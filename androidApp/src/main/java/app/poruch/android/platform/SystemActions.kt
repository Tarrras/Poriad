package app.poruch.android.platform

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import android.widget.Toast
import androidx.annotation.StringRes
import app.poruch.android.R
import app.poruch.android.ui.dateWords
import app.poruch.android.ui.eventTime
import app.poruch.domain.Event
import java.time.Instant

/**
 * Hand-offs to apps the reader already trusts. Each returns whether a handler existed, so the
 * caller can say so rather than leaving a tap that did nothing.
 */

/** Sharing hands the event to any app the reader already uses; no in-app invitations to maintain. */
fun Context.shareEvent(event: Event) {
    val summary = getString(R.string.share_event_text, event.title, eventTime(event, dateWords()), "${event.city}, ${event.address}")
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, event.title)
        putExtra(Intent.EXTRA_TEXT, summary)
    }
    startActivity(Intent.createChooser(intent, getString(R.string.share_chooser)))
}

/** The system calendar owns reminders we cannot: a copy there outlives our local notifications. */
fun Context.addToCalendar(event: Event): Boolean {
    val start = runCatching { Instant.parse(event.startsAt).toEpochMilli() }.getOrNull() ?: return false
    val end = runCatching { Instant.parse(event.endsAt).toEpochMilli() }.getOrNull() ?: (start + DEFAULT_DURATION_MS)
    val intent = Intent(Intent.ACTION_INSERT)
        .setData(CalendarContract.Events.CONTENT_URI)
        .putExtra(CalendarContract.Events.TITLE, event.title)
        .putExtra(CalendarContract.Events.DESCRIPTION, event.description)
        .putExtra(CalendarContract.Events.EVENT_LOCATION, "${event.city}, ${event.address}")
        .putExtra(CalendarContract.Events.EVENT_TIMEZONE, event.timeZone)
        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start)
        .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
    return runCatching { startActivity(intent) }.isSuccess
}

/**
 * Афішу купують і дочитують на джерелі, а не в нас: своєї каси ми не маємо, а повний чужий опис
 * не маємо права показувати (docs/event-ingestion.md §8). Тому єдина дія над нею — вихід назовні.
 */
fun Context.openLink(url: String): Boolean {
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
    if (uri.scheme != "https") return false
    return runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }.isSuccess
}

/** Routing belongs to the maps app the reader already trusts, not to a half-built one of ours. */
fun Context.openInMaps(event: Event): Boolean {
    val label = Uri.encode(event.title)
    val uri = Uri.parse("geo:${event.latitude},${event.longitude}?q=${event.latitude},${event.longitude}($label)")
    return runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }.isSuccess
}

fun Context.toast(@StringRes message: Int) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()

/** An event with an unparseable end still needs one in the calendar; an hour is the safe guess. */
private const val DEFAULT_DURATION_MS = 3_600_000L
