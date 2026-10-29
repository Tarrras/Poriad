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
    val tomorrowAt: String? = null,
    /**
     * Квиток: година початку «19:40». Текст — «Початок о 19:40», а не «за годину»: без точних будильників Android
     * ставить нагадування про квиток раніше, щоб неточне не прийшло вже на початок.
     */
    val startsAt: String? = null
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

/** Про що дайджест: будні (понеділок) чи вихідні (четвер). [key] — у `digest_open`. */
enum class DigestKind(val key: String) { WEEKDAYS("weekdays"), WEEKEND("weekend") }

/** Чому подію в дайджесті варто помітити (docs/return-hooks.md). Порядок — сила причини. */
/** [NEAR] — подія в «Моїх місцях» (docs/my-places.md). */
enum class DigestReason { FOLLOWED, COMPANY, NEAR, ONE_NIGHT, FOR_YOU }

/**
 * Дайджест у вільний час людини. Текст рахується з видачі при останньому відкритті, тож працює без сервера й для гостя.
 * [city] null — область «Шукати тут», кажемо «поруч». [week] — котрий тиждень від останнього відкриття
 * (1–[DigestRules.WEEKS]): від нього заголовок і `digest_open`. [lead] — одна подія, яку варто назвати, з причинами
 * [reasons] ([followName] — за ким стежу); null — лише кількість і [titles].
 */
data class WeekendDigest(
    val city: String?,
    val count: Int,
    val titles: List<String>,
    val fireAtEpochMillis: Long,
    val week: Int,
    val kind: DigestKind = DigestKind.WEEKEND,
    val lead: String? = null,
    val reasons: List<DigestReason> = emptyList(),
    val followName: String? = null
) {
    /** Ключ сповіщення й будильника: вихідні — 1–4, будні — 11–14. Старі версії знали лише 1–4, тож ті — вихідні. */
    val id: Int get() = week + if (kind == DigestKind.WEEKDAYS) WEEKDAYS_OFFSET else 0

    companion object {
        const val WEEKDAYS_OFFSET = 10
        fun kindOf(id: Int) = if (id > WEEKDAYS_OFFSET) DigestKind.WEEKDAYS else DigestKind.WEEKEND
        fun weekOf(id: Int) = id % WEEKDAYS_OFFSET
    }
}

/**
 * Коли дзвонити й про що (docs/return-hooks.md, хвиля 2). Чисте правило: видача, смак, час і пояс приходять ззовні.
 * Дзвонимо тоді, коли людина сказала, що вільна: про вихідні — у четвер (план на вихідні складають до пʼятниці), про
 * будні — у понеділок, лише якщо обрано будні.
 */
object DigestRules {
    const val WEEKEND_HOUR = 18
    const val WEEKDAYS_HOUR = 17

    /** Менше — мовчимо: «одна подія на вихідних» радше відштовхне, ніж поверне. */
    const val MIN_EVENTS = 3

    /** Скільки назв у тексті без вирізненої події: більше не влазить у рядок сповіщення. */
    const val TITLES = 2

    /** Причин у тексті: третя вже не читається. */
    const val REASONS = 2

    /**
     * Скільки тижнів наперед. Кожне відкриття переписує драбину з нуля; хто не відкрив за чотири —
     * тиша: повертає подія, а не наполегливість.
     */
    const val WEEKS = 4

    /** Вихідні — завжди, коли їх обрано або не обрано нічого; будні — лише коли обрано. */
    fun kinds(times: List<TimeSlot>): List<DigestKind> {
        val weekdays = TimeSlot.WEEKDAY_DAY in times || TimeSlot.WEEKDAY_EVENING in times
        val weekend = TimeSlot.WEEKEND_DAY in times || TimeSlot.WEEKEND_EVENING in times
        return buildList {
            if (weekend || !weekdays) add(DigestKind.WEEKEND)
            if (weekdays) add(DigestKind.WEEKDAYS)
        }
    }

    /**
     * До [WEEKS] дзвінків кожного виду з [kinds]. Вихідні — четвер о [WEEKEND_HOUR] про пт 17:00 – нд; будні — понеділок о
     * [WEEKDAYS_HOUR] про пн 17:00 – пт 17:00. Подія рахується, якщо хоч один її сеанс у вікні й у вільному слоті
     * людини. Тиждень з менш ніж [MIN_EVENTS] випадає, решта тримає свій номер. [index] уже склеєний і ранжований за
     * смаком. [followed] — id події → за ким людина стежить (заклад чи артист); [near] — id подій у «Моїх місцях».
     */
    fun plan(
        index: List<EventIndexEntry>, city: String?, enabled: Boolean, now: Instant, zone: TimeZone,
        taste: Taste = Taste(), followed: Map<String, String> = emptyMap(), near: Set<String> = emptySet()
    ): List<WeekendDigest> {
        if (!enabled) return emptyList()
        // Прокат рахуємо, якщо хоч один сеанс у вікні: картка стоїть під найближчим, а він може бути раніше.
        val starts = index.filter { taste.curates(it.category) }.map { entry ->
            entry to entry.sessions.map { it.startsAt }.ifEmpty { listOf(entry.startsAt) }
                .mapNotNull { runCatching { Instant.parse(it) }.getOrNull() }
        }
        return kinds(taste.times).flatMap { plan(it, starts, city, now, zone, taste, followed, near) }
    }

    private fun plan(
        kind: DigestKind, starts: List<Pair<EventIndexEntry, List<Instant>>>, city: String?, now: Instant, zone: TimeZone,
        taste: Taste, followed: Map<String, String>, near: Set<String>
    ): List<WeekendDigest> {
        val (day, hour) = if (kind == DigestKind.WEEKEND) DayOfWeek.THURSDAY to WEEKEND_HOUR else DayOfWeek.MONDAY to WEEKDAYS_HOUR
        val today = now.toLocalDateTime(zone).date
        var first = today.plus((day.isoDayNumber - today.dayOfWeek.isoDayNumber + 7) % 7, DateTimeUnit.DAY)
        if (first.atTime(hour, 0).toInstant(zone) <= now) first = first.plus(7, DateTimeUnit.DAY)
        val chosen = taste.times.toSet()
        val weekendChosen = TimeSlot.WEEKEND_DAY in chosen || TimeSlot.WEEKEND_EVENING in chosen
        return (1..WEEKS).mapNotNull { week ->
            val fireDay = first.plus(7 * (week - 1), DateTimeUnit.DAY)
            val fireAt = fireDay.atTime(hour, 0).toInstant(zone)
            val (from, to) = if (kind == DigestKind.WEEKEND) {
                val friday = fireDay.plus(1, DateTimeUnit.DAY)
                friday.atTime(TimeSlot.EVENING_FROM_HOUR, 0).toInstant(zone) to friday.plus(3, DateTimeUnit.DAY).atStartOfDayIn(zone)
            } else {
                fireAt to fireDay.plus(4, DateTimeUnit.DAY).atTime(TimeSlot.EVENING_FROM_HOUR, 0).toInstant(zone)
            }
            val window = starts.filter { (entry, times) ->
                times.any { at ->
                    if (at < from || at >= to) return@any false
                    val slot = TasteRanking.slotAt(at, entry.timeZone)
                    when (kind) {
                        // Пʼятничний вечір — уже вихідні, хоч слот і будній.
                        DigestKind.WEEKEND -> !weekendChosen || slot == TimeSlot.WEEKDAY_EVENING || slot in chosen
                        DigestKind.WEEKDAYS -> slot in chosen
                    }
                }
            }.map { it.first }
            if (window.size < MIN_EVENTS) return@mapNotNull null
            val lead = lead(window, taste, followed, near)
            WeekendDigest(
                city, window.size, window.take(TITLES).map { it.title }, fireAt.toEpochMilliseconds(), week, kind,
                lead?.first?.title, lead?.second.orEmpty(), lead?.first?.let { followed[it.id] }
            )
        }
    }

    /**
     * «Цікаве = рідкісне + твоє»: серед подій вікна, що відповідають смаку (без смаку — усіх), та, де найбільше причин;
     * рівні — у порядку видачі, тобто за смаком. Без жодної причини, але під смак — «під ваші інтереси»; інакше null.
     */
    fun lead(
        window: List<EventIndexEntry>, taste: Taste, followed: Map<String, String>, near: Set<String> = emptySet()
    ): Pair<EventIndexEntry, List<DigestReason>>? {
        val candidates = TasteRanking.matching(window, taste).ifEmpty { window }
        val best = candidates.map { it to reasons(it, followed, near) }.maxByOrNull { it.second.size } ?: return null
        if (best.second.isNotEmpty()) return best.first to best.second.take(REASONS)
        return if (TasteRanking.matches(best.first, taste)) best.first to listOf(DigestReason.FOR_YOU) else null
    }

    private fun reasons(entry: EventIndexEntry, followed: Map<String, String>, near: Set<String>) = buildList {
        if (entry.id in followed) add(DigestReason.FOLLOWED)
        if (entry.companyCount > 0) add(DigestReason.COMPANY)
        if (entry.id in near) add(DigestReason.NEAR)
        // Не прокат: у серії видачі один показ (EventSeries склеїв би решту в sessions).
        if (entry.origin == EventOrigin.IMPORT && entry.sessions.size <= 1) add(DigestReason.ONE_NIGHT)
    }
}

/** Кому і коли нагадувати. Чисте правило: без часу пристрою, без дозволів, без платформи. */
object ReminderRules {
    /** За скільки до початку нагадуємо про свою подію чи «йду». */
    val LEAD = 1.hours

    /** Збережене нагадуємо напередодні о цій порі: лишається вечір, щоб вирішити й покликати когось. */
    const val SAVED_HOUR = 18

    /** Стеля на кількість запланованих: iOS тримає лише 64 локальних сповіщення на застосунок, ще до 8 — дайджести. */
    const val MAX_SCHEDULED = 52

    /**
     * Нагадування для [events] людини [userId] (усе з `my_events`, у гостя — картки його закладок). Опубліковані,
     * де вона організатор або схвалений учасник, — за [LEAD]; збережені ([savedIds]) — напередодні о [SAVED_HOUR] за
     * поясом телефона [zone]. Час, що вже минув, випадає. Гостю — лише збережені: участь — з акаунтом.
     */
    fun plan(
        events: List<Event>,
        savedIds: Collection<String>,
        userId: String?,
        enabled: Boolean,
        now: Instant,
        zone: TimeZone
    ): List<EventReminder> {
        if (!enabled) return emptyList()
        val saved = savedIds.toSet()
        return events.asSequence()
            .filter { it.isPublished }
            .mapNotNull { event ->
                val start = event.startInstant ?: return@mapNotNull null
                // Одне нагадування на подію: «йду» сильніше за закладку, тож своя чи «йду» — за годину, навіть збережена.
                val reminder = when {
                    userId != null && event.concerns(userId) -> EventReminder(event.id, event.title, event.address, (start - LEAD).toEpochMilliseconds())
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

    /**
     * Квиток — це «йду»: нагадування за [LEAD], як про свою подію, з назвою й місцем із квитка (docs/ticket-wallet.md).
     * Id — `ticket:…`: окремо від нагадування про збережену афішу (напередодні), і тап відкриває сам квиток.
     */
    fun tickets(
        tickets: List<WalletTicket>, enabled: Boolean, now: Instant, zone: TimeZone = TimeZone.currentSystemDefault()
    ): List<EventReminder> {
        if (!enabled) return emptyList()
        return tickets.mapNotNull { ticket ->
            val start = ticket.startInstant ?: return@mapNotNull null
            val local = start.toLocalDateTime(zone)
            val at = "${local.hour.toString().padStart(2, '0')}:${local.minute.toString().padStart(2, '0')}"
            EventReminder(TICKET_PREFIX + ticket.id, ticket.title, ticket.place.orEmpty(), (start - LEAD).toEpochMilliseconds(), startsAt = at)
                .takeIf { it.fireAtEpochMillis > now.toEpochMilliseconds() }
        }
    }

    /** Нагадування про квиток, а не про подію: платформа відкриває квиток. */
    const val TICKET_PREFIX = "ticket:"

    private fun Event.concerns(userId: String): Boolean {
        val room = gathering ?: return false
        return room.joined || room.organizerId == userId
    }
}
