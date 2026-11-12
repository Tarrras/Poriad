package app.poruch.domain

import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Instant
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.LocalTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.plus
import kotlinx.datetime.toInstant
import kotlinx.datetime.toLocalDateTime

/**
 * Шаблон «швидкої події» (docs/creation-platform-plan-2026-11.md, етап 2): один тап ставить жанр, місця й тривалість
 * замість типових 20 місць. Назви й типовий опис — на платформі (`strings.xml`), [key] — для чернетки й аналітики.
 */
enum class MeetupTemplate(val key: String, val category: EventCategory, val seats: Int, val minutes: Int) {
    // «Кіно» — зустріч, а не жанр `cinema`: той для сеансів з імпорту, і в добірки йде лише за інтересом ([Taste.curates]).
    CINEMA("cinema", EventCategory.SOCIAL, 4, 150),
    BOARD_GAMES("board_games", EventCategory.GAMES, 6, 180),
    WALK("walk", EventCategory.OUTDOORS, 6, 120),
    COFFEE("coffee", EventCategory.FOOD, 4, 90),
    WORKSHOP("workshop", EventCategory.ART, 8, 120),
    SPORT("sport", EventCategory.SPORT, 8, 90);

    companion object {
        fun fromKey(key: String?): MeetupTemplate? = entries.firstOrNull { it.key == key }
    }
}

/** Чип дня в «Коли». [WEEKEND] — найближча субота чи неділя після завтра: підпис дає [QuickDay.sunday]. */
enum class QuickDayKind { TODAY, TOMORROW, WEEKEND }

data class QuickDay(val kind: QuickDayKind, val date: LocalDate) {
    val sunday get() = date.dayOfWeek == DayOfWeek.SUNDAY
}

/** Правила однієї форми «Своя зустріч». Час — мілісекунди епохи й назва поясу: так їх тримають обидві платформи. */
object QuickEvent {
    /** Без шаблону — невелика компанія, а не зала на 20. */
    const val DEFAULT_SEATS = 6
    const val DEFAULT_MINUTES = 120
    /** Понад стільки місць — підказка «Для великих подій зручніше кабінет». Не заборона. */
    const val LARGE_SEATS = 30
    /**
     * До стількох місць — маленька компанія (власник, 12.11): на «Подію створено» першим «Скопіювати посилання» — кинути
     * в свій чат, а «Поширити анонс» (пост для Threads) другим. Більші — навпаки: їм потрібні нові люди.
     */
    const val SMALL_SEATS = 12
    /** Вечір: година, яку ставимо, поки людина не обрала свою. */
    private val EVENING = LocalTime(19, 0)

    fun isLarge(capacity: Int) = capacity > LARGE_SEATS
    fun isSmall(capacity: Int) = capacity in 1..SMALL_SEATS

    /**
     * Назва за шаблоном — лише поки людина не написала свою: порожньо чи назва попереднього шаблону ([previous]).
     * «Настолки: Каркасон» тап по «Кава» не зітре.
     */
    fun title(current: String, previous: String?, label: String): String =
        if (current.isBlank() || current.trim() == previous) label else current

    /**
     * Поле сховане під «Ще»: з його помилкою «Ще» розгортається, а воронка пише крок `more`, а не `quick`.
     * На видноті — назва, місце, початок і місця.
     */
    fun isMore(field: DraftField) = field !in setOf(
        DraftField.TITLE, DraftField.ADDRESS, DraftField.LOCATION, DraftField.STARTS_AT, DraftField.CAPACITY
    )

    /**
     * «Де?» — одне питання й одне прохання. Нема точки — показуємо лише її («Оберіть адресу з підказок або точку
     * на мапі»): підказка дає й адресу, і точку, тож «Вкажіть місто й адресу» над нею було б другим червоним рядком
     * про те саме. Окремо ADDRESS лишається, коли точка є, а адреси чи міста нема.
     */
    fun placeProblems(problems: List<DraftField>): List<DraftField> =
        if (DraftField.LOCATION in problems) problems - DraftField.ADDRESS else problems

    /** Сьогодні, завтра й найближчий вихідний після них: у п'ятницю це неділя, у суботу — наступна субота. */
    fun days(now: Long, zone: String): List<QuickDay> {
        val today = Instant.fromEpochMilliseconds(now).toLocalDateTime(zone(zone)).date
        val weekend = generateSequence(today.plus(2, DateTimeUnit.DAY)) { it.plus(1, DateTimeUnit.DAY) }
            .first { it.dayOfWeek == DayOfWeek.SATURDAY || it.dayOfWeek == DayOfWeek.SUNDAY }
        return listOf(
            QuickDay(QuickDayKind.TODAY, today), QuickDay(QuickDayKind.TOMORROW, today.plus(1, DateTimeUnit.DAY)),
            QuickDay(QuickDayKind.WEEKEND, weekend)
        )
    }

    /** Котрий чип дня відповідає початку [start]; null — «інша дата». */
    fun dayOf(start: Long, now: Long, zone: String): QuickDayKind? {
        val date = Instant.fromEpochMilliseconds(start).toLocalDateTime(zone(zone)).date
        return days(now, zone).firstOrNull { it.date == date }?.kind
    }

    /** Початок нової зустрічі: сьогодні о 19:00, якщо до неї ще дві години, інакше завтра о 19:00. */
    fun defaultStart(now: Long, zone: String): Long {
        val tz = zone(zone)
        val today = Instant.fromEpochMilliseconds(now).toLocalDateTime(tz).date
        val tonight = LocalDateTime(today, EVENING).toInstant(tz)
        val start = if (tonight >= Instant.fromEpochMilliseconds(now) + 2.hours) tonight
        else LocalDateTime(today.plus(1, DateTimeUnit.DAY), EVENING).toInstant(tz)
        return start.toEpochMilliseconds()
    }

    /**
     * Тап по чипу дня: день новий, година — та, що вже стоїть ([current]; null — 19:00). Сьогодні з годиною, що минула чи
     * ось-ось, — найближча повна година не раніше ніж за годину: «21:00», а не минуле.
     */
    fun startOn(day: QuickDay, current: Long?, now: Long, zone: String): Long {
        val tz = zone(zone)
        val time = current?.let { Instant.fromEpochMilliseconds(it).toLocalDateTime(tz).time } ?: EVENING
        val start = LocalDateTime(day.date, LocalTime(time.hour, time.minute)).toInstant(tz)
        val soon = Instant.fromEpochMilliseconds(now) + 1.hours
        if (start >= soon) return start.toEpochMilliseconds()
        val local = soon.toLocalDateTime(tz)
        val full = LocalDateTime(local.date, LocalTime(local.hour, 0)).toInstant(tz)
        return (if (full >= soon) full else full + 1.hours).toEpochMilliseconds()
    }

    /**
     * Кінець за новим початком [start]: тривалість — як була ([previousStart]..[previousEnd]), щоб подія з сайту на три
     * години не стала двогодинною; без неї — [minutes] шаблону чи типові дві години.
     */
    fun end(start: Long, previousStart: Long? = null, previousEnd: Long? = null, minutes: Int = DEFAULT_MINUTES): Long {
        val held = if (previousStart != null && previousEnd != null) previousEnd - previousStart else 0
        return start + if (held > 0) held else minutes.minutes.inWholeMilliseconds
    }

    private fun zone(id: String) = runCatching { TimeZone.of(id) }.getOrDefault(TimeZone.currentSystemDefault())
}
