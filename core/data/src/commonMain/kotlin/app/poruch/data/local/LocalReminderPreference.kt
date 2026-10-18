package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.ReminderPreferenceStore

/** Прапорець нагадувань під префіксом `device:`: як і смак, належить телефону, а не акаунту. */
class LocalReminderPreference(private val database: PoruchDatabase) : ReminderPreferenceStore {
    /**
     * Увімкнено, поки людина не вимкнула, як і дайджест: справжній замок — дозвіл системи. Інакше дозвіл,
     * даний не з приєднання (підписка, дайджест, Налаштування, Android до 13), лишав нагадування вимкненими.
     */
    override fun enabled(): Boolean =
        database.cacheQueries.readDevice(KEY).executeAsOneOrNull() != "false"

    override fun setEnabled(enabled: Boolean) {
        database.cacheQueries.writeDevice(KEY, enabled.toString())
    }

    /** Увімкнено, поки людина не вимкнула: рядка нема — так. */
    override fun digestEnabled(): Boolean =
        database.cacheQueries.readDevice(DIGEST).executeAsOneOrNull() != "false"

    override fun setDigestEnabled(enabled: Boolean) {
        database.cacheQueries.writeDevice(DIGEST, enabled.toString())
    }

    private companion object {
        const val KEY = "device:reminders"
        const val DIGEST = "device:digest"
    }
}
