package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

/** Кому й коли нагадувати: власні події, схвалена участь, лише майбутнє, лише за згодою. */
class ReminderRulesTest {
    private val me = "me"
    private val now = Instant.parse("2026-09-15T12:00:00Z")

    private fun event(
        id: String, startsAt: String, organizer: String = "someone", joined: Boolean = false,
        status: String = EventStatus.PUBLISHED, room: Boolean = true
    ) = Event(
        id = id, title = "Настілки", description = "", category = "games", city = "Київ",
        address = "Поділ", startsAt = startsAt, endsAt = startsAt, timeZone = "Europe/Kyiv",
        status = status, latitude = 50.45, longitude = 30.52,
        gathering = if (room) Gathering(organizer, "", 10, 1, joined) else null,
        listing = if (room) null else Listing(sourceName = "Karabas")
    )

    @Test fun ownAndJoinedEventsGetAReminderAnHourBefore() {
        val mine = event("own", "2026-09-15T18:00:00Z", organizer = me)
        val joined = event("joined", "2026-09-16T18:00:00Z", joined = true)
        val plan = ReminderRules.plan(listOf(joined, mine), me, enabled = true, now = now)
        assertEquals(listOf("own", "joined"), plan.map { it.eventId })
        assertEquals(Instant.parse("2026-09-15T17:00:00Z").toEpochMilliseconds(), plan.first().fireAtEpochMillis)
    }

    @Test fun strangersListingsAndCancelledAreSkipped() {
        val saved = event("saved", "2026-09-15T18:00:00Z")
        val listing = event("listing", "2026-09-15T18:00:00Z", room = false)
        val cancelled = event("cancelled", "2026-09-15T18:00:00Z", organizer = me, status = EventStatus.CANCELLED)
        assertTrue(ReminderRules.plan(listOf(saved, listing, cancelled), me, enabled = true, now = now).isEmpty())
    }

    @Test fun nothingWithinTheLeadOrInThePast() {
        val soon = event("soon", "2026-09-15T12:30:00Z", organizer = me)
        val past = event("past", "2026-09-14T18:00:00Z", organizer = me)
        assertTrue(ReminderRules.plan(listOf(soon, past), me, enabled = true, now = now).isEmpty())
    }

    @Test fun guestsAndOptOutsGetNothing() {
        val mine = event("own", "2026-09-15T18:00:00Z", organizer = me)
        assertTrue(ReminderRules.plan(listOf(mine), me, enabled = false, now = now).isEmpty())
        assertTrue(ReminderRules.plan(listOf(mine), null, enabled = true, now = now).isEmpty())
    }
}
