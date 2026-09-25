package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant
import kotlinx.datetime.TimeZone

class MyEventsRulesTest {
    // Четвер, 25 вересня 2026, 12:00 за Києвом.
    private val now = Instant.parse("2026-09-25T09:00:00Z")
    private val kyiv = TimeZone.of("Europe/Kyiv")

    private fun room(
        id: String, starts: String, hours: Int = 2, organizer: String = "host", joined: Boolean = false,
        membership: String = if (joined) Membership.APPROVED else Membership.NONE, status: String = EventStatus.PUBLISHED
    ): Event {
        val start = Instant.parse(starts)
        return Event(
            id = id, title = id, description = "", category = "games", city = "Київ", address = "Поділ",
            startsAt = starts, endsAt = (start + kotlin.time.Duration.parse("${hours}h")).toString(), timeZone = "Europe/Kyiv",
            status = status, latitude = 0.0, longitude = 0.0,
            gathering = Gathering(organizerId = organizer, organizerName = "", capacity = 10, attendeeCount = 3, joined = joined, membership = membership)
        )
    }

    private fun board(
        events: List<Event>, saved: List<String> = emptyList(), queued: List<String> = emptyList(),
        requests: List<JoinRequest> = emptyList(), unread: List<String> = emptyList()
    ) = MyEventsRules.board(events, "me", saved, queued, requests, unread, now, kyiv)

    private fun MyEventsBoard.ids(tab: MyEventsTab) = sections(tab).associate { s -> s.group to s.events.map { it.id } }

    @Test fun requestedAndQueuedEventsAreGoing() {
        val events = listOf(
            room("tonight", "2026-09-25T16:30:00Z", joined = true),
            room("asked", "2026-09-27T09:00:00Z", membership = Membership.REQUESTED),
            room("queued", "2026-09-30T16:00:00Z"),
            room("stranger", "2026-09-30T16:00:00Z")
        )
        val b = board(events, queued = listOf("queued"))
        assertEquals(
            mapOf(MyEventsGroup.TODAY to listOf("tonight"), MyEventsGroup.UPCOMING to listOf("asked", "queued")),
            b.ids(MyEventsTab.GOING)
        )
        assertEquals(3, b.goingAhead)
        assertEquals(1, b.awaiting)
    }

    @Test fun pastKeepsOnlyAttendedNotCancelledNewestFirst() {
        val events = listOf(
            room("old", "2026-09-10T16:00:00Z", joined = true),
            room("cancelled", "2026-09-18T16:00:00Z", joined = true, status = EventStatus.CANCELLED),
            room("fresh", "2026-09-24T16:00:00Z", joined = true),
            room("askedPast", "2026-09-23T16:00:00Z", membership = Membership.REQUESTED)
        )
        assertEquals(mapOf(MyEventsGroup.PAST to listOf("fresh", "old")), board(events).ids(MyEventsTab.GOING))
    }

    @Test fun underwayCountsAsToday() {
        val events = listOf(room("now", "2026-09-25T08:00:00Z", hours = 3, joined = true))
        assertEquals(mapOf(MyEventsGroup.TODAY to listOf("now")), board(events).ids(MyEventsTab.GOING))
    }

    @Test fun ownEventsGoToOrganizingOnly() {
        val events = listOf(
            room("mine", "2026-09-26T15:00:00Z", organizer = "me"),
            room("minePast", "2026-09-18T15:00:00Z", organizer = "me")
        )
        val b = board(events, requests = listOf(
            JoinRequest("mine", "u1", "Дмитро", null, "2026-09-25T08:40:00Z"),
            JoinRequest("minePast", "u2", "Оля", null, "2026-09-17T08:40:00Z")
        ), unread = listOf("mine", "minePast"))
        assertTrue(b.isEmpty(MyEventsTab.GOING))
        assertEquals(
            mapOf(MyEventsGroup.UPCOMING to listOf("mine"), MyEventsGroup.PAST to listOf("minePast")),
            b.ids(MyEventsTab.ORGANIZING)
        )
        assertEquals(1, b.requests)
        assertEquals(3, b.organizingBadge)
    }

    @Test fun savedSplitsByCalendarWeekAndDropsEnded() {
        val events = listOf(
            room("sunday", "2026-09-27T17:00:00Z"),
            room("monday", "2026-09-28T17:00:00Z"),
            room("gone", "2026-09-20T17:00:00Z")
        )
        val b = board(events, saved = listOf("sunday", "monday", "gone"))
        assertEquals(
            mapOf(MyEventsGroup.THIS_WEEK to listOf("sunday"), MyEventsGroup.LATER to listOf("monday")),
            b.ids(MyEventsTab.SAVED)
        )
        assertEquals(2, b.savedAhead)
        assertEquals(1, b.savedThisWeek)
    }

    @Test fun guestHasNothing() {
        val b = MyEventsRules.board(listOf(room("x", "2026-09-26T15:00:00Z", joined = true)), null, emptyList(), emptyList(), emptyList(), emptyList(), now, kyiv)
        assertEquals(MyEventsBoard(), b)
    }
}
