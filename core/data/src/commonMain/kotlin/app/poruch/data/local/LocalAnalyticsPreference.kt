package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.AnalyticsPreferenceStore

/** Згода на аналітику під префіксом `device:`: належить телефону. Нічого не записано — збір увімкнено. */
class LocalAnalyticsPreference(private val database: PoruchDatabase) : AnalyticsPreferenceStore {
    override fun enabled(): Boolean =
        database.cacheQueries.readDevice(KEY).executeAsOneOrNull() != "false"

    override fun setEnabled(enabled: Boolean) {
        database.cacheQueries.writeDevice(KEY, enabled.toString())
    }

    private companion object {
        const val KEY = "device:analytics"
    }
}
