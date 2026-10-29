package app.poruch.android.ui

import androidx.compose.ui.graphics.vector.ImageVector
import app.poruch.android.R
import app.poruch.domain.EventCategory
import app.poruch.domain.Event
import app.poruch.domain.EventSession
import app.poruch.domain.Listing
import app.poruch.domain.Offer
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

/** Те, що людина може обрати, у порядку домену. */
val categories = EventCategory.selectable

fun categoryLabel(category: EventCategory) = when (category) {
    EventCategory.MUSIC -> R.string.music
    EventCategory.SPORT -> R.string.sport
    EventCategory.ART -> R.string.art
    EventCategory.FOOD -> R.string.food
    EventCategory.GAMES -> R.string.games
    EventCategory.OUTDOORS -> R.string.outdoors
    EventCategory.SOCIAL -> R.string.social
    EventCategory.COMEDY -> R.string.comedy
    EventCategory.KIDS -> R.string.kids
    EventCategory.TOURS -> R.string.tours
    EventCategory.CONFERENCE -> R.string.conference
    EventCategory.CINEMA -> R.string.cinema
    EventCategory.UNKNOWN -> R.string.category_other
}

fun categoryIcon(category: EventCategory): ImageVector = when (category) {
    EventCategory.MUSIC -> PoruchIcons.music
    EventCategory.SPORT -> PoruchIcons.sport
    EventCategory.ART -> PoruchIcons.art
    EventCategory.FOOD -> PoruchIcons.food
    EventCategory.GAMES -> PoruchIcons.games
    EventCategory.OUTDOORS -> PoruchIcons.outdoors
    EventCategory.COMEDY -> PoruchIcons.comedy
    EventCategory.KIDS -> PoruchIcons.kids
    EventCategory.TOURS -> PoruchIcons.tours
    EventCategory.CONFERENCE -> PoruchIcons.conference
    EventCategory.CINEMA -> PoruchIcons.cinema
    EventCategory.SOCIAL, EventCategory.UNKNOWN -> PoruchIcons.social
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
 * що вже йде: сеанс — «ТРИВАЄ ЗАРАЗ», прокат — «ДО 30 ВЕРЕСНЯ». Минуле — просто датою:
 * «20 ВЕРЕСНЯ · 14:00», бо «НД» тижневої давності читається як найближча неділя.
 */
fun eventOverline(event: Event, words: DateWords, now: Instant = Instant.now()): String {
    val at = zoned(event) ?: return event.startsAt
    val instant = now.toKotlin()
    if (event.hasEnded(instant)) {
        val withYear = at.year != now.atZone(at.zone).year
        return "${plainDate(at, withYear)} · ${at.format(pattern(HOUR))}".uppercase(ukrainian)
    }
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

/**
 * Що друкується на корінці квитка: велике й мале. Сеанс — година й день («19:30», «СЬОГОДНІ»); те, що вже йде, — кінець
 * прокату («ДО 30.11», «ТРИВАЄ») чи «ЗАРАЗ»; минуле — година й дата числом. [compact] — малий корінець 56–60 dp: «СЬОГОДНІ» туди
 * не влазить, тож і майбутнє датою числом. Слова ті самі, що в iOS `stubParts`.
 */
/** Корінець зустрічі, якої ще нема (редактор): година й день, як у нижньому корінці [stubParts] з `medium`. */
fun draftStubParts(at: ZonedDateTime, words: DateWords, now: Instant = Instant.now()): Pair<String, String> {
    val days = ChronoUnit.DAYS.between(now.atZone(at.zone).toLocalDate(), at.toLocalDate())
    val day = if (days in 0L..6L) dayLabel(at, now.atZone(at.zone), words, short = true) else at.format(pattern("EE dd.MM"))
    return at.format(pattern(HOUR)) to day.uppercase(ukrainian)
}

fun stubParts(
    event: Event, words: DateWords, compact: Boolean = false,
    /** Нижній корінець постера: день словом лише на найближчий тиждень, далі коротко «ЧТ 12.11». */
    medium: Boolean = false, now: Instant = Instant.now()
): Pair<String, String> {
    val at = zoned(event) ?: return "—" to ""
    val instant = now.toKotlin()
    if (event.hasEnded(instant)) return at.format(pattern(HOUR)) to at.format(pattern("dd.MM"))
    if (event.isUnderway(instant)) {
        val end = if (event.isMultiDay) zonedEnd(event) else null
        // «ДО 30.11» великим, як «ЗАРАЗ»: малим словом після дати корінець читався задом наперед — «30.11 до».
        return if (end != null) "ДО ${end.format(pattern("dd.MM"))}" to "ТРИВАЄ" else "ЗАРАЗ" to "ТРИВАЄ"
    }
    val days = ChronoUnit.DAYS.between(now.atZone(at.zone).toLocalDate(), at.toLocalDate())
    val day = when {
        compact -> at.format(pattern("dd.MM"))
        medium && days !in 0L..6L -> at.format(pattern("EE dd.MM")).uppercase(ukrainian)
        else -> dayLabel(at, now.atZone(at.zone), words, short = true).uppercase(ukrainian)
    }
    return at.format(pattern(HOUR)) to day
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
fun listingPrice(listing: Listing): String = priceLabel(listing.isFree, listing.priceMin)

/** Ціна одного продавця: «від 400 ₴» у рядку «Квитки». */
@Composable
fun offerPrice(offer: Offer): String = priceLabel(offer.isFree, offer.priceMin)

@Composable
private fun priceLabel(isFree: Boolean?, priceMin: Double?): String = when {
    isFree == true -> stringResource(R.string.listing_free)
    priceMin != null -> stringResource(R.string.listing_price_from, hryvnia(priceMin))
    else -> stringResource(R.string.listing_price_unknown)
}

/**
 * Стара й нова дата перенесеної афіші, «пт 21.11, 19:00», у поясі події (питання 6, варіант Б: стара — на квитку,
 * перекреслена; нова — та, що на корінці). Null — не перенесена.
 */
fun movedDates(event: Event): Pair<String, String>? {
    val listing = event.listing?.takeIf { it.isMoved } ?: return null
    val zone = runCatching { ZoneId.of(event.timeZone) }.getOrNull() ?: return null
    val old = runCatching { Instant.parse(listing.previousStartsAt).atZone(zone) }.getOrNull() ?: return null
    val new = zoned(event) ?: return null
    return old.format(pattern(MOVED)) to new.format(pattern(MOVED))
}

/** Час збору для питання R7а: «21:30», коли день той самий, що [ref], інакше «пт, 7 листопада о 21:30». Пояс — події. */
fun meetWhen(raw: String, ref: String?, zone: String): String {
    val at = zonedAt(raw, zone) ?: return raw
    return if (ref != null && sameDay(raw, ref, zone)) at.format(pattern(HOUR)) else at.format(pattern("EE, d MMMM 'о' HH:mm"))
}

/** Той самий календарний день у поясі [zone]. */
fun sameDay(a: String, b: String, zone: String): Boolean {
    val x = zonedAt(a, zone) ?: return false
    val y = zonedAt(b, zone) ?: return false
    return x.toLocalDate() == y.toLocalDate()
}

private fun zonedAt(raw: String, zone: String) =
    runCatching { java.time.OffsetDateTime.parse(raw).toInstant().atZone(ZoneId.of(zone)) }.getOrNull()

/** Стара дата довгою формою для банера деталей: «пт, 21 листопада, 19:00». */
fun previousDate(event: Event): String? {
    val raw = event.listing?.previousStartsAt ?: return null
    val zone = runCatching { ZoneId.of(event.timeZone) }.getOrNull() ?: return null
    return runCatching { Instant.parse(raw).atZone(zone).format(pattern("EE, d MMMM, HH:mm")) }.getOrNull()
}

private const val MOVED = "EE dd.MM, HH:mm"

/** Копійки в афішах нічого не додають. */
private fun hryvnia(amount: Double): String =
    if (amount == amount.toLong().toDouble()) amount.toLong().toString()
    else "%.2f".format(ukrainian, amount)
