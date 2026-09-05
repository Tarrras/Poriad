package app.poruch.data

import app.poruch.domain.*
import io.ktor.http.HttpMethod
import io.ktor.http.Url
import io.ktor.http.parseQueryString
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import kotlin.time.Clock

class SupabaseAuthRepository(private val api: ApiClient, private val store: SecureSessionStore): AuthRepository {
    private val mutable = MutableStateFlow(readStored())
    override val session = mutable.asStateFlow()
    private val mutex = Mutex()
    private fun readStored(): UserSession? = store.read()?.let { raw ->
        runCatching { decode(api.json.parseToJsonElement(raw).jsonObject) }.getOrElse { store.clear(); null }
    }
    private fun decode(value: JsonObject): UserSession {
        val uid = value["user"]?.jsonObject?.string("id") ?: value.string("user_id")
        require(uid.isNotBlank() && value.string("access_token").isNotBlank())
        return UserSession(uid, value.string("access_token"), value.string("refresh_token"),
            value["expires_at"]?.jsonPrimitive?.longOrNull ?: (Clock.System.now().epochSeconds + (value["expires_in"]?.jsonPrimitive?.longOrNull ?: 3600)))
    }
    private fun persist(value: JsonObject) {
        val session = decode(value)
        store.write(buildJsonObject {
            put("user_id", session.userId); put("access_token", session.accessToken)
            put("refresh_token", session.refreshToken); put("expires_at", session.expiresAt)
        }.toString())
        mutable.value = session
    }
    override suspend fun signIn(email: String, password: String) = mutex.withLock {
        val result = api.request("/auth/v1/token", HttpMethod.Post, buildJsonObject {
            put("email", email.trim()); put("password", password)
        }, query=mapOf("grant_type" to "password"))
        persist(result.jsonObject)
    }
    override suspend fun signUp(email: String, password: String, name: String): Boolean = mutex.withLock {
        val result = api.request("/auth/v1/signup", HttpMethod.Post, buildJsonObject {
            put("email", email.trim()); put("password", password)
            put("data", buildJsonObject { put("display_name", name.trim()) })
        }, query=mapOf("redirect_to" to "poruch://auth/callback")).jsonObject
        if (result.string("access_token").isNotEmpty()) { persist(result); true } else false
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
        } catch (e: AppException) {
            if (e.kind == Failure.AUTH || e.kind == Failure.VALIDATION) { store.clear(); mutable.value = null }
            throw e
        }
    }
    override suspend fun requestPasswordReset(email: String) {
        api.request("/auth/v1/recover", HttpMethod.Post, buildJsonObject { put("email", email.trim()) }, query=mapOf("redirect_to" to "poruch://auth/callback"))
    }
    override suspend fun updatePassword(password: String) {
        api.request("/auth/v1/user", HttpMethod.Put, buildJsonObject { put("password",password) }, token=accessToken())
    }
    override suspend fun handleCallback(url: String): Boolean = mutex.withLock {
        val parsed = Url(url)
        require(parsed.protocol.name == "poruch" && parsed.host == "auth" && parsed.encodedPath == "/callback")
        val values = parseQueryString(parsed.fragment)
        val token = values["access_token"] ?: throw AppException(Failure.AUTH,"Посилання не містить сесії. Увійдіть після підтвердження email")
        val refresh = values["refresh_token"] ?: throw AppException(Failure.AUTH,"Відкрийте нове посилання з листа")
        // Validate the bearer with Auth before trusting any incoming deep-link identity.
        val user = api.request("/auth/v1/user", token=token).jsonObject
        persist(buildJsonObject {
            put("user",user); put("access_token",token); put("refresh_token",refresh)
            put("expires_at",Clock.System.now().epochSeconds + (values["expires_in"]?.toLongOrNull()?.coerceIn(0,3600) ?: 0))
        })
        values["type"] == "recovery"
    }

}
