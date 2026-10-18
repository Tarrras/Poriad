package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.data.platformDatabaseDriver
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LocalReminderPreferenceTest {
    private val database = PoruchDatabase(platformDatabaseDriver())

    /** Нагадування за годину — з першого дозволу системи, звідки б він не прийшов; «ні» людини пам'ятається. */
    @Test
    fun remindersAreOnUntilTurnedOff() {
        assertTrue(LocalReminderPreference(database).enabled())
        LocalReminderPreference(database).setEnabled(false)
        assertFalse(LocalReminderPreference(database).enabled())
        LocalReminderPreference(database).setEnabled(true)
        assertTrue(LocalReminderPreference(database).enabled())
    }
}
