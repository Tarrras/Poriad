package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant
import kotlinx.datetime.TimeZone

/** Дайджест: до чотирьох пʼятниць о 17:00, лише події суботи й неділі після кожної, не менше трьох. */
class DigestRulesTest {
    private val kyiv = TimeZone.of("Europe/Kyiv")
    // Середа, 23 вересня 2026, полудень у Києві. Пʼятниця — 25-го, вихідні — 26–27-го.
    private val wednesday = Instant.parse("2026-09-23T09:00:00Z")
    private val fridayFire = Instant.parse("2026-09-25T14:00:00Z").toEpochMilliseconds()

    private fun entry(id: String, startsAt: String, sessions: List<String> = emptyList()) = EventIndexEntry(
        id = id, latitude = 50.45, longitude = 30.52, category = EventCategory.GAMES,
        startsAt = startsAt, timeZone = "Europe/Kyiv", title = "Подія $id", origin = EventOrigin.IMPORT,
        sessions = sessions.mapIndexed { i, s -> EventSession("$id-$i", s, "Europe/Kyiv") }
    )

    private val weekend = listOf(
        entry("a", "2026-09-26T10:00:00Z"),
        entry("b", "2026-09-27T16:00:00Z"),
        entry("c", "2026-09-25T21:30:00Z") // субота, 00:30 за Києвом
    )

    /** [count] подій на суботу [saturday] (YYYY-MM-DD), полудень за Києвом. */
    private fun saturday(saturday: String, count: Int) = (1..count).map { entry("$saturday-$it", "${saturday}T09:00:00Z") }

    @Test fun countsSaturdayAndSundayAndFiresFridayAtFive() {
        val friday = entry("fri", "2026-09-25T17:00:00Z")
        val monday = entry("mon", "2026-09-27T21:00:00Z") // понеділок, 00:00 за Києвом
        val digest = DigestRules.plan(weekend + friday + monday, "Київ", enabled = true, now = wednesday, zone = kyiv).single()
        assertEquals(3, digest.count)
        assertEquals(listOf("Подія a", "Подія b"), digest.titles)
        assertEquals(fridayFire, digest.fireAtEpochMillis)
        assertEquals("Київ", digest.city)
        assertEquals(1, digest.week)
    }

    @Test fun runCountsWhenAnySessionFallsOnTheWeekend() {
        val run = entry("run", "2026-09-24T16:00:00Z", listOf("2026-09-24T16:00:00Z", "2026-09-26T16:00:00Z"))
        assertEquals(4, DigestRules.plan(weekend + run, null, true, wednesday, kyiv).single().count)
    }

    @Test fun afterFridayFiveItTargetsNextWeek() {
        val fridayEvening = Instant.parse("2026-09-25T15:00:00Z")
        val next = listOf("2026-10-03T10:00:00Z", "2026-10-03T12:00:00Z", "2026-10-04T10:00:00Z").mapIndexed { i, s -> entry("n$i", s) }
        val digest = DigestRules.plan(weekend + next, "Київ", true, fridayEvening, kyiv).single()
        assertEquals(3, digest.count)
        assertEquals(Instant.parse("2026-10-02T14:00:00Z").toEpochMilliseconds(), digest.fireAtEpochMillis)
        assertEquals(1, digest.week)
    }

    @Test fun ladderCoversFourFridaysSkipsThinOnesAndStopsAfterTheFourth() {
        // Середа, 14 жовтня: пʼятниці 16, 23, 30 жовтня й 6 листопада; 25 жовтня Київ переходить на зимовий час.
        val now = Instant.parse("2026-10-14T09:00:00Z")
        val index = saturday("2026-10-17", 4) + saturday("2026-10-24", 2) + saturday("2026-10-31", 3) +
            saturday("2026-11-07", 5) + saturday("2026-11-14", 6)
        val ladder = DigestRules.plan(index, "Київ", true, now, kyiv)
        assertEquals(listOf(1, 3, 4), ladder.map { it.week })
        assertEquals(listOf(4, 3, 5), ladder.map { it.count })
        assertEquals(
            listOf("2026-10-16T14:00:00Z", "2026-10-30T15:00:00Z", "2026-11-06T15:00:00Z").map { Instant.parse(it).toEpochMilliseconds() },
            ladder.map { it.fireAtEpochMillis }
        )
    }

    @Test fun silentWhenDisabledOrTooFew() {
        assertTrue(DigestRules.plan(weekend, "Київ", enabled = false, now = wednesday, zone = kyiv).isEmpty())
        assertTrue(DigestRules.plan(weekend.take(2), "Київ", enabled = true, now = wednesday, zone = kyiv).isEmpty())
    }
}
