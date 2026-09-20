package app.poruch.domain

/**
 * Продуктові події для воронки. Сінк ставить платформа (Firebase Analytics); без нього — тиша.
 * Правило те саме, що в [PoruchLog]: жодних email, імен, текстів чи id людей і подій. Лише
 * факт дії та грубі виміри (категорія, місто), за якими ділять воронку.
 * Словник подій — docs/analytics.md.
 */
object PoruchAnalytics {
    var sink: ((name: String, params: Map<String, String>) -> Unit)? = null

    fun track(name: String, vararg params: Pair<String, Any?>) {
        sink?.invoke(name, params.mapNotNull { (key, value) -> value?.let { key to it.toString() } }.toMap())
    }
}
