package app.poruch.domain

/**
 * Продуктові події для воронки. Сінк ставить платформа (Firebase Analytics); без нього — тиша.
 * Правило те саме, що в [PoruchLog]: жодних email, імен, текстів чи id людей і подій. Лише
 * факт дії та грубі виміри (категорія, місто), за якими ділять воронку.
 * Словник подій — docs/analytics.md.
 */
object PoruchAnalytics {
    var sink: ((name: String, params: Map<String, String>) -> Unit)? = null

    /**
     * Платформний перемикач збору (Firebase `setAnalyticsCollectionEnabled`). Кличеться одразу
     * при встановленні з поточним [enabled] і далі на кожну зміну.
     */
    var collection: ((enabled: Boolean) -> Unit)? = null
        set(value) { field = value; value?.invoke(enabled) }

    /** Людина дозволила збір. Вимкнено — події в [sink] не йдуть. Ставить `PoruchApp` з налаштування пристрою. */
    var enabled: Boolean = true
        set(value) { if (field != value) { field = value; collection?.invoke(value) } }

    fun track(name: String, vararg params: Pair<String, Any?>) {
        if (!enabled) return
        sink?.invoke(name, params.mapNotNull { (key, value) -> value?.let { key to it.toString() } }.toMap())
    }
}

/** Згода на аналітику. Прапорець пристрою, як і нагадування: за замовчуванням збір увімкнено. */
interface AnalyticsPreferenceStore {
    fun enabled(): Boolean
    fun setEnabled(enabled: Boolean)
}
