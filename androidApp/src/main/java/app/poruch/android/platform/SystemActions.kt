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

// Передача в системні застосунки. Кожна функція повертає, чи був обробник, щоб тап не мовчав.

/** Поділитись через будь-який застосунок; своїх запрошень не тримаємо. */
fun Context.shareEvent(event: Event) {
    val summary = getString(R.string.share_event_text, event.title, eventTime(event, dateWords()), "${event.city}, ${event.address}")
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, event.title)
        putExtra(Intent.EXTRA_TEXT, summary)
    }
    startActivity(Intent.createChooser(intent, getString(R.string.share_chooser)))
}

/** Копія в системному календарі переживає наші локальні сповіщення. */
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

/** Афішу купують і дочитують на джерелі (docs/event-ingestion.md §8). */
fun Context.openLink(url: String): Boolean {
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
    if (uri.scheme != "https") return false
    return runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }.isSuccess
}

/** Лист у підтримку: адресу підставляємо, тему й текст пише людина. */
fun Context.writeEmail(address: String): Boolean {
    val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$address"))
    return runCatching { startActivity(intent) }.isSuccess
}

/** Маршрут будує системна мапа. */
fun Context.openInMaps(event: Event): Boolean {
    val label = Uri.encode(event.title)
    val uri = Uri.parse("geo:${event.latitude},${event.longitude}?q=${event.latitude},${event.longitude}($label)")
    return runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }.isSuccess
}

fun Context.toast(@StringRes message: Int) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()

/** Текст у буфер обміну без позначки «чутливе»: це повідомлення чату, а не пароль. */
fun Context.copyText(text: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
    clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Poruch", text))
}

/** Тривалість для календаря, якщо кінець не розібрався. */
private const val DEFAULT_DURATION_MS = 3_600_000L
