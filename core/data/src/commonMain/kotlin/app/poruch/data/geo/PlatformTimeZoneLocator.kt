package app.poruch.data.geo

import app.poruch.domain.PoruchLog
import app.poruch.domain.TimeZoneLocator
import kotlinx.datetime.TimeZone

/**
 * Обгортка над платформенним [timeZoneAt], яка зводить назву до сучасної: у базі, міграціях
 * та імпорті пояс пишеться `Europe/Kyiv`, і двох написань бути не має.
 */
class PlatformTimeZoneLocator(
    /** Параметром, щоб тест міг перевірити зведення назви: на JVM [timeZoneAt] нічого не знає. */
    private val lookup: suspend (Double, Double) -> String? = ::timeZoneAt
) : TimeZoneLocator {
    override suspend fun zoneAt(latitude: Double, longitude: Double): String? =
        runCatching { lookup(latitude, longitude) }.getOrNull()?.let(::modernZoneName)
}

/**
 * Пояси, перейменовані в tzdb 2022b. Android ICU досі вважає канонічним `Europe/Kiev`, iOS
 * одразу дає нову назву. Список навмисно короткий: лише те, що бачили на своїх пристроях.
 */
private val renamed = mapOf(
    "Europe/Kiev" to "Europe/Kyiv",
    "Europe/Uzhgorod" to "Europe/Kyiv",
    "Europe/Zaporozhye" to "Europe/Kyiv"
)

internal fun modernZoneName(id: String): String {
    val modern = renamed[id] ?: return id
    // Нову назву беремо, лише якщо її знає система, інакше впаде перше ж форматування дати.
    if (modern !in TimeZone.availableZoneIds) return id
    PoruchLog.d("geo") { "$id → $modern" }
    return modern
}
