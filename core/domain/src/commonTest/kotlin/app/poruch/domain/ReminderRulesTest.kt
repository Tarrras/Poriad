package app.poruch.domain

import kotlin.test.*
import kotlin.time.Duration.Companion.days
import kotlin.time.Instant
import kotlinx.datetime.TimeZone

/**
 * Кому й коли нагадувати: власні події й схвалена участь — за годину, збережені — напередодні о 18:00,
 * лише майбутнє, лише за згодою, лише з акаунтом.
 */
class ReminderRulesTest {
    private val me = "me"
    private val kyiv = TimeZone.of("Europe/Kyiv")
    // Вівторок, 15 вересня 2026, 15:00 за Києвом.
    private val now = Instant.parse("2026-09-15T12:00:00Z")

    private fun event(
        id: String, startsAt: String, organizer: String = "someone", joined: Boolean = false,
        status: EventStatus = EventStatus.PUBLISHED, room: Boolean = true
    ) = Event(
        id = id, title = "Настілки", description = "", category = EventCategory.GAMES, city = "Київ",
        address = "Поділ", startsAt = startsAt, endsAt = startsAt, timeZone = "Europe/Kyiv",
        status = status, latitude = 50.45, longitude = 30.52,
        gathering = if (room) Gathering(organizer, "", 10, 1, joined) else null,
        listing = if (room) null else Listing(sourceName = "Karabas")
    )

    private fun plan(events: List<Event>, saved: List<String> = emptyList(), user: String? = me, enabled: Boolean = true) =
        ReminderRules.plan(events, saved, user, enabled, now, kyiv)

    @Test fun ownAndJoinedEventsGetAReminderAnHourBefore() {
        val mine = event("own", "2026-09-15T18:00:00Z", organizer = me)
        val joined = event("joined", "2026-09-16T18:00:00Z", joined = true)
        val reminders = plan(listOf(joined, mine))
        assertEquals(listOf("own", "joined"), reminders.map { it.eventId })
        assertEquals(Instant.parse("2026-09-15T17:00:00Z").toEpochMilliseconds(), reminders.first().fireAtEpochMillis)
        assertTrue(reminders.all { it.tomorrowAt == null })
    }

    @Test fun strangersListingsAndCancelledAreSkipped() {
        val stranger = event("stranger", "2026-09-15T18:00:00Z")
        val listing = event("listing", "2026-09-15T18:00:00Z", room = false)
        val cancelled = event("cancelled", "2026-09-15T18:00:00Z", organizer = me, status = EventStatus.CANCELLED)
        assertTrue(plan(listOf(stranger, listing, cancelled)).isEmpty())
    }

    @Test fun savedEventsGetADayBeforeReminderAtSix() {
        // Четвер, 19:00 за Києвом → середа, 18:00 (15:00 UTC).
        val concert = event("concert", "2026-09-17T16:00:00Z", room = false)
        val reminder = plan(listOf(concert), saved = listOf("concert")).single()
        assertEquals(Instant.parse("2026-09-16T15:00:00Z").toEpochMilliseconds(), reminder.fireAtEpochMillis)
        assertEquals("19:00", reminder.tomorrowAt)
    }

    @Test fun savedTooSoonOrCancelledGetsNothing() {
        // Сьогодні о 21:00: «напередодні о 18:00» вже вчора.
        val tonight = event("tonight", "2026-09-15T18:00:00Z", room = false)
        val cancelled = event("cancelled", "2026-09-18T16:00:00Z", room = false, status = EventStatus.CANCELLED)
        assertTrue(plan(listOf(tonight, cancelled), saved = listOf("tonight", "cancelled")).isEmpty())
    }

    @Test fun savedAndJoinedGetsOnlyTheHourBefore() {
        val joined = event("joined", "2026-09-17T16:00:00Z", joined = true)
        val reminder = plan(listOf(joined), saved = listOf("joined")).single()
        assertNull(reminder.tomorrowAt)
        assertEquals(Instant.parse("2026-09-17T15:00:00Z").toEpochMilliseconds(), reminder.fireAtEpochMillis)
    }

    @Test fun nothingWithinTheLeadOrInThePast() {
        val soon = event("soon", "2026-09-15T12:30:00Z", organizer = me)
        val past = event("past", "2026-09-14T18:00:00Z", organizer = me)
        assertTrue(plan(listOf(soon, past)).isEmpty())
    }

    @Test fun nearestFirstUpToTheIosCap() {
        val saved = (1..70).map { day -> event("s$day", (Instant.parse("2026-09-17T16:00:00Z") + day.days).toString(), room = false) }
        val reminders = plan(saved.reversed(), saved = saved.map { it.id })
        assertEquals(ReminderRules.MAX_SCHEDULED, reminders.size)
        assertEquals("s1", reminders.first().eventId)
    }

    @Test fun guestsAndOptOutsGetNothing() {
        val mine = event("own", "2026-09-15T18:00:00Z", organizer = me)
        val concert = event("concert", "2026-09-17T16:00:00Z", room = false)
        assertTrue(plan(listOf(mine, concert), saved = listOf("concert"), enabled = false).isEmpty())
        assertTrue(plan(listOf(mine, concert), saved = listOf("concert"), user = null).isEmpty())
    }
}
