package app.poruch.shared

import app.poruch.domain.HomeLocation

/** Реекспорт, щоб платформний модуль залежав лише від `shared`. */
typealias SecureSessionStore = app.poruch.domain.SecureSessionStore

/**
 * Бекенд, у який ходить збірка. Вибирає платформа (Android flavor, iOS конфігурація), значення —
 * зі згенерованого [BuildConfig] (gradle.properties, `poriad.*`). Ключі публічні; service-role у клієнті не буває.
 *
 * Застаріло: enum тримає обидва середовища, тож prod-бінарник несе адресу й ключ dev. Платформи
 * будують [AppConfig] зі значень свого конфігу збірки (Android flavor `buildConfigField`, iOS
 * xcconfig → Info.plist); коли обидві перейдуть, enum і генерація `BuildConfig` у `shared` зникнуть.
 */
@Deprecated("Значення середовища — з конфігу збірки платформи: AppConfig(supabaseUrl, publishableKey, authScheme = …)")
enum class AppEnvironment(
    val supabaseUrl: String,
    val publishableKey: String,
    val authScheme: String
) {
    DEV(BuildConfig.DEV_SUPABASE_URL, BuildConfig.DEV_SUPABASE_KEY, BuildConfig.DEV_AUTH_SCHEME),
    PROD(BuildConfig.PROD_SUPABASE_URL, BuildConfig.PROD_SUPABASE_KEY, BuildConfig.PROD_AUTH_SCHEME)
}

/** Що збірці треба, щоб дістатися бекенду і знати, де відкривати мапу. */
data class AppConfig(
    val supabaseUrl: String,
    val publishableKey: String,
    val home: HomeLocation = HomeLocation.Kyiv,
    /** Схема `<scheme>://auth/callback` з листів Auth; має збігатися з зареєстрованою платформою. */
    val authScheme: String = "poriad",
    /** Версія застосунку (versionName / CFBundleShortVersionString): іде в User-Agent геокодера. */
    val appVersion: String = "dev",
    /** Photon. Власного сервера поки нема — публічний komoot, тому чесний [userAgent] обов'язковий. */
    val geocoderUrl: String = "https://photon.komoot.io/api/"
) {
    /** Для Swift: ObjC-експорт не знає аргументів за замовчуванням, а iOS досі кличе чотирма. */
    constructor(supabaseUrl: String, publishableKey: String, home: HomeLocation, authScheme: String) :
        this(supabaseUrl, publishableKey, home, authScheme, appVersion = "dev")

    /** Політика публічного Photon: застосунок називає себе і дає контакт. */
    val userAgent: String get() = "Poriad/$appVersion (+https://poriad.app; hello@poriad.app)"
}

class Subscription(private val cancel: () -> Unit) {
    fun close() = cancel()
}
