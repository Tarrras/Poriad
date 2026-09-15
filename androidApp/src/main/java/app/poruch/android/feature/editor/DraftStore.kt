package app.poruch.android.feature.editor

import android.content.Context
import androidx.core.content.edit

/** Тримає неопубліковану чернетку після смерті процесу. Лише нові події: редагування має запис на сервері. */
class DraftStore(context: Context) {
    private val store = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    /** Місто підставляємо, координати — ні: центр міста як крапка дозволяв опублікувати подію, не торкнувшись мапи. */
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
        approvalRequired = store.getBoolean(APPROVAL, false),
        contactUrl = store.read(CONTACT)
    )

    fun save(form: EditorForm) = store.edit {
        putString(TITLE, form.title); putString(DESCRIPTION, form.description); putString(CATEGORY, form.category)
        putString(CITY, form.city); putString(ADDRESS, form.address)
        putString(LATITUDE, form.latitude); putString(LONGITUDE, form.longitude)
        putString(ZONE, form.timeZone); putString(STARTS, form.starts); putString(ENDS, form.ends)
        putString(CAPACITY, form.capacity)
        putString(MIN_AGE, form.minAge); putString(MAX_AGE, form.maxAge); putBoolean(APPROVAL, form.approvalRequired)
        putString(CONTACT, form.contactUrl)
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
        const val CONTACT = "contact"
    }
}
