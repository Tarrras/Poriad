package app.poruch.domain

/** Платформа пуш-токена, як її називає `push_tokens.platform`. */
object PushPlatform {
    const val ANDROID = "android"
    const val IOS = "ios"
}

/** Реєстрація пристрою для пушів. Токен дає платформа (FCM або APNs), сервер шле сам. */
interface PushTokens {
    suspend fun register(token: String, platform: String)
    /**
     * [accessToken] — ключ акаунта, під яким токен реєстрували, коли його сесії вже нема (вихід
     * офлайн, відкликана сесія). Null — поточна сесія.
     */
    suspend fun unregister(token: String, accessToken: String? = null)
}

/**
 * Токен, який не вдалося зняти, коли акаунт пішов з телефона, і чим його знімати. Без цього
 * сповіщення чату акаунта A далі падають на екран блокування після його виходу.
 */
data class PendingUnregister(val token: String, val userId: String, val accessToken: String, val expiresAt: Long)

/** Незнятий токен. Належить пристрою: вихід з акаунта його не стирає. */
interface PendingUnregisterStore {
    fun read(): PendingUnregister?
    fun write(value: PendingUnregister?)
}
