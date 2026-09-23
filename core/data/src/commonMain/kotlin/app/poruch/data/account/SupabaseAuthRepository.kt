package app.poruch.data.account
import app.poruch.data.api.string
import app.poruch.data.api.ApiClient

import app.poruch.domain.*
import io.ktor.http.HttpMethod
import io.ktor.http.Url
import io.ktor.http.parseQueryString
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import kotlin.time.Clock

/**
 * Auth через GoTrue REST. У сховищі один JSON: поля сесії плюс, поки триває підтвердження пошти
 * чи відновлення, verifier кожного потоку (`pkce_signup`, `pkce_recovery`): лист реєстрації й лист
 * відновлення можуть чекати одночасно, і другий не має затирати перший. Лист несе лише одноразовий `code` (PKCE):
 * перехопити `poriad://` може інший застосунок, але без verifier код не обміняти, а колбек із
 * готовими токенами у фрагменті ми більше не приймаємо — так закрито і session fixation.
 */
class SupabaseAuthRepository(
    private val api: ApiClient,
    private val store: SecureSessionStore,
    private val scheme: String = "poriad"
): AuthRepository {
    private val callback = "$scheme://auth/callback"
    private val mutable = MutableStateFlow(readStored())
    override val session = mutable.asStateFlow()
    private val mutex = Mutex()

    init {
        // 401 від API — токен помер раніше, ніж думав годинник: ApiClient просить свіжий тут.
        api.reauthorize = ::refreshRejected
    }

    private fun stored(): JsonObject? = store.read()?.let { raw ->
        runCatching { api.json.parseToJsonElement(raw).jsonObject }.getOrElse { store.clear(); null }
    }
    private fun readStored(): UserSession? = stored()?.takeIf { it.string("access_token").isNotBlank() }?.let { value ->
        runCatching { decode(value) }.getOrElse { store.clear(); null }
    }
    private fun decode(value: JsonObject): UserSession {
        val uid = value["user"]?.jsonObject?.string("id") ?: value.string("user_id")
        require(uid.isNotBlank() && value.string("access_token").isNotBlank())
        // Строк рахуємо від годинника пристрою: `expires_at` сервера з годинником, що відстає чи
        // спішить, давав або вічно «свіжий» мертвий токен, або refresh на кожен запит. Відповідь
        // сервера несе `expires_in`; збережена сесія — вже наш локальний `expires_at`.
        val expiresAt = value["expires_in"]?.jsonPrimitive?.longOrNull?.let { Clock.System.now().epochSeconds + it }
            ?: value["expires_at"]?.jsonPrimitive?.longOrNull ?: (Clock.System.now().epochSeconds + 3600)
        return UserSession(uid, value.string("access_token"), value.string("refresh_token"), expiresAt)
    }
    /** Пише сесію. Verifier-и інших потоків лишаються: [dropVerifier] — той, що щойно обміняли. */
    private fun persist(value: JsonObject, dropVerifier: String? = null) {
        val session = decode(value)
        val pending = stored().orEmpty().filterKeys { it.startsWith(PKCE_PREFIX) && it != dropVerifier }
            .let { if (LEGACY_VERIFIER in it) it else it - LEGACY_FLOW }
        store.write(JsonObject(pending + buildJsonObject {
            put("user_id", session.userId); put("access_token", session.accessToken)
            put("refresh_token", session.refreshToken); put("expires_at", session.expiresAt)
        }).toString())
        mutable.value = session
    }
    private fun clearSession() { store.clear(); mutable.value = null }
    /** Кладе verifier потоку поруч із сесією (якщо вона є), не чіпаючи її. */
    private fun rememberVerifier(verifier: String, flow: String) {
        val current = stored() ?: JsonObject(emptyMap())
        store.write(JsonObject(current + (PKCE_PREFIX + flow to JsonPrimitive(verifier))).toString())
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
        }, query=mapOf("redirect_to" to callback)).jsonObject
        if (result.string("access_token").isNotEmpty()) { persist(result); true }
        else { rememberVerifier(verifier, FLOW_SIGNUP); false }
    }
    override suspend fun signOut() {
        // Свіжий токен до м'ютекса: з простроченим сервер відмовив би, і refresh-токен лишився б живим.
        val token = try { accessToken() } catch (e: CancellationException) { throw e } catch (e: Exception) { null }
        mutex.withLock {
            try { if (token != null) api.request("/auth/v1/logout", HttpMethod.Post, token=token, query=mapOf("scope" to "local"), reauthorizable=false) }
            finally { clearSession() }
        }
    }
    override suspend fun accessToken(): String? = mutex.withLock {
        val session = mutable.value ?: return@withLock null
        if (session.expiresAt > Clock.System.now().epochSeconds + 60) return@withLock session.accessToken
        refresh(session)
    }
    /** Сервер відхилив [rejected] (401). Якщо його вже замінили — новий; інакше примусовий refresh. */
    private suspend fun refreshRejected(rejected: String): String? = mutex.withLock {
        val session = mutable.value ?: return@withLock null
        if (session.accessToken != rejected) return@withLock session.accessToken
        refresh(session)
    }
    /** Лише під [mutex]. */
    private suspend fun refresh(session: UserSession): String? = try {
        val result = api.request("/auth/v1/token", HttpMethod.Post, buildJsonObject { put("refresh_token", session.refreshToken) }, query=mapOf("grant_type" to "refresh_token"))
        persist(result.jsonObject)
        mutable.value?.accessToken
    } catch (e: AppFailure) {
        // Відмова в оновленні — сесія вичерпана; решта помилок може бути тимчасовою. Пуш-токен
        // цього акаунта зніме спільний код: він бачить, що сесія зникла не через вихід.
        if (e.error is AppError.SessionRequired || e.error is AppError.InvalidCredentials || e.error is AppError.Rejected) {
            PoruchLog.w("auth") { "refresh refused (${e.error}), session dropped" }
            clearSession()
        }
        throw e
    }
    override suspend fun requestPasswordReset(email: String) = mutex.withLock {
        val verifier = Pkce.newVerifier()
        api.request("/auth/v1/recover", HttpMethod.Post, buildJsonObject {
            put("email", email.trim())
            pkceParams(verifier).forEach { (k, v) -> put(k, v) }
        }, query=mapOf("redirect_to" to callback))
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
        val proof = api.request("/auth/v1/token", HttpMethod.Post, buildJsonObject {
            put("email", email); put("password", password)
        }, query=mapOf("grant_type" to "password")).jsonObject.string("access_token")
        // Grant створив на сервері ще одну сесію: закриваємо саме її (`scope=local`, бо за
        // замовчуванням logout глобальний і вийшов би й звідси). Збій — лише зайва сесія до її строку.
        if (proof.isNotBlank()) try {
            api.request("/auth/v1/logout", HttpMethod.Post, token=proof, query=mapOf("scope" to "local"), reauthorizable=false)
        } catch (e: CancellationException) { throw e } catch (e: Exception) { PoruchLog.w("auth") { "verification session not closed: ${e.asAppError()}" } }
    }
    override suspend fun deleteAccount() {
        val token = accessToken() ?: fail(AppError.SessionRequired)
        try {
            // Edge Function під service role: прибирає фото зі Storage і видаляє користувача. Відповідь — `{"deleted":true}`.
            api.request("/functions/v1/delete-account", HttpMethod.Post, buildJsonObject {}, token=token)
        } catch (e: AppFailure) {
            // 401 — сесії на сервері вже нема, тож і тут тримати нічого. Решта (мережа, 5xx) лишає
            // людину в акаунті: інакше вона «вийшла», а акаунт з усім живий.
            if (e.error is AppError.SessionRequired) mutex.withLock { clearSession() }
            throw e
        }
        mutex.withLock { clearSession() }
    }
    /**
     * Приймає лише `<scheme>://auth/callback?code=…`. Код обмінюється на сесію разом із verifier,
     * який чекає у сховищі з моменту реєстрації чи запиту відновлення. Лист не каже, якого він потоку,
     * тож пробуємо verifier-и по черзі: чужий сервер відхиляє як `bad_code_verifier`, не спалюючи код.
     * Verifier-а нема (посилання вже використане, старе чи з іншого пристрою) — [AppError.LinkExpired];
     * є, але жоден не підійшов — [AppError.LinkOnAnotherDevice]. Повертає true для відновлення пароля.
     */
    override suspend fun handleCallback(url: String): Boolean = mutex.withLock {
        val parsed = Url(url)
        require(parsed.protocol.name == scheme && parsed.host == "auth" && parsed.encodedPath == "/callback")
        val code = parsed.parameters["code"] ?: run {
            // Старий implicit-колбек з токенами у фрагменті: чужий застосунок міг би підсунути
            // свою сесію. Не довіряємо.
            if (parseQueryString(parsed.fragment)["access_token"] != null) fail(AppError.SessionRequired)
            // Сервер сам каже, що посилання прострочене (`otp_expired`).
            parsed.parameters["error_description"]?.let {
                fail(if (parsed.parameters["error_code"]?.endsWith("_expired") == true) AppError.LinkExpired else AppError.Rejected)
            }
            fail(AppError.SessionRequired)
        }
        val pending = stored() ?: JsonObject(emptyMap())
        // Ключ verifier-а → чи це відновлення. Старий формат (один `pkce_verifier`) — до оновлення застосунку.
        val candidates = buildList {
            listOf(FLOW_RECOVERY, FLOW_SIGNUP).forEach { flow -> add(PKCE_PREFIX + flow to (flow == FLOW_RECOVERY)) }
            add(LEGACY_VERIFIER to (pending.string(LEGACY_FLOW) == FLOW_RECOVERY))
        }.filter { (key, _) -> pending.string(key).isNotBlank() }
        if (candidates.isEmpty()) fail(AppError.LinkExpired)
        for ((key, recovery) in candidates) {
            val result = try {
                api.request("/auth/v1/token", HttpMethod.Post, buildJsonObject {
                    put("auth_code", code); put("code_verifier", pending.string(key))
                }, query=mapOf("grant_type" to "pkce")).jsonObject
            } catch (e: AppFailure) {
                if (e.error is AppError.LinkExpired) throw e
                if (e.error is AppError.Rejected || e.error is AppError.NotOwner) continue
                throw e
            }
            persist(result, dropVerifier = key)
            return@withLock recovery
        }
        fail(AppError.LinkOnAnotherDevice)
    }

    private companion object {
        const val FLOW_SIGNUP = "signup"
        const val FLOW_RECOVERY = "recovery"
        const val PKCE_PREFIX = "pkce_"
        /** Поля однопотокового формату. Ключі з [PKCE_PREFIX], тож [persist] їх теж переносить. */
        const val LEGACY_VERIFIER = "pkce_verifier"
        const val LEGACY_FLOW = "pkce_flow"
    }
}
