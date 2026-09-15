package app.poruch.android.ui

import androidx.compose.ui.graphics.vector.ImageVector
import app.poruch.android.R
import app.poruch.domain.Event
import app.poruch.domain.EventRules
import app.poruch.domain.EventSession
import app.poruch.domain.Listing
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/** Словник домену в його порядку: підписи нижче збігаються за індексом. */
val categories = EventRules.categories
private val categoryLabels = listOf(R.string.music, R.string.sport, R.string.art, R.string.food, R.string.games, R.string.outdoors, R.string.social, R.string.comedy, R.string.kids, R.string.tours, R.string.conference)

fun categoryLabel(key: String) = categoryLabels.getOrElse(categories.indexOf(key)) { R.string.all }

fun categoryIcon(category: String): ImageVector = when (category) {
    "music" -> PoruchIcons.music
    "sport" -> PoruchIcons.sport
    "art" -> PoruchIcons.art
    "food" -> PoruchIcons.food
    "games" -> PoruchIcons.games
    "outdoors" -> PoruchIcons.outdoors
    "comedy" -> PoruchIcons.comedy
    "kids" -> PoruchIcons.kids
    "tours" -> PoruchIcons.tours
    "conference" -> PoruchIcons.conference
    else -> PoruchIcons.social
}

private val ukrainian: Locale = Locale.forLanguageTag("uk")

private fun zoned(event: Event) = runCatching { Instant.parse(event.startsAt).atZone(ZoneId.of(event.timeZone)) }.getOrNull()

private fun zonedEnd(event: Event) = runCatching { Instant.parse(event.endsAt).atZone(ZoneId.of(event.timeZone)) }.getOrNull()

/** Кеш форматерів за шаблоном: `ofPattern` дорогий, а `eventOverline` кличуть на кожен рядок скролу. */
private val patterns = ConcurrentHashMap<String, DateTimeFormatter>()

private fun pattern(value: String): DateTimeFormatter =
    patterns.getOrPut(value) { DateTimeFormatter.ofPattern(value, ukrainian) }

/** Слова для дат, зібрані один раз. Форматування без Context, тож служить і composable, і шерингу. */
data class DateWords(
    val today: String, val tomorrow: String, val underway: String,
    /** «до 30 вересня» — підпис картки прокату. */
    val until: String,
    val weekdayOn: List<String>,
    /** «і о 19:30» — другий сеанс того самого вечора. */
    val alsoAt: String = "+%1\$s",
    /** «ще 2 дати» — решта днів прокату. */
    val moreDates: (Int) -> String = { "+$it" },
    /** «ще 3 сеанси» — решта сеансів того самого дня. */
    val moreShowings: (Int) -> String = { "+$it" }
)

/** Слова з ресурсів раз на композицію, а не на картку: `getStringArray` будує новий масив щоразу. */
@Composable
fun dateWords(): DateWords {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    return remember(context, configuration) { context.dateWords() }
}

fun Context.dateWords(): DateWords = DateWords(
    today = getString(R.string.today),
    tomorrow = getString(R.string.tomorrow),
    underway = getString(R.string.underway_now),
    until = getString(R.string.underway_until),
    weekdayOn = resources.getStringArray(R.array.weekday_on).toList(),
    alsoAt = getString(R.string.series_also_at),
    moreDates = { resources.getQuantityString(R.plurals.series_more_dates, it, it) },
    moreShowings = { resources.getQuantityString(R.plurals.series_more_showings, it, it) }
)

private const val HOUR = "HH:mm"

/** Дата словами людини. Поза поточним роком — з роком, інакше «13 березня» читається як минуле. */
private fun dayLabel(at: ZonedDateTime, now: ZonedDateTime, words: DateWords, short: Boolean): String {
    val date = at.toLocalDate()
    val today = now.toLocalDate()
    val days = ChronoUnit.DAYS.between(today, date)
    return when {
        days == 0L -> words.today
        days == 1L -> words.tomorrow
        // До тижня досить назви дня, далі потрібна дата.
        days in 2L..6L -> words.weekdayOn.getOrElse(at.dayOfWeek.value - 1) {
            at.format(pattern(if (short) "EEE, d MMM" else "EEEE, d MMMM"))
        }
        date.year != today.year ->
            at.format(pattern(if (short) "EEE, d MMM yyyy" else "d MMMM yyyy"))
        else ->
            at.format(pattern(if (short) "EEE, d MMM" else "EEEE, d MMMM"))
    }
}

/** Дата прокату числом: «30 вересня». Не через [dayLabel], бо «до у суботу» — не речення. */
private fun plainDate(at: ZonedDateTime, withYear: Boolean): String =
    at.format(pattern(if (withYear) "d MMMM yyyy" else "d MMMM"))

/** Проміжок прокату: «16 липня – 30 вересня». Рік для обох кінців разом. */
private fun rangeLabel(start: ZonedDateTime, end: ZonedDateTime, now: ZonedDateTime): String {
    val year = now.toLocalDate().year
    val withYear = start.year != year || end.year != year
    return "${plainDate(start, withYear)} – ${plainDate(end, withYear)}"
}

/**
 * Надрядок картки: «СЬОГОДНІ · 18:30», «СБ, 13 БЕР. 2027 · 18:00», у поясі події. Для того,
 * що вже йде: сеанс — «ТРИВАЄ ЗАРАЗ», прокат — «ДО 30 ВЕРЕСНЯ».
 */
fun eventOverline(event: Event, words: DateWords, now: Instant = Instant.now()): String {
    val at = zoned(event) ?: return event.startsAt
    val instant = now.toKotlin()
    // Про прокат питаємо лише коли подія вже йде: невідкрита виставка показує початок, як усі.
    if (event.isUnderway(instant)) {
        val end = if (event.isMultiDay) zonedEnd(event) else null
        if (end != null) {
            val withYear = end.year != now.atZone(at.zone).toLocalDate().year
            return words.until.format(ukrainian, plainDate(end, withYear)).uppercase(ukrainian)
        }
        return words.underway.uppercase(ukrainian)
    }
    val day = dayLabel(at, now.atZone(at.zone), words, short = true)
    return "$day · ${at.format(pattern(HOUR))}".uppercase(ukrainian)
}

/**
 * Довга форма для екрана деталей. Пояс називаємо лише коли він відрізняється від поясу читача.
 * Сеанс: «Четвер, 16 липня · 18:00». Прокат: «16 липня – 30 вересня», без години, бо вона
 * читалась би як щоденний час відкриття.
 */
fun eventTime(event: Event, words: DateWords, now: Instant = Instant.now()): String {
    val at = zoned(event) ?: return event.startsAt
    val here = now.atZone(at.zone)
    val instant = now.toKotlin()
    val prefix = if (event.isUnderway(instant)) "${words.underway} · " else ""
    if (event.isMultiDay) {
        zonedEnd(event)?.let { return prefix + rangeLabel(at, it, here) }
    }
    val day = dayLabel(at, here, words, short = false)
    val hour = at.format(pattern(HOUR))
    val zoneSuffix =
        if (at.zone.rules.getOffset(at.toInstant()) == ZoneId.systemDefault().rules.getOffset(at.toInstant())) ""
        else " " + at.format(pattern("z"))
    return "$prefix$day · $hour$zoneSuffix"
}

/** Надрядок картки: дата найближчого сеансу і, для прокату, згадка про решту. На деталях решту показує карусель. */
fun cardOverline(event: Event, words: DateWords, now: Instant = Instant.now()): String {
    val base = eventOverline(event, words, now)
    val note = seriesNote(event, words) ?: return base
    return "$base · ${note.uppercase(ukrainian)}"
}

/**
 * Решта сеансів прокату: «ще 2 дати», «ще 3 сеанси», «і о 19:30». Число, а не проміжок, бо
 * прокат буває з розривами. Дні, а не сеанси, коли днів кілька.
 */
fun seriesNote(event: Event, words: DateWords): String? {
    if (!event.isSeries) return null
    val days = event.otherSessionDays
    if (days > 0) return words.moreDates(days)
    val others = event.otherSessionCount
    if (others == 1) {
        val next = event.sessions.firstOrNull { it.id != event.id } ?: return null
        val at = zoned(next) ?: return null
        return words.alsoAt.format(ukrainian, at.format(pattern(HOUR)))
    }
    return words.moreShowings(others)
}

/** Сеанс у каруселі дат: день і година окремо, бо два сеанси одного вечора інакше були б однаковими кнопками. */
fun sessionLabel(session: EventSession, words: DateWords, now: Instant = Instant.now()): Pair<String, String> {
    val at = zoned(session) ?: return session.startsAt to ""
    return dayLabel(at, now.atZone(at.zone), words, short = true) to at.format(pattern(HOUR))
}

private fun zoned(session: EventSession) =
    runCatching { Instant.parse(session.startsAt).atZone(ZoneId.of(session.timeZone)) }.getOrNull()

/** java.time.Instant → kotlin.time.Instant, щоб користуватись предикатами домену. */
private fun Instant.toKotlin(): kotlin.time.Instant = kotlin.time.Instant.fromEpochSeconds(epochSecond, nano)

/** Ціна одним рядком: «безкоштовно», «від N» або «джерело не сказало». Останнє — не нуль. */
@Composable
fun listingPrice(listing: Listing): String = when {
    listing.isFree == true -> stringResource(R.string.listing_free)
    listing.priceMin != null -> stringResource(R.string.listing_price_from, hryvnia(listing.priceMin!!))
    else -> stringResource(R.string.listing_price_unknown)
}

/** Копійки в афішах нічого не додають. */
private fun hryvnia(amount: Double): String =
    if (amount == amount.toLong().toDouble()) amount.toLong().toString()
    else "%.2f".format(ukrainian, amount)
