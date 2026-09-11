package app.poruch.android.feature.editor

import android.content.Context
import androidx.core.content.edit

/**
 * Keeps an unpublished draft across process death. Only new events are saved: an edit already has
 * its record on the server, and a stale local copy would silently overwrite it.
 */
class DraftStore(context: Context) {
    private val store = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    /**
     * Місто підставляємо, координати — ні.
     *
     * Раніше порожні координати заповнювались центром міста, і нова подія з першого кадру
     * вважалась такою, де крапку вже поставили: підпис казав «позначено», пін стояв посеред
     * Києва, а опублікувати її можна було, жодного разу не торкнувшись мапи. Порожньо — чесніше:
     * мапа однаково відкривається на місті, але як вигляд, а не як відповідь.
     */
    fun load(city: String) = EditorForm(
        title = store.read(TITLE),
        description = store.read(DESCRIPTION),
        category = store.read(CATEGORY).ifEmpty { EditorForm.DEFAULT_CATEGORY },
        city = store.read(CITY).ifEmpty { city },
        address = store.read(ADDRESS),
        latitude = store.read(LATITUDE),
        longitude = store.read(LONGITUDE),
        timeZone = store.read(ZONE).ifEmpty { java.time.ZoneId.systemDefault().id },
        starts = store.read(STARTS),
        ends = store.read(ENDS),
        capacity = store.read(CAPACITY).ifEmpty { EditorForm.DEFAULT_CAPACITY },
        minAge = store.read(MIN_AGE).ifEmpty { EditorForm.DEFAULT_MIN_AGE },
        maxAge = store.read(MAX_AGE),
        approvalRequired = store.getBoolean(APPROVAL, false)
    )

    fun save(form: EditorForm) = store.edit {
        putString(TITLE, form.title); putString(DESCRIPTION, form.description); putString(CATEGORY, form.category)
        putString(CITY, form.city); putString(ADDRESS, form.address)
        putString(LATITUDE, form.latitude); putString(LONGITUDE, form.longitude)
        putString(ZONE, form.timeZone); putString(STARTS, form.starts); putString(ENDS, form.ends)
        putString(CAPACITY, form.capacity)
        putString(MIN_AGE, form.minAge); putString(MAX_AGE, form.maxAge); putBoolean(APPROVAL, form.approvalRequired)
    }

    fun clear() = store.edit { clear() }

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
    }
}
