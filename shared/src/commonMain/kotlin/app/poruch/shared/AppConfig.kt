package app.poruch.shared

import app.poruch.domain.HomeLocation

/** Реекспорт, щоб платформний модуль залежав лише від `shared`. */
typealias SecureSessionStore = app.poruch.domain.SecureSessionStore

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
    /** Політика публічного Photon: застосунок називає себе і дає контакт. */
    val userAgent: String get() = "Poriad/$appVersion (+https://poriad.app; hello@poriad.app)"
}

class Subscription(private val cancel: () -> Unit) {
    fun close() = cancel()
}
