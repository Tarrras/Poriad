package app.poruch.shared

import app.poruch.domain.HomeLocation

/** Реекспорт, щоб платформний модуль залежав лише від `shared`. */
typealias SecureSessionStore = app.poruch.domain.SecureSessionStore

/**
 * Бекенд, у який ходить збірка. Вибирає платформа (Android flavor, iOS конфігурація), значення —
 * зі згенерованого [BuildConfig] (gradle.properties, `poriad.*`). Ключі публічні; service-role у клієнті не буває.
 */
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
    val authScheme: String = "poriad"
)

class Subscription(private val cancel: () -> Unit) {
    fun close() = cancel()
}
