package app.poruch.domain

import kotlin.test.*

/** Сервер новіший за застосунок: невідоме значення не валить розбір і не відкриває зайвого. */
class ServerKeysTest {
    @Test fun unknownValuesDegradeSafely() {
        assertEquals(EventStatus.UNKNOWN, EventStatus.fromKey("archived"))
        assertEquals(EventOrigin.UNKNOWN, EventOrigin.fromKey("feed"))
        assertEquals(Membership.NONE, Membership.fromKey("invited"))
        assertEquals(ImportStatus.LIVE, ImportStatus.fromKey(null))
        // Незнайомий стан акаунта — вже обмеження, а не «активний».
        assertTrue(AccountFacts(status = AccountStatus.fromKey("frozen")).restricted)
    }

    @Test fun knownKeysRoundTrip() {
        EventStatus.entries.filter { it != EventStatus.UNKNOWN }.forEach { assertEquals(it, EventStatus.fromKey(it.key)) }
        Membership.entries.forEach { assertEquals(it, Membership.fromKey(it.key)) }
        TimeSlot.entries.forEach { assertEquals(it, TimeSlot.fromKey(it.key)) }
        Crowd.entries.forEach { assertEquals(it, Crowd.fromKey(it.key)) }
    }
}
