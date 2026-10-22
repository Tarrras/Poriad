package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.data.platformDatabaseDriver
import app.poruch.domain.PendingUnregister
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class LocalPendingUnregisterTest {
    private val database = PoruchDatabase(platformDatabaseDriver())

    /** Запис старої версії з ключем доступу й строком ще читається; новий їх уже не містить. */
    @Test
    fun anOldRecordStillReadsAndANewOneHoldsNoAccessToken() {
        val old = """{"token":"t1","user_id":"a","access_token":"jwt","expires_at":9999999999}"""
        database.cacheQueries.writeDevice("device:push-unregister", old)
        val store = LocalPendingUnregister(database)
        assertEquals(PendingUnregister("t1", "a"), store.read())

        store.write(PendingUnregister("t2", "b"))
        val stored = database.cacheQueries.readDevice("device:push-unregister").executeAsOne()
        assertFalse("access_token" in stored || "expires_at" in stored)
        assertEquals(PendingUnregister("t2", "b"), store.read())
    }
}
