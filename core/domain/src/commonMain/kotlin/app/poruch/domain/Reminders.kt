package app.poruch.domain

import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.atTime
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlinx.datetime.toInstant
import kotlinx.datetime.toLocalDateTime

/**
 * Локальне нагадування про подію: що сказати і коли. Час в epoch-мілісекундах, бо його
 * читають AlarmManager і UNUserNotificationCenter, а не бізнес-логіка. [tomorrowAt] — початок
 * завтра («19:00») у нагадуванні напередодні про збережену; null — «за годину» про свою чи «йду».
 */
data class EventReminder(
    val eventId: String,
    val title: String,
    val address: String,
    val fireAtEpochMillis: Long,
    val tomorrowAt: String? = null
)

/**
 * Системний планувальник нагадувань. Реалізує платформа; отримує повний список і сама
 * вирішує, що скасувати, а що лишити. Порожній список означає «нічого не нагадувати».
 */
interface ReminderScheduler {
    fun replace(reminders: List<EventReminder>)

    /** Драбина дайджестів вихідних: новий план замінює весь старий, порожній знімає. */
    fun replaceDigests(digests: List<WeekendDigest>)
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
 * [week] — котра пʼятниця від останнього відкриття (1–[DigestRules.WEEKS]): від неї заголовок і `digest_open`.
 */
data class WeekendDigest(val city: String?, val count: Int, val titles: List<String>, val fireAtEpochMillis: Long, val week: Int)

/** Коли дзвонити й про що. Чисте правило: видача, час і пояс приходять ззовні. */
object DigestRules {
    const val FIRE_HOUR = 17

    /** Менше — мовчимо: «одна подія на вихідних» радше відштовхне, ніж поверне. */
    const val MIN_EVENTS = 3

    /** Скільки назв у тексті: більше не влазить у рядок сповіщення. */
    const val TITLES = 2

    /**
     * Скільки пʼятниць наперед. Кожне відкриття переписує драбину з нуля; хто не відкрив за чотири —
     * тиша: повертає подія, а не наполегливість.
     */
    const val WEEKS = 4

    /**
     * До [WEEKS] найближчих пʼятниць о [FIRE_HOUR], що ще попереду, і події, які починаються в суботу чи
     * неділю після кожної. Пʼятниця з менш ніж [MIN_EVENTS] відомими подіями випадає, решта тримає свій
     * номер тижня. [index] уже склеєний і ранжований за смаком: назви беремо з початку.
     */
    fun plan(index: List<EventIndexEntry>, city: String?, enabled: Boolean, now: Instant, zone: TimeZone): List<WeekendDigest> {
        if (!enabled) return emptyList()
        val today = now.toLocalDateTime(zone).date
        var first = today.plus((DayOfWeek.FRIDAY.isoDayNumber - today.dayOfWeek.isoDayNumber + 7) % 7, DateTimeUnit.DAY)
        if (first.atTime(FIRE_HOUR, 0).toInstant(zone) <= now) first = first.plus(7, DateTimeUnit.DAY)
        // Прокат рахуємо, якщо хоч один сеанс на вихідних: картка стоїть під найближчим, а він може бути в четвер.
        val starts = index.map { entry ->
            entry to entry.sessions.map { it.startsAt }.ifEmpty { listOf(entry.startsAt) }
                .mapNotNull { runCatching { Instant.parse(it) }.getOrNull() }
        }
        return (1..WEEKS).mapNotNull { week ->
            val friday = first.plus(7 * (week - 1), DateTimeUnit.DAY)
            val from = friday.plus(1, DateTimeUnit.DAY).atStartOfDayIn(zone)
            val to = friday.plus(3, DateTimeUnit.DAY).atStartOfDayIn(zone)
            val weekend = starts.filter { (_, times) -> times.any { it >= from && it < to } }.map { it.first }
            if (weekend.size < MIN_EVENTS) return@mapNotNull null
            val fireAt = friday.atTime(FIRE_HOUR, 0).toInstant(zone)
            WeekendDigest(city, weekend.size, weekend.take(TITLES).map { it.title }, fireAt.toEpochMilliseconds(), week)
        }
    }
}

/** Кому і коли нагадувати. Чисте правило: без часу пристрою, без дозволів, без платформи. */
object ReminderRules {
    /** За скільки до початку нагадуємо про свою подію чи «йду». */
    val LEAD = 1.hours

    /** Збережене нагадуємо напередодні о цій порі: лишається вечір, щоб вирішити й покликати когось. */
    const val SAVED_HOUR = 18

    /** Стеля на кількість запланованих: iOS тримає лише 64 локальних сповіщення на застосунок, ще 4 — дайджести. */
    const val MAX_SCHEDULED = 56

    /**
     * Нагадування для [events] людини [userId] (усе з `my_events`). Опубліковані, де вона організатор
     * або схвалений учасник, — за [LEAD]; збережені ([savedIds]) — напередодні о [SAVED_HOUR] за поясом
     * телефона [zone]. Час, що вже минув, випадає. Гостю нічого: участь і закладки — лише з акаунтом.
     */
    fun plan(
        events: List<Event>,
        savedIds: Collection<String>,
        userId: String?,
        enabled: Boolean,
        now: Instant,
        zone: TimeZone
    ): List<EventReminder> {
        if (!enabled || userId == null) return emptyList()
        val saved = savedIds.toSet()
        return events.asSequence()
            .filter { it.isPublished }
            .mapNotNull { event ->
                val start = event.startInstant ?: return@mapNotNull null
                // Одне нагадування на подію: «йду» сильніше за закладку, тож своя чи «йду» — за годину, навіть збережена.
                val reminder = when {
                    event.concerns(userId) -> EventReminder(event.id, event.title, event.address, (start - LEAD).toEpochMilliseconds())
                    event.id in saved -> {
                        val local = start.toLocalDateTime(zone)
                        val fireAt = local.date.minus(1, DateTimeUnit.DAY).atTime(SAVED_HOUR, 0).toInstant(zone)
                        val at = "${local.hour.toString().padStart(2, '0')}:${local.minute.toString().padStart(2, '0')}"
                        EventReminder(event.id, event.title, event.address, fireAt.toEpochMilliseconds(), at)
                    }
                    else -> null
                }
                reminder?.takeIf { it.fireAtEpochMillis > now.toEpochMilliseconds() }
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
