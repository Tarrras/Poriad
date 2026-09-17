package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.ReminderPreferenceStore

/** Прапорець нагадувань під префіксом `device:`: як і смак, належить телефону, а не акаунту. */
class LocalReminderPreference(private val database: PoruchDatabase) : ReminderPreferenceStore {
    override fun enabled(): Boolean =
        database.cacheQueries.readDevice(KEY).executeAsOneOrNull() == "true"

    override fun setEnabled(enabled: Boolean) {
        database.cacheQueries.writeDevice(KEY, enabled.toString())
    }

    private companion object {
        const val KEY = "device:reminders"
    }
}
