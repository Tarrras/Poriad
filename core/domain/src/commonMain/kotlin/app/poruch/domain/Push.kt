package app.poruch.domain

/** Платформа пуш-токена, як її називає `push_tokens.platform`. */
object PushPlatform {
    const val ANDROID = "android"
    const val IOS = "ios"
}

/** Реєстрація пристрою для пушів. Токен дає платформа (FCM або APNs), сервер шле сам. */
interface PushTokens {
    suspend fun register(token: String, platform: String)
    suspend fun unregister(token: String)
}
