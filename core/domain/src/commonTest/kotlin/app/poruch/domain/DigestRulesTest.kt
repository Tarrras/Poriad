package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant
import kotlinx.datetime.TimeZone

/** Дайджест: найближча пʼятниця о 17:00, лише події суботи й неділі після неї, не менше трьох. */
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

    @Test fun countsSaturdayAndSundayAndFiresFridayAtFive() {
        val friday = entry("fri", "2026-09-25T17:00:00Z")
        val monday = entry("mon", "2026-09-27T21:00:00Z") // понеділок, 00:00 за Києвом
        val digest = DigestRules.plan(weekend + friday + monday, "Київ", enabled = true, now = wednesday, zone = kyiv)!!
        assertEquals(3, digest.count)
        assertEquals(listOf("Подія a", "Подія b"), digest.titles)
        assertEquals(fridayFire, digest.fireAtEpochMillis)
        assertEquals("Київ", digest.city)
    }

    @Test fun runCountsWhenAnySessionFallsOnTheWeekend() {
        val run = entry("run", "2026-09-24T16:00:00Z", listOf("2026-09-24T16:00:00Z", "2026-09-26T16:00:00Z"))
        assertEquals(4, DigestRules.plan(weekend + run, null, true, wednesday, kyiv)?.count)
    }

    @Test fun afterFridayFiveItTargetsNextWeek() {
        val fridayEvening = Instant.parse("2026-09-25T15:00:00Z")
        val next = listOf("2026-10-03T10:00:00Z", "2026-10-03T12:00:00Z", "2026-10-04T10:00:00Z").mapIndexed { i, s -> entry("n$i", s) }
        val digest = DigestRules.plan(weekend + next, "Київ", true, fridayEvening, kyiv)!!
        assertEquals(3, digest.count)
        assertEquals(Instant.parse("2026-10-02T14:00:00Z").toEpochMilliseconds(), digest.fireAtEpochMillis)
    }

    @Test fun silentWhenDisabledOrTooFew() {
        assertNull(DigestRules.plan(weekend, "Київ", enabled = false, now = wednesday, zone = kyiv))
        assertNull(DigestRules.plan(weekend.take(2), "Київ", enabled = true, now = wednesday, zone = kyiv))
    }
}
