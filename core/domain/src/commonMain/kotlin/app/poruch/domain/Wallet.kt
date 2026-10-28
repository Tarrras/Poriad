package app.poruch.domain

import kotlin.time.Duration.Companion.minutes
import kotlin.time.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.LocalTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toInstant
import kotlinx.serialization.Serializable

/**
 * Квиток з телефона (docs/ticket-wallet.md). Файл лежить лише на пристрої ([file] — імʼя в сховищі застосунку), тут —
 * що з нього прочитано й підтверджено людиною. [eventId] — подія афіші, якщо квиток на неї; інакше це квиток без афіші
 * (кіно) зі своїми назвою, місцем і часом.
 */
@Serializable
data class WalletTicket(
    val id: String,
    val file: String,
    val kind: TicketKind,
    val title: String,
    val place: String? = null,
    /** Початок, ISO-8601 в UTC. */
    val startsAt: String,
    val timeZone: String,
    /** Скільки квитків у файлі: сторінки PDF чи місця з тексту. */
    val count: Int = 1,
    val seats: List<TicketSeat> = emptyList(),
    val eventId: String? = null,
    val addedAt: String,
) {
    val startInstant: Instant? get() = runCatching { Instant.parse(startsAt) }.getOrNull()

    /** Подія вже минула: квиток лишається пробитим, як інші минулі плани. */
    fun isPast(now: Instant): Boolean = startInstant?.let { it + PAST_AFTER < now } ?: false

    companion object {
        /** Квиток «минулий» через 3 години після початку: кіно й концерт ще йдуть, а людина вже всередині. */
        val PAST_AFTER = 180.minutes
    }
}

@Serializable
enum class TicketKind { PDF, IMAGE }

/** Квитки на телефоні (docs/ticket-wallet.md): лише пристрій і під `device:` — переживають вихід з акаунта. */
interface TicketStore {
    fun all(): List<WalletTicket>
    fun write(tickets: List<WalletTicket>)
}

/** Місце в залі: «ряд 7, місце 12». Без ряду — фан-зона чи вільна розсадка з номером. */
@Serializable
data class TicketSeat(val row: String? = null, val seat: String)

/** Що вдалося прочитати з квитка до підтвердження. Порожнє поле людина заповнює сама. */
data class TicketDraft(
    val title: String? = null,
    val place: String? = null,
    val start: LocalDateTime? = null,
    val seats: List<TicketSeat> = emptyList(),
) {
    /** Наскільки розібрано: для аналітики `wallet_import.parsed`. */
    val parsed: String get() = when {
        title != null && start != null -> "full"
        title != null || start != null || place != null -> "partial"
        else -> "none"
    }
}

/**
 * Текст квитка → чернетка. Квитки різних продавців різні, тож правила прості й терплячі: підписи («Фільм:», «Зал:»,
 * «Ряд 7 Місце 12»), дата з часом в одному рядку, а дата покупки чи номер замовлення не плутаються з початком.
 * Помилка тут не страшна: людина бачить чернетку й виправляє її перед «Додати».
 */
object TicketReader {
    private val MONTHS = listOf(
        "січня", "лютого", "березня", "квітня", "травня", "червня",
        "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"
    )
    private val MONTHS_EN = listOf(
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december"
    )
    private val NUMERIC_DATE = Regex("""(?<!\d)(\d{1,2})\.(\d{1,2})(?:\.(\d{4}|\d{2}))?(?![\d:])""")
    private val WORD_DATE = Regex("""(?<!\d)(\d{1,2})\s+(${(MONTHS + MONTHS_EN).joinToString("|")})(?:\s+(\d{4}))?""", RegexOption.IGNORE_CASE)
    private val TIME = Regex("""(?<![\d.:])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])""")
    private val SEAT = Regex("""(?:ряд|row)\D{0,4}?(\d{1,3})[^\dА-Яа-яA-Za-z]{0,6}(?:місце|seat|м\.)\D{0,4}?(\d{1,3})""", RegexOption.IGNORE_CASE)

    /** Рядки покупки й оплати: дата там — коли купили, а не коли йти. */
    private val PURCHASE = Regex("""покуп|придба|оплат|замовл|видано|сформовано|order|purchase|issued""", RegexOption.IGNORE_CASE)
    /** Підпис часу початку: перевага над іншими часами («вхід з 18:00, початок 19:00»). Цілим словом: не «Частина». */
    private val START = Regex("""(?<!\p{L})(?:початок|сеанс|start|time|час)(?!\p{L})""", RegexOption.IGNORE_CASE)

    private val TITLE_LABELS = listOf("фільм", "подія", "вистава", "назва", "захід", "event", "film", "movie")
    private val PLACE_LABELS = listOf("кінотеатр", "місце проведення", "майданчик", "заклад", "локація", "адреса", "venue", "cinema", "place")
    private const val HALL_LABEL = "зал"

    /** Не назва: службові слова квитка й бренди продавців. Словами, а не підрядком: «Частина» — не «час». */
    private val BOILER_WORDS = setOf(
        "квиток", "квитка", "квитки", "електронний", "ticket", "e-ticket", "білет", "ряд", "місце", "сектор", "зал", "ціна",
        "вартість", "грн", "uah", "номер", "код", "qr", "дата", "час", "початок", "вхід", "multiplex", "мультиплекс", "планета",
        "planeta", "karabas", "карабас", "concert", "покупець", "замовлення", "оплата", "видано", "повернення", "правила"
    )
    private val BOILER_PARTS = listOf("₴", "№", ".ua", ".com", "http", "@", "www", "internet-bilet", "ticketsbox")
    private val AGE = Regex("""(?<!\d)\d{1,2}\+""")

    fun read(text: String, today: LocalDate): TicketDraft {
        val lines = text.lines().map { it.trim().replace(Regex("""\s+"""), " ") }.filter { it.isNotEmpty() }
        return TicketDraft(
            title = labelled(lines, TITLE_LABELS) ?: firstTitleLine(lines),
            place = labelled(lines, PLACE_LABELS)?.let { place -> labelled(lines, listOf(HALL_LABEL), loose = true)?.let { "$place, зал $it" } ?: place },
            start = start(lines, today),
            seats = SEAT.findAll(text).map { TicketSeat(it.groupValues[1], it.groupValues[2]) }.distinct().toList(),
        )
    }

    /**
     * «Підпис: значення» в одному рядку або підпис окремим рядком і значення під ним. Без двокрапки підпис не підпис:
     * «Шоу „Що нового?“» — назва. [loose] — «Зал 5» без двокрапки.
     */
    private fun labelled(lines: List<String>, labels: List<String>, loose: Boolean = false): String? {
        for ((i, line) in lines.withIndex()) {
            val lower = line.lowercase()
            val label = labels.firstOrNull { lower.startsWith(it) } ?: continue
            val after = line.drop(label.length)
            if (after.firstOrNull()?.isLetter() == true) continue
            val rest = after.trimStart(':', ' ', '-', '—', '–').trim()
            if (rest.isEmpty() && after.trim().removeSuffix(":").isEmpty()) {
                return lines.getOrNull(i + 1)?.takeIf { next -> labels.none { next.lowercase().startsWith(it) } }
            }
            if (rest.any(Char::isLetterOrDigit) && (after.trimStart().startsWith(":") || loose)) return rest
        }
        return null
    }

    private fun firstTitleLine(lines: List<String>): String? = lines.firstOrNull { line ->
        line.count(Char::isLetter) >= 3 && line.length <= 90 && !isBoilerplate(line) &&
            !TIME.containsMatchIn(line) && !NUMERIC_DATE.containsMatchIn(line) && !WORD_DATE.containsMatchIn(line)
    }

    private fun isBoilerplate(line: String): Boolean {
        val lower = line.lowercase()
        return BOILER_PARTS.any { it in lower } || AGE.containsMatchIn(line) ||
            lower.split(Regex("""[^\p{L}\p{N}-]+""")).any { it in BOILER_WORDS }
    }

    private fun start(lines: List<String>, today: LocalDate): LocalDateTime? {
        val candidates = lines.withIndex().filter { !PURCHASE.containsMatchIn(it.value) }
        val dated = candidates.mapNotNull { (i, line) -> date(line, today)?.let { Triple(i, line, it) } }
        // Дата з часом в одному рядку — найнадійніше; далі дата й час у сусідніх рядках; далі будь-яка дата.
        dated.firstNotNullOfOrNull { (_, line, date) -> time(line)?.let { LocalDateTime(date, it) } }?.let { return it }
        val date = dated.firstOrNull()?.third ?: return null
        val time = candidates.firstOrNull { START.containsMatchIn(it.value) && TIME.containsMatchIn(it.value) }?.let { time(it.value) }
            ?: dated.first().first.let { i -> candidates.firstOrNull { it.index in i - 2..i + 2 && TIME.containsMatchIn(it.value) } }?.let { time(it.value) }
            ?: candidates.firstNotNullOfOrNull { time(it.value) }
            ?: return null
        return LocalDateTime(date, time)
    }

    /** Останній час у рядку: «вхід 18:00 · початок 19:00» — початок пишуть після входу. */
    private fun time(line: String): LocalTime? {
        val match = TIME.findAll(line).lastOrNull() ?: return null
        return LocalTime(match.groupValues[1].toInt(), match.groupValues[2].toInt())
    }

    private fun date(line: String, today: LocalDate): LocalDate? {
        WORD_DATE.find(line)?.let { m ->
            val name = m.groupValues[2].lowercase()
            val month = (MONTHS.indexOf(name).takeIf { it >= 0 } ?: MONTHS_EN.indexOf(name)) + 1
            return dateOf(m.groupValues[1].toInt(), month, m.groupValues[3].toIntOrNull(), today)
        }
        for (m in NUMERIC_DATE.findAll(line)) {
            val year = m.groupValues[3].takeIf { it.isNotEmpty() }?.toInt()?.let { if (it < 100) 2000 + it else it }
            dateOf(m.groupValues[1].toInt(), m.groupValues[2].toInt(), year, today)?.let { return it }
        }
        return null
    }

    /** Без року — найближча така дата, не раніше вчорашньої: квиток купують наперед. */
    private fun dateOf(day: Int, month: Int, year: Int?, today: LocalDate): LocalDate? {
        if (month !in 1..12 || day !in 1..31) return null
        fun on(y: Int) = runCatching { LocalDate(y, month, day) }.getOrNull()
        if (year != null) return on(year)
        val thisYear = on(today.year) ?: return null
        return if (thisYear.toEpochDays() >= today.toEpochDays() - 1) thisYear else on(today.year + 1)
    }
}

/** Яку подію афіші найімовірніше відкриває квиток. */
object TicketMatch {
    /** Початок на квитку й у видачі розходяться: продавці округлюють, а сеанс кіно стартує з рекламою. */
    val WINDOW = 45.minutes
    private val STOP = setOf("і", "й", "та", "в", "у", "на", "з", "із", "зі", "до", "по", "the", "a", "an", "of", "and")

    /** Id події: сам сеанс серії, коли квиток на нього. Null — квиток без афіші. */
    fun match(draft: TicketDraft, index: List<EventIndexEntry>, zone: TimeZone): String? {
        val title = draft.title?.let(::words)?.takeIf { it.isNotEmpty() } ?: return null
        val start = draft.start?.toInstant(zone) ?: return null
        return index.mapNotNull { entry ->
            val starts = listOf(entry.id to entry.startsAt) + entry.sessions.filterNot { it.cancelled }.map { it.id to it.startsAt }
            val near = starts.firstOrNull { (_, at) -> runCatching { Instant.parse(at) }.getOrNull()?.let { (it - start).absoluteValue <= WINDOW } == true }
                ?: return@mapNotNull null
            val score = overlap(title, words(entry.title))
            if (score >= 0.6) near.first to score else null
        }.maxByOrNull { it.second }?.first
    }

    /** Частка слів коротшої назви, що є в довшій: «Ліст» проти «Ліст. Безмежжя уяви (Музичний салон НФУ)» — збіг. */
    private fun overlap(a: Set<String>, b: Set<String>): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        val (short, long) = if (a.size <= b.size) a to b else b to a
        return short.count { it in long }.toDouble() / short.size
    }

    private fun words(text: String): Set<String> =
        text.lowercase().replace('’', '\'').replace('ʼ', '\'').split(Regex("""[^\p{L}\p{N}']+"""))
            .filter { it.length >= 2 && it !in STOP }.toSet()
}
