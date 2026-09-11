package app.poruch.android.ui

import androidx.compose.ui.graphics.vector.ImageVector
import app.poruch.android.R
import app.poruch.domain.Event
import app.poruch.domain.EventRules
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

/** The domain's vocabulary, in the domain's order — the labels below line up with it index by index. */
val categories = EventRules.categories
private val categoryLabels = listOf(R.string.music, R.string.sport, R.string.art, R.string.food, R.string.games, R.string.outdoors, R.string.social, R.string.comedy, R.string.kids)

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
    else -> PoruchIcons.social
}

private val ukrainian: Locale = Locale.forLanguageTag("uk")

private fun zoned(event: Event) = runCatching { Instant.parse(event.startsAt).atZone(ZoneId.of(event.timeZone)) }.getOrNull()

private fun zonedEnd(event: Event) = runCatching { Instant.parse(event.endsAt).atZone(ZoneId.of(event.timeZone)) }.getOrNull()

/**
 * Форматери — по одному на шаблон, а не на виклик.
 *
 * `DateTimeFormatter.ofPattern` щоразу розбирає шаблон і збирає дерево форматування, а
 * `eventOverline` викликається для кожного рядка списку під час скролу. Локаль тут стала, тож
 * ключем вистачає самого шаблону.
 */
private val patterns = ConcurrentHashMap<String, DateTimeFormatter>()

private fun pattern(value: String): DateTimeFormatter =
    patterns.getOrPut(value) { DateTimeFormatter.ofPattern(value, ukrainian) }

/**
 * The words a date needs, resolved once. Formatting itself stays free of Context, so the same
 * functions serve a composable and the share sheet.
 */
data class DateWords(
    val today: String, val tomorrow: String, val underway: String,
    /** «до 30 вересня» — підпис картки прокату. */
    val until: String,
    /** «Триває до 30 вересня» — те саме реченням, для екрана події. */
    val underwayUntil: String,
    val weekdayOn: List<String>
)

/**
 * Слова беруться з ресурсів один раз на композицію, а не на кожну картку: `getStringArray`
 * будує новий масив щоразу, а в списку карток сотня.
 */
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
    underwayUntil = getString(R.string.underway_until_long),
    weekdayOn = resources.getStringArray(R.array.weekday_on).toList()
)

private const val HOUR = "HH:mm"

/**
 * How far away a date is, in the terms a person actually uses. «13 березня» alone is a trap:
 * six months out it reads as the March that already passed, so anything outside the current year
 * carries its year.
 */
private fun dayLabel(at: ZonedDateTime, now: ZonedDateTime, words: DateWords, short: Boolean): String {
    val date = at.toLocalDate()
    val today = now.toLocalDate()
    val days = ChronoUnit.DAYS.between(today, date)
    return when {
        days == 0L -> words.today
        days == 1L -> words.tomorrow
        // За тиждень назва дня ще орієнтує («у суботу»), далі вже ні — там потрібна дата.
        days in 2L..6L -> words.weekdayOn.getOrElse(at.dayOfWeek.value - 1) {
            at.format(pattern(if (short) "EEE, d MMM" else "EEEE, d MMMM"))
        }
        date.year != today.year ->
            at.format(pattern(if (short) "EEE, d MMM yyyy" else "d MMMM yyyy"))
        else ->
            at.format(pattern(if (short) "EEE, d MMM" else "EEEE, d MMMM"))
    }
}

/**
 * Кінець прокату звичайною датою: «до 30 вересня».
 *
 * Навмисно не через [dayLabel]: там «Завтра» й «У суботу», і «до у суботу» — це не речення. Рік
 * дописуємо з тієї самої причини, з якої його дописує [dayLabel].
 */
private fun untilLabel(end: ZonedDateTime, now: ZonedDateTime, template: String): String {
    val shape = if (end.year != now.toLocalDate().year) "d MMMM yyyy" else "d MMMM"
    return template.format(ukrainian, end.format(pattern(shape)))
}

/**
 * Overline above a card title: «СЬОГОДНІ · 18:30», «СБ, 13 БЕР. 2027 · 18:00». Event's own zone.
 *
 * Два стани для того, що вже почалось, а не один. Концерт, що почався годину тому, — «ТРИВАЄ
 * ЗАРАЗ». Виставка з прокатом до 30 вересня цим підписом не сказала б головного, а її дата
 * початку («16 ЛИПНЯ») читається як подія, що минула, — тому «ДО 30 ВЕРЕСНЯ».
 */
fun eventOverline(event: Event, words: DateWords, now: Instant = Instant.now()): String {
    val at = zoned(event) ?: return event.startsAt
    val instant = now.toKotlin()
    if (event.endsAfterToday(instant)) {
        zonedEnd(event)?.let { return untilLabel(it, now.atZone(at.zone), words.until).uppercase(ukrainian) }
    }
    if (event.isUnderway(instant)) return words.underway.uppercase(ukrainian)
    val day = dayLabel(at, now.atZone(at.zone), words, short = true)
    return "$day · ${at.format(pattern(HOUR))}".uppercase(ukrainian)
}

/**
 * Long form for the detail screen. The zone is named only when it differs from the reader's own:
 * for someone in Kyiv reading about Kyiv, «GMT+03:00» is noise, but for a traveller it is the
 * difference between arriving and missing it.
 */
fun eventTime(event: Event, words: DateWords, now: Instant = Instant.now()): String {
    val at = zoned(event) ?: return event.startsAt
    val day = dayLabel(at, now.atZone(at.zone), words, short = false)
    val hour = at.format(pattern(HOUR))
    val zoneSuffix =
        if (at.zone.rules.getOffset(at.toInstant()) == ZoneId.systemDefault().rules.getOffset(at.toInstant())) ""
        else " " + at.format(pattern("z"))
    val instant = now.toKotlin()
    // На екрані події дата початку лишається: вона відповідає на «з якого числа», якого підпис
    // картки не вміщає.
    val prefix = when {
        event.endsAfterToday(instant) -> zonedEnd(event)
            ?.let { untilLabel(it, now.atZone(at.zone), words.underwayUntil) + " · " }
            ?: "${words.underway} · "
        event.isUnderway(instant) -> "${words.underway} · "
        else -> ""
    }
    return "$prefix$day · $hour$zoneSuffix"
}

/** java.time.Instant -> kotlin.time.Instant, so the domain's own predicates can be reused. */
private fun Instant.toKotlin(): kotlin.time.Instant = kotlin.time.Instant.fromEpochSeconds(epochSecond, nano)

// Порогу «мало місць» тут більше немає: він живе в Gathering.isScarce, спільний для обох платформ.

/**
 * Ціна квитка одним рядком. Три різні речі, які легко злити в одну: «безкоштовно», «від стількох»
 * і «джерело не сказало». Остання — не нуль і не порожньо, інакше платна подія читалася б як
 * дарова.
 */
@Composable
fun listingPrice(listing: Listing): String = when {
    listing.isFree == true -> stringResource(R.string.listing_free)
    listing.priceMin != null -> stringResource(R.string.listing_price_from, hryvnia(listing.priceMin!!))
    else -> stringResource(R.string.listing_price_unknown)
}

/** Копійки в афішах трапляються рідко й нічого не додають, тож ціле число лишається цілим. */
private fun hryvnia(amount: Double): String =
    if (amount == amount.toLong().toDouble()) amount.toLong().toString()
    else "%.2f".format(ukrainian, amount)
