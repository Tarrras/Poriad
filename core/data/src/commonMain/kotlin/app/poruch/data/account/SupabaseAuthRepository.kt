package app.poruch.data.account
import app.poruch.data.api.string
import app.poruch.data.api.ApiClient

import app.poruch.domain.*
import io.ktor.http.HttpMethod
import io.ktor.http.Url
import io.ktor.http.parseQueryString
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import kotlin.time.Clock

/**
 * Auth через GoTrue REST. У сховищі один JSON: поля сесії плюс, поки триває підтвердження пошти
 * чи відновлення, `pkce_verifier` і `pkce_flow`. Лист несе лише одноразовий `code` (PKCE):
 * перехопити `poriad://` може інший застосунок, але без verifier код не обміняти, а колбек із
 * готовими токенами у фрагменті ми більше не приймаємо — так закрито і session fixation.
 */
class SupabaseAuthRepository(private val api: ApiClient, private val store: SecureSessionStore): AuthRepository {
    private val mutable = MutableStateFlow(readStored())
    override val session = mutable.asStateFlow()
    private val mutex = Mutex()

    private fun stored(): JsonObject? = store.read()?.let { raw ->
        runCatching { api.json.parseToJsonElement(raw).jsonObject }.getOrElse { store.clear(); null }
    }
    private fun readStored(): UserSession? = stored()?.takeIf { it.string("access_token").isNotBlank() }?.let { value ->
        runCatching { decode(value) }.getOrElse { store.clear(); null }
    }
    private fun decode(value: JsonObject): UserSession {
        val uid = value["user"]?.jsonObject?.string("id") ?: value.string("user_id")
        require(uid.isNotBlank() && value.string("access_token").isNotBlank())
        return UserSession(uid, value.string("access_token"), value.string("refresh_token"),
            value["expires_at"]?.jsonPrimitive?.longOrNull ?: (Clock.System.now().epochSeconds + (value["expires_in"]?.jsonPrimitive?.longOrNull ?: 3600)))
    }
    private fun persist(value: JsonObject) {
        val session = decode(value)
        // Успішний обмін коду чи вхід закриває PKCE-раунд: verifier більше не потрібен.
        store.write(buildJsonObject {
            put("user_id", session.userId); put("access_token", session.accessToken)
            put("refresh_token", session.refreshToken); put("expires_at", session.expiresAt)
        }.toString())
        mutable.value = session
    }
    /** Кладе verifier поруч із сесією (якщо вона є), не чіпаючи її. */
    private fun rememberVerifier(verifier: String, flow: String) {
        val current = stored() ?: JsonObject(emptyMap())
        store.write(JsonObject(current + mapOf("pkce_verifier" to JsonPrimitive(verifier), "pkce_flow" to JsonPrimitive(flow))).toString())
    }
    private fun pkceParams(verifier: String) = buildJsonObject {
        put("code_challenge", Pkce.challenge(verifier)); put("code_challenge_method", "s256")
    }

    override suspend fun signIn(email: String, password: String) = mutex.withLock {
        val result = api.request("/auth/v1/token", HttpMethod.Post, buildJsonObject {
            put("email", email.trim()); put("password", password)
        }, query=mapOf("grant_type" to "password"))
        persist(result.jsonObject)
    }
    override suspend fun signUp(email: String, password: String, name: String, birthDate: String): Boolean = mutex.withLock {
        val verifier = Pkce.newVerifier()
        val result = api.request("/auth/v1/signup", HttpMethod.Post, buildJsonObject {
            put("email", email.trim()); put("password", password)
            // Дата народження їде в метаданих: тригер акаунта відмовляє неповнолітнім у тій самій транзакції.
            put("data", buildJsonObject { put("display_name", name.trim()); put("birth_date", birthDate) })
            pkceParams(verifier).forEach { (k, v) -> put(k, v) }
        }, query=mapOf("redirect_to" to CALLBACK)).jsonObject
        if (result.string("access_token").isNotEmpty()) { persist(result); true }
        else { rememberVerifier(verifier, FLOW_SIGNUP); false }
    }
    override suspend fun signOut() = mutex.withLock {
        val token = mutable.value?.accessToken
        try { if (token != null) api.request("/auth/v1/logout", HttpMethod.Post, token=token) }
        finally { store.clear(); mutable.value = null }
    }
    override suspend fun accessToken(): String? = mutex.withLock {
        val session = mutable.value ?: return@withLock null
        if (session.expiresAt > Clock.System.now().epochSeconds + 60) return@withLock session.accessToken
        try {
            val result = api.request("/auth/v1/token", HttpMethod.Post, buildJsonObject { put("refresh_token", session.refreshToken) }, query=mapOf("grant_type" to "refresh_token"))
            persist(result.jsonObject)
            mutable.value?.accessToken
        } catch (e: AppFailure) {
            // Відмова в оновленні — сесія вичерпана; решта помилок може бути тимчасовою.
            if (e.error is AppError.SessionRequired || e.error is AppError.InvalidCredentials || e.error is AppError.Rejected) {
                store.clear(); mutable.value = null
            }
            throw e
        }
    }
    override suspend fun requestPasswordReset(email: String) = mutex.withLock {
        val verifier = Pkce.newVerifier()
        api.request("/auth/v1/recover", HttpMethod.Post, buildJsonObject {
            put("email", email.trim())
            pkceParams(verifier).forEach { (k, v) -> put(k, v) }
        }, query=mapOf("redirect_to" to CALLBACK))
        rememberVerifier(verifier, FLOW_RECOVERY)
    }
    override suspend fun updatePassword(password: String) {
        api.request("/auth/v1/user", HttpMethod.Put, buildJsonObject { put("password",password) }, token=accessToken())
    }
    override suspend fun verifyPassword(password: String) {
        val token = accessToken() ?: fail(AppError.SessionRequired)
        val email = api.request("/auth/v1/user", token=token).jsonObject.string("email")
        if (email.isBlank()) fail(AppError.SessionRequired)
        // Окремий grant без persist: нам потрібна лише відповідь «так, це пароль власника».
        api.request("/auth/v1/token", HttpMethod.Post, buildJsonObject {
            put("email", email); put("password", password)
        }, query=mapOf("grant_type" to "password"))
    }
    override suspend fun deleteAccount() {
        mutex.withLock {
            val token = mutable.value?.accessToken ?: fail(AppError.SessionRequired)
            try { api.request("/rest/v1/rpc/delete_my_account", HttpMethod.Post, buildJsonObject {}, token=token, prefer="return=minimal") }
            finally { store.clear(); mutable.value = null }
        }
    }
    /**
     * Приймає лише `poriad://auth/callback?code=…`. Код обмінюється на сесію разом із verifier,
     * який чекає у сховищі з моменту реєстрації чи запиту відновлення; без нього (лист відкрили
     * на іншому пристрої) — [AppError.LinkOnAnotherDevice]. Повертає true для відновлення пароля.
     */
    override suspend fun handleCallback(url: String): Boolean = mutex.withLock {
        val parsed = Url(url)
        require(parsed.protocol.name == "poriad" && parsed.host == "auth" && parsed.encodedPath == "/callback")
        val code = parsed.parameters["code"] ?: run {
            // Старий implicit-колбек з токенами у фрагменті: чужий застосунок міг би підсунути
            // свою сесію. Не довіряємо.
            if (parseQueryString(parsed.fragment)["access_token"] != null) fail(AppError.SessionRequired)
            parsed.parameters["error_description"]?.let { fail(AppError.Rejected) }
            fail(AppError.SessionRequired)
        }
        val pending = stored()
        val verifier = pending?.string("pkce_verifier")?.takeIf { it.isNotBlank() } ?: fail(AppError.LinkOnAnotherDevice)
        val recovery = pending.string("pkce_flow") == FLOW_RECOVERY
        val result = try {
            api.request("/auth/v1/token", HttpMethod.Post, buildJsonObject {
                put("auth_code", code); put("code_verifier", verifier)
            }, query=mapOf("grant_type" to "pkce")).jsonObject
        } catch (e: AppFailure) {
            if (e.error is AppError.Rejected || e.error is AppError.NotOwner) fail(AppError.LinkOnAnotherDevice) else throw e
        }
        persist(result)
        recovery
    }

    private companion object {
        const val CALLBACK = "poriad://auth/callback"
        const val FLOW_SIGNUP = "signup"
        const val FLOW_RECOVERY = "recovery"
    }
}
