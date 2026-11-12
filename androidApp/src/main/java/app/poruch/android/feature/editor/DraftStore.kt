package app.poruch.android.feature.editor

import app.poruch.domain.EventCategory
import android.content.Context
import androidx.core.content.edit
import app.poruch.domain.DraftMedia
import app.poruch.domain.EventMedia
import app.poruch.domain.MediaKind

/**
 * Тримає неопубліковану чернетку після смерті процесу. Лише нові події: редагування має запис на сервері. Фото й відео —
 * файлами в [files], тут лише їхній порядок.
 */
class DraftStore(context: Context, private val files: DraftMediaFiles) {
    private val store = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    /** Місто підставляємо, координати — ні: центр міста як крапка дозволяв опублікувати подію, не торкнувшись мапи. */
    fun load(city: String): EditorForm {
        // Минулий початок у давній чернетці — не намір, а давність: дату обирають заново.
        val stale = runCatching {
            java.time.LocalDateTime.parse(store.read(STARTS), EditorForm.LOCAL_FORMAT) <= java.time.LocalDateTime.now()
        }.getOrDefault(false)
        return EditorForm(
            title = store.read(TITLE),
            description = store.read(DESCRIPTION),
            category = EventCategory.fromKey(store.read(CATEGORY)).takeIf { it != EventCategory.UNKNOWN } ?: EditorForm.DEFAULT_CATEGORY,
            city = store.read(CITY).ifEmpty { city },
            address = store.read(ADDRESS),
            latitude = store.read(LATITUDE),
            longitude = store.read(LONGITUDE),
            timeZone = store.read(ZONE).ifEmpty { java.time.ZoneId.systemDefault().id },
            starts = if (stale) "" else store.read(STARTS),
            ends = if (stale) "" else store.read(ENDS),
            capacity = store.read(CAPACITY).ifEmpty { EditorForm.DEFAULT_CAPACITY },
            minAge = store.read(MIN_AGE).ifEmpty { EditorForm.DEFAULT_MIN_AGE },
            maxAge = store.read(MAX_AGE),
            approvalRequired = store.getBoolean(APPROVAL, false),
            contactUrl = store.read(CONTACT), price = store.read(PRICE), prepay = store.getBoolean(PREPAY, false),
            // Старі чернетки без прапорця: платна — та, де є ціна.
            paid = store.getBoolean(PAID, store.read(PRICE).isNotEmpty()),
            template = app.poruch.domain.MeetupTemplate.fromKey(store.read(TEMPLATE)),
            linkOnly = store.getBoolean(LINK_ONLY, false),
            media = store.read(MEDIA).lines().mapNotNull(::media)
        ).also { form ->
            // Файли прибраних і опублікованих чернеток: редагування своїх файлів не лишає (їх прибирає модель).
            files.prune(form.media.filterIsInstance<DraftMedia.Local>().mapTo(HashSet()) { it.key })
        }
    }

    fun save(form: EditorForm) = store.edit {
        putString(TITLE, form.title); putString(DESCRIPTION, form.description); putString(CATEGORY, form.category.key)
        putString(CITY, form.city); putString(ADDRESS, form.address)
        putString(LATITUDE, form.latitude); putString(LONGITUDE, form.longitude)
        putString(ZONE, form.timeZone); putString(STARTS, form.starts); putString(ENDS, form.ends)
        putString(CAPACITY, form.capacity)
        putString(MIN_AGE, form.minAge); putString(MAX_AGE, form.maxAge); putBoolean(APPROVAL, form.approvalRequired)
        putString(CONTACT, form.contactUrl); putString(PRICE, form.price); putBoolean(PREPAY, form.prepay); putBoolean(PAID, form.paid)
        putString(MEDIA, form.media.joinToString("\n", transform = ::line)); putString(TEMPLATE, form.template?.key.orEmpty())
        putBoolean(LINK_ONLY, form.linkOnly)
    }

    fun clear() {
        store.edit { clear() }
        files.prune(emptySet())
    }

    /** Рядок на файл: вид запису, вид файлу, ключ чи адреса й постер. Адреси без табуляцій і переносів. */
    private fun line(media: DraftMedia) = when (media) {
        is DraftMedia.Local -> "L\t${media.kind.key}\t${media.key}"
        is DraftMedia.Remote -> "R\t${media.kind.key}\t${media.media.url}\t${media.media.poster.orEmpty()}"
        is DraftMedia.Copied -> "C\t${media.kind.key}\t${media.media.url}\t${media.media.poster.orEmpty()}"
    }

    private fun media(line: String): DraftMedia? {
        val parts = line.split('\t')
        val kind = MediaKind.fromKey(parts.getOrNull(1)) ?: return null
        val value = parts.getOrNull(2)?.takeIf { it.isNotEmpty() } ?: return null
        val remote by lazy { EventMedia(kind, value, parts.getOrNull(3)?.takeIf { it.isNotEmpty() }) }
        return when (parts[0]) {
            "L" -> files.local(value, kind).takeIf { files.file(value, kind).exists() }
            "R" -> DraftMedia.Remote(remote)
            "C" -> DraftMedia.Copied(remote)
            else -> null
        }
    }

    private fun android.content.SharedPreferences.read(key: String) = getString(key, "").orEmpty()

    private companion object {
        const val NAME = "event_draft"
        const val TITLE = "title"
        const val DESCRIPTION = "description"
        const val CATEGORY = "category"
        const val CITY = "city"
        const val ADDRESS = "address"
        const val LATITUDE = "latitude"
        const val LONGITUDE = "longitude"
        const val ZONE = "zone"
        const val STARTS = "starts"
        const val ENDS = "ends"
        const val CAPACITY = "capacity"
        const val MIN_AGE = "min_age"
        const val MAX_AGE = "max_age"
        const val APPROVAL = "approval"
        const val CONTACT = "contact"
        const val PRICE = "price"
        const val PREPAY = "prepay"
        const val PAID = "paid"
        const val MEDIA = "media"
        const val TEMPLATE = "template"
        const val LINK_ONLY = "link_only"
    }
}
