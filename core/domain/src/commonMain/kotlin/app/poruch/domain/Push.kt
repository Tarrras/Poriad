package app.poruch.domain

/** Платформа пуш-токена, як її називає `push_tokens.platform`. */
enum class PushPlatform(val key: String) { ANDROID("android"), IOS("ios") }

/** Реєстрація пристрою для пушів. Токен дає платформа (FCM або APNs), сервер шле сам. */
interface PushTokens {
    suspend fun register(token: String, platform: PushPlatform)
    /**
     * [accessToken] — ключ акаунта, під яким токен реєстрували, коли його сесії вже нема (сервер
     * відкликав сесію). Null — поточна сесія.
     */
    suspend fun unregister(token: String, accessToken: String? = null)
    /**
     * Знімає [token] акаунта [userId] без сесії (`release_push_token`, роль anon): так для повтору після виходу
     * офлайн не треба зберігати ключ доступу. Інший акаунт уже взяв токен собі — сервер нічого не чіпає.
     */
    suspend fun release(token: String, userId: String)

    /**
     * Канал повернення (docs/guest-channel.md): пристрій відкрили з дозволом і дайджестом — сервер знає `last_seen`,
     * місто ([city] з [HomeLocation.covered], null — своє місце) і ключі [EventCategory] з інтересів. Без акаунта теж.
     */
    suspend fun touchDevice(token: String, platform: PushPlatform, city: String?, interests: List<String>)
    suspend fun forgetDevice(token: String)

    /**
     * Радар артистів (docs/artist-radar.md): місто пристрою з дозволом і артисти гостя ([artists] — id; в акаунта
     * порожньо, його артисти в підписках). Від дайджесту не залежить, на відміну від [touchDevice].
     */
    suspend fun setRadar(token: String, platform: PushPlatform, city: String?, artists: List<String>) {}
    suspend fun forgetRadar(token: String) {}

    /** «Мої місця» (docs/my-places.md): повний список зон пристрою; забуваються разом з ним у [forgetRadar]. */
    suspend fun setZones(token: String, platform: PushPlatform, city: String?, zones: List<Zone>) {}
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
 * Токен, який не вдалося зняти, коли акаунт пішов з телефона, і чий він. Без цього
 * сповіщення чату акаунта A далі падають на екран блокування після його виходу. Ключа доступу тут нема:
 * запис лежить у звичайному кеші, а знімає [PushTokens.release] за токеном і акаунтом.
 */
data class PendingUnregister(val token: String, val userId: String)

/** Незнятий токен. Належить пристрою: вихід з акаунта його не стирає. */
interface PendingUnregisterStore {
    fun read(): PendingUnregister?
    fun write(value: PendingUnregister?)
}
