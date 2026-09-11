package app.poruch.data.geo

import app.poruch.domain.PoruchLog
import app.poruch.domain.TimeZoneLocator
import kotlinx.datetime.TimeZone

/**
 * Доменна межа над платформенним пошуком поясу. Сам пошук — в [timeZoneAt]: кожна платформа вміє
 * це по-своєму, а застосунок нагорі про різницю не знає.
 *
 * Тут же назва зводиться до сучасної. Це не косметика: `Europe/Kyiv` — те, як пояс називається в
 * tzdb від 2022b, як його пишуть міграції, конвеєр імпорту й самі дані. Якби застосунок писав
 * `Europe/Kiev`, у базі жили б два написання одного поясу.
 */
class PlatformTimeZoneLocator(
    /**
     * Платформенний пошук. Параметром — щоб зв'язку «знайшли пояс → записали сучасну назву» можна
     * було перевірити тестом: сам [timeZoneAt] на JVM нічого не знає й не має знати.
     */
    private val lookup: suspend (Double, Double) -> String? = ::timeZoneAt
) : TimeZoneLocator {
    override suspend fun zoneAt(latitude: Double, longitude: Double): String? =
        runCatching { lookup(latitude, longitude) }.getOrNull()?.let(::modernZoneName)
}

/**
 * Пояси, перейменовані в tzdb 2022b: київський став `Europe/Kyiv`, а ужгородський і запорізький
 * злилися з ним.
 *
 * Потрібно це тому, що база часових поясів на пристрої може бути старшою за перейменування.
 * Перевірено на Android 16: ICU там пропонує обидві назви — і `Europe/Kiev`, і `Europe/Kyiv`, —
 * але канонічною досі вважає стару. iOS ту саму точку називає одразу правильно, тож ця таблиця
 * для нього — порожня робота, і хай так лишається.
 *
 * Список короткий свідомо: сюди потрапляє лише те, що ми справді бачили на своїх пристроях, а не
 * увесь `backward`-файл tzdb. Перекладати назви, яких ми не перевіряли, означало б вигадувати.
 */
private val renamed = mapOf(
    "Europe/Kiev" to "Europe/Kyiv",
    "Europe/Uzhgorod" to "Europe/Kyiv",
    "Europe/Zaporozhye" to "Europe/Kyiv"
)

internal fun modernZoneName(id: String): String {
    val modern = renamed[id] ?: return id
    // Нову назву беремо лише тоді, коли її знає сама система: інакше ми віддали б редактору
    // ідентифікатор, на якому впаде перше ж форматування дати.
    if (modern !in TimeZone.availableZoneIds) return id
    PoruchLog.d("geo") { "$id → $modern" }
    return modern
}
