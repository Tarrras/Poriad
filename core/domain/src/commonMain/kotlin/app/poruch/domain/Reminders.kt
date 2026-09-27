package app.poruch.domain

import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.atTime
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.plus
import kotlinx.datetime.toInstant
import kotlinx.datetime.toLocalDateTime

/**
 * Локальне нагадування про подію: що сказати і коли. Час в epoch-мілісекундах, бо його
 * читають AlarmManager і UNUserNotificationCenter, а не бізнес-логіка.
 */
data class EventReminder(val eventId: String, val title: String, val address: String, val fireAtEpochMillis: Long)

/**
 * Системний планувальник нагадувань. Реалізує платформа; отримує повний список і сама
 * вирішує, що скасувати, а що лишити. Порожній список означає «нічого не нагадувати».
 */
interface ReminderScheduler {
    fun replace(reminders: List<EventReminder>)

    /** Єдиний дайджест вихідних: новий замінює старий, null знімає. */
    fun replaceDigest(digest: WeekendDigest?)
}

/** Прапорець «нагадувати» на пристрої. Переживає вихід з акаунта, як і відповіді онбордингу. */
interface ReminderPreferenceStore {
    fun enabled(): Boolean
    fun setEnabled(enabled: Boolean)

    /** Дайджест вихідних. За замовчуванням так: без дозволу системи він однаково мовчить. */
    fun digestEnabled(): Boolean
    fun setDigestEnabled(enabled: Boolean)
}

/**
 * Пʼятничне «що поруч на вихідних». Текст рахується з видачі при останньому відкритті, тож
 * працює без сервера й для гостя. [city] null — область «Шукати тут», кажемо «поруч».
 */
data class WeekendDigest(val city: String?, val count: Int, val titles: List<String>, val fireAtEpochMillis: Long)

/** Коли дзвонити й про що. Чисте правило: видача, час і пояс приходять ззовні. */
object DigestRules {
    const val FIRE_HOUR = 17

    /** Менше — мовчимо: «одна подія на вихідних» радше відштовхне, ніж поверне. */
    const val MIN_EVENTS = 3

    /** Скільки назв у тексті: більше не влазить у рядок сповіщення. */
    const val TITLES = 2

    /**
     * Найближча пʼятниця о [FIRE_HOUR], що ще попереду, і події, які починаються в суботу чи
     * неділю після неї. [index] уже склеєний і ранжований за смаком: назви беремо з початку.
     */
    fun plan(index: List<EventIndexEntry>, city: String?, enabled: Boolean, now: Instant, zone: TimeZone): WeekendDigest? {
        if (!enabled) return null
        val today = now.toLocalDateTime(zone).date
        var friday = today.plus((DayOfWeek.FRIDAY.isoDayNumber - today.dayOfWeek.isoDayNumber + 7) % 7, DateTimeUnit.DAY)
        if (friday.atTime(FIRE_HOUR, 0).toInstant(zone) <= now) friday = friday.plus(7, DateTimeUnit.DAY)
        val fireAt = friday.atTime(FIRE_HOUR, 0).toInstant(zone)
        val from = friday.plus(1, DateTimeUnit.DAY).atStartOfDayIn(zone)
        val to = friday.plus(3, DateTimeUnit.DAY).atStartOfDayIn(zone)
        // Прокат рахуємо, якщо хоч один сеанс на вихідних: картка стоїть під найближчим, а він може бути в четвер.
        val weekend = index.filter { entry ->
            entry.sessions.map { it.startsAt }.ifEmpty { listOf(entry.startsAt) }
                .any { start -> runCatching { Instant.parse(start) }.getOrNull()?.let { it >= from && it < to } == true }
        }
        if (weekend.size < MIN_EVENTS) return null
        return WeekendDigest(city, weekend.size, weekend.take(TITLES).map { it.title }, fireAt.toEpochMilliseconds())
    }
}

/** Кому і коли нагадувати. Чисте правило: без часу пристрою, без дозволів, без платформи. */
object ReminderRules {
    /** За скільки до початку нагадуємо. */
    val LEAD = 1.hours

    /** Стеля на кількість запланованих: iOS тримає лише 64 локальних сповіщення на застосунок. */
    const val MAX_SCHEDULED = 60

    /**
     * Нагадування для [events] людини [userId]. Беремо опубліковані події, де вона організатор
     * або схвалений учасник, і лише ті, до яких ще більше за [LEAD]. Гостю нічого не плануємо.
     */
    fun plan(events: List<Event>, userId: String?, enabled: Boolean, now: Instant): List<EventReminder> {
        if (!enabled || userId == null) return emptyList()
        return events.asSequence()
            .filter { it.isPublished && it.concerns(userId) }
            .mapNotNull { event ->
                val start = event.startInstant ?: return@mapNotNull null
                val fireAt = start - LEAD
                if (fireAt <= now) null
                else EventReminder(event.id, event.title, event.address, fireAt.toEpochMilliseconds())
            }
            .sortedBy { it.fireAtEpochMillis }
            .take(MAX_SCHEDULED)
            .toList()
    }

    private fun Event.concerns(userId: String): Boolean {
        val room = gathering ?: return false
        return room.joined || room.organizerId == userId
    }
}
