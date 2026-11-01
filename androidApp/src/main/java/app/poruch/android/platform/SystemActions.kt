package app.poruch.android.platform

import android.annotation.SuppressLint
import android.provider.Settings
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import android.widget.Toast
import androidx.annotation.StringRes
import app.poruch.android.R
import app.poruch.android.ui.dateWords
import app.poruch.android.ui.eventTime
import android.content.ClipData
import androidx.core.content.FileProvider
import app.poruch.domain.Event
import app.poruch.domain.EventMedia
import app.poruch.domain.MediaKind
import app.poruch.domain.PoruchLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import app.poruch.domain.EventLinks
import app.poruch.domain.StoreLinks
import app.poruch.shared.PoruchApp
import org.koin.java.KoinJavaComponent
import java.time.Instant

// Передача в системні застосунки. Кожна функція повертає, чи був обробник, щоб тап не мовчав.

/** Поділитись через будь-який застосунок. Посилання в кінці: Telegram і месенджери розгортають з нього прев'ю. */
fun Context.shareEvent(event: Event) {
    val summary = getString(R.string.share_event_text, event.title, eventTime(event, dateWords()), "${event.city}, ${event.address}", EventLinks.url(event.id))
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, event.title)
        putExtra(Intent.EXTRA_TEXT, summary)
    }
    startActivity(Intent.createChooser(intent, getString(R.string.share_chooser)))
    KoinJavaComponent.get<PoruchApp>(PoruchApp::class.java).eventShared()
}

/** «Покликати» (docs/invites.md): те саме, але голосом людини й з посиланням, яке дав спільний шар. `share` він уже порахував. */
fun Context.inviteEvent(event: Event, link: String) {
    val text = getString(R.string.invite_share_text, event.displayTitle, eventTime(event, dateWords()), "${event.city}, ${event.address}", link)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, event.displayTitle)
        putExtra(Intent.EXTRA_TEXT, text)
    }
    startActivity(Intent.createChooser(intent, getString(R.string.invite_chooser)))
}

/** Пошук компанії щойно створено: «Шукаю компанію на …» з посиланням на супутник, а не на афішу. */
fun Context.shareCompanion(parent: Event, companionId: String) {
    val text = getString(R.string.companion_share_text, parent.title, eventTime(parent, dateWords()), EventLinks.url(companionId))
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
    }
    startActivity(Intent.createChooser(intent, getString(R.string.companion_share_chooser)))
}

/**
 * «Пост для Threads» (docs/organizers-1.5.md, 1.5): системне меню з текстом і всіма фото й відео події. Threads з меню
 * бере лише медіа, тож текст ще й у буфері — людина вставляє його сама. Файли — копіями в кеші для FileProvider.
 */
suspend fun Context.shareThreadsPost(media: List<EventMedia>, text: String) {
    // Файли качаються кілька секунд: другий тап за цей час не починає ще одне завантаження й друге меню.
    if (!preparingThreadsPost.compareAndSet(false, true)) return
    try { prepareThreadsPost(media, text) } finally { preparingThreadsPost.set(false) }
}

/** Фото й відео події для посту; подія до 1.5 — її обкладинка. */
val Event.shareMedia: List<EventMedia> get() = media.ifEmpty { listOfNotNull(imageUrl?.let { EventMedia(MediaKind.PHOTO, it) }) }

/** «Поділитися з другом» з «Подію створено»: лише посилання, особисте `?by=` від спільного шару. */
fun Context.shareLink(link: String) {
    val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, link)
    startActivity(Intent.createChooser(intent, getString(R.string.share_friend)))
}

private val preparingThreadsPost = AtomicBoolean(false)

private suspend fun Context.prepareThreadsPost(media: List<EventMedia>, text: String) {
    copyText(text)
    toast(R.string.threads_copied)
    val files = withContext(Dispatchers.IO) {
        // Своя тека на кожне поширення: застосунок, куди поділились, може ще читати файли попереднього. Старші за годину
        // вже нікому не потрібні.
        val root = File(cacheDir, "send/threads")
        root.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > THREADS_FILES_TTL_MS }?.forEach { it.deleteRecursively() }
        val folder = File(root, System.currentTimeMillis().toString()).apply { mkdirs() }
        media.mapIndexedNotNull { index, item ->
            val file = File(folder, "${index + 1}.${if (item.kind == MediaKind.VIDEO) "mp4" else "jpg"}")
            // Без файлу — пост без нього, а не без меню: текст однаково в буфері.
            runCatching { download(item.url, file); item.kind to file }
                .onFailure { file.delete(); PoruchLog.w("share") { "threads media skipped: ${it.javaClass.simpleName}" } }.getOrNull()
        }
    }
    val uris = files.map { (_, file) -> FileProvider.getUriForFile(this, "$packageName.files", file) }
    val intent = if (uris.isEmpty()) Intent(Intent.ACTION_SEND).setType("text/plain")
    else Intent(Intent.ACTION_SEND_MULTIPLE).apply {
        type = files.map { it.first }.distinct().singleOrNull()?.let { if (it == MediaKind.VIDEO) "video/mp4" else "image/jpeg" } ?: "*/*"
        putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
        clipData = ClipData.newRawUri(null, uris.first()).apply { uris.drop(1).forEach { addItem(ClipData.Item(it)) } }
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    intent.putExtra(Intent.EXTRA_TEXT, text)
    startActivity(Intent.createChooser(intent, getString(R.string.threads_post)))
}

/** Файл зі Storage з таймаутами: без них повільна мережа тримала б «готуємо» безкінечно. */
private fun download(url: String, file: File) {
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.connectTimeout = DOWNLOAD_CONNECT_MS
    connection.readTimeout = DOWNLOAD_READ_MS
    try {
        connection.inputStream.use { input -> file.outputStream().use(input::copyTo) }
    } finally { connection.disconnect() }
}

private const val THREADS_FILES_TTL_MS = 3_600_000L
private const val DOWNLOAD_CONNECT_MS = 10_000
private const val DOWNLOAD_READ_MS = 20_000

/** «Поділитися застосунком» з профілю: готовий текст із посиланням на сайт, де обидва стори. */
fun Context.shareApp() {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, getString(R.string.share_app_text, StoreLinks.SHARE))
    }
    startActivity(Intent.createChooser(intent, getString(R.string.share_app)))
}

/** Сторінка в Google Play: застосунок Play Маркет, а без нього — сайт. Пакет прод, бо dev у сторі нема. */
fun Context.openStorePage(): Boolean =
    runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=${StoreLinks.ANDROID_PACKAGE}"))) }.isSuccess ||
        openLink(StoreLinks.PLAY)

/** Копія в системному календарі переживає наші локальні сповіщення. */
fun Context.addToCalendar(event: Event): Boolean {
    val start = runCatching { Instant.parse(event.startsAt).toEpochMilli() }.getOrNull() ?: return false
    val end = runCatching { Instant.parse(event.endsAt).toEpochMilli() }.getOrNull() ?: (start + DEFAULT_DURATION_MS)
    return addToCalendar(event.title, event.description, "${event.city}, ${event.address}", event.timeZone, start, end)
}

/** Системний календар з готовими полями, без дозволів: людина сама зберігає подію в календарі. */
fun Context.addToCalendar(title: String, description: String?, location: String, timeZone: String, start: Long, end: Long): Boolean {
    val intent = Intent(Intent.ACTION_INSERT)
        .setData(CalendarContract.Events.CONTENT_URI)
        .putExtra(CalendarContract.Events.TITLE, title)
        .putExtra(CalendarContract.Events.DESCRIPTION, description)
        .putExtra(CalendarContract.Events.EVENT_LOCATION, location)
        .putExtra(CalendarContract.Events.EVENT_TIMEZONE, timeZone)
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

/** Сповіщення застосунку в системних налаштуваннях: туди веде «Відкрити налаштування», коли дозвіл забрано. */
fun Context.openNotificationSettings(): Boolean {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
    return runCatching { startActivity(intent) }.isSuccess
}

/** Сторінка застосунку в системних налаштуваннях: там вмикають геолокацію, коли дозвіл забрано. */
fun Context.openAppSettings(): Boolean {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
    return runCatching { startActivity(intent) }.isSuccess
}

/** «Будильники й нагадування» застосунку: там дозволяють точні будильники (Android 12+). */
@SuppressLint("InlinedApi")
fun Context.openAlarmSettings(): Boolean {
    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
    return runCatching { startActivity(intent) }.isSuccess
}

/** Лист у підтримку: адресу підставляємо, тему й текст пише людина. */
fun Context.writeEmail(address: String): Boolean {
    val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$address"))
    return runCatching { startActivity(intent) }.isSuccess
}

/** Маршрут будує системна мапа. */
fun Context.openInMaps(event: Event): Boolean = openInMaps(event.latitude, event.longitude, event.title)

fun Context.openInMaps(latitude: Double, longitude: Double, label: String): Boolean {
    val uri = Uri.parse("geo:$latitude,$longitude?q=$latitude,$longitude(${Uri.encode(label)})")
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
