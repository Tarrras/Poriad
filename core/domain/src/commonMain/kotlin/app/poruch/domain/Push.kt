package app.poruch.domain

/** Платформа пуш-токена, як її називає `push_tokens.platform`. */
enum class PushPlatform(val key: String) { ANDROID("android"), IOS("ios") }

/** Реєстрація пристрою для пушів. Токен дає платформа (FCM або APNs), сервер шле сам. */
interface PushTokens {
    suspend fun register(token: String, platform: PushPlatform)
    /**
     * [accessToken] — ключ акаунта, під яким токен реєстрували, коли його сесії вже нема (вихід
     * офлайн, відкликана сесія). Null — поточна сесія.
     */
    suspend fun unregister(token: String, accessToken: String? = null)

    /**
     * Канал повернення (docs/guest-channel.md): пристрій відкрили з дозволом і дайджестом — сервер знає `last_seen`,
     * місто ([city] з [HomeLocation.covered], null — своє місце) і ключі [EventCategory] з інтересів. Без акаунта теж.
     */
    suspend fun touchDevice(token: String, platform: PushPlatform, city: String?, interests: List<String>)
    suspend fun forgetDevice(token: String)
}

/** Що сервер востаннє почув про пристрій від [PushTokens.touchDevice] і коли ([at], epoch-секунди). */
data class DeviceTouch(val token: String, val city: String?, val interests: List<String>, val at: Long)

/**
 * Останній [DeviceTouch]. Належить пристрою, як і дайджест: переживає вихід з акаунта. Назви методів свої, а не
 * `read`/`write`: Kotlin/Native інакше перейменував би `write(value:)` у протоколах, які вже реалізує iOS.
 */
interface DeviceTouchStore {
    fun last(): DeviceTouch?
    fun save(touch: DeviceTouch?)
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
