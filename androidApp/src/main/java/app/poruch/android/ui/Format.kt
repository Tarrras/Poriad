package app.poruch.android.ui

import androidx.compose.ui.graphics.vector.ImageVector
import app.poruch.android.R
import app.poruch.domain.Event
import app.poruch.domain.EventRules
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The domain's vocabulary, in the domain's order — the labels below line up with it index by index. */
val categories = EventRules.categories
private val categoryLabels = listOf(R.string.music, R.string.sport, R.string.art, R.string.food, R.string.games, R.string.outdoors, R.string.social)

fun categoryLabel(key: String) = categoryLabels.getOrElse(categories.indexOf(key)) { R.string.all }

fun categoryIcon(category: String): ImageVector = when (category) {
    "music" -> PoruchIcons.music
    "sport" -> PoruchIcons.sport
    "art" -> PoruchIcons.art
    "food" -> PoruchIcons.food
    "games" -> PoruchIcons.games
    "outdoors" -> PoruchIcons.outdoors
    else -> PoruchIcons.social
}

private val ukrainian: Locale = Locale.forLanguageTag("uk")

private fun zoned(event: Event) = runCatching { Instant.parse(event.startsAt).atZone(ZoneId.of(event.timeZone)) }.getOrNull()

/** Overline above a card title: «СБ, 11 ЛИП · 18:30». Always rendered in the event's own zone. */
fun eventOverline(event: Event): String = zoned(event)
    ?.format(DateTimeFormatter.ofPattern("EEE, d MMM · HH:mm", ukrainian))?.uppercase(ukrainian)
    ?: event.startsAt

/** Long form for the detail screen, with the zone abbreviation so travellers are not misled. */
fun eventTime(event: Event): String = zoned(event)
    ?.format(DateTimeFormatter.ofPattern("EEEE, d MMMM · HH:mm z", ukrainian))
    ?: event.startsAt

fun eventSeatsLeft(event: Event): Int = (event.capacity - event.attendeeCount).coerceAtLeast(0)

/** True once the remaining capacity is small enough to be worth an urgency badge. */
fun eventScarce(event: Event): Boolean {
    val left = eventSeatsLeft(event)
    return !event.isCancelled && left in 1..(event.capacity / SCARCITY_FRACTION).coerceAtLeast(MIN_SCARCE_SEATS)
}

/** A fifth of the room left reads as "hurry"; below three seats it always does. */
private const val SCARCITY_FRACTION = 5
private const val MIN_SCARCE_SEATS = 3
