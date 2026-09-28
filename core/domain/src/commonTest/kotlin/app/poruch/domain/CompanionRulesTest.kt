package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

/** «Шукаю компанію»: коли пропонувати, який час зустрічі і що сервер відхилить. */
class CompanionRulesTest {
    private val start = "2026-10-04T16:00:00Z"
    private val now = Instant.parse("2026-10-04T10:00:00Z")

    private fun listing(startsAt: String = start, status: EventStatus = EventStatus.PUBLISHED, import: ImportStatus = ImportStatus.LIVE) = Event(
        id = "e", title = "Концерт", description = "", category = EventCategory.MUSIC, city = "Київ", address = "Поділ",
        startsAt = startsAt, endsAt = "2026-10-04T19:00:00Z", timeZone = "Europe/Kyiv", status = status,
        latitude = 50.45, longitude = 30.52, listing = Listing("Concert.ua", status = import)
    )

    @Test fun offeredOnlyOnLiveFutureListing() {
        assertTrue(CompanionRules.canOffer(listing(), now))
        assertFalse(CompanionRules.canOffer(listing(startsAt = "2026-10-04T09:00:00Z"), now), "started")
        assertFalse(CompanionRules.canOffer(listing(status = EventStatus.CANCELLED), now))
        assertFalse(CompanionRules.canOffer(listing(import = ImportStatus.WITHDRAWN), now))
        val room = listing().copy(listing = null, gathering = Gathering("u", "Олена", 4, 0, false))
        assertFalse(CompanionRules.canOffer(room, now), "community events have their own door")
    }

    @Test fun meetTimesStepQuarterHoursWithinThreeHours() {
        val times = CompanionRules.meetTimes(start, now)
        assertEquals(13, times.size)
        assertEquals("2026-10-04T13:00:00Z", times.first())
        assertEquals(start, times.last())
        assertEquals("2026-10-04T15:30:00Z", CompanionRules.defaultMeetAt(start, now))
    }

    @Test fun lateCallerGetsOnlyFutureTimes() {
        val late = Instant.parse("2026-10-04T15:40:00Z")
        assertEquals(listOf("2026-10-04T15:45:00Z", start), CompanionRules.meetTimes(start, late))
        assertEquals("2026-10-04T15:45:00Z", CompanionRules.defaultMeetAt(start, late), "30 min before is gone")
        assertNull(CompanionRules.defaultMeetAt(start, Instant.parse("2026-10-04T16:00:00Z")))
        assertNull(CompanionRules.defaultMeetAt("not a date", now))
    }

    @Test fun validateMirrorsServer() {
        assertEquals(emptyList(), CompanionRules.validate(start, "2026-10-04T15:30:00Z", "Біля входу", 4, now))
        assertEquals(emptyList(), CompanionRules.validate(start, "2026-10-04T13:00:00Z", null, 2, now), "window edge")
        assertEquals(listOf(DraftField.STARTS_AT), CompanionRules.validate(start, "2026-10-04T16:01:00Z", null, 4, now))
        assertEquals(listOf(DraftField.STARTS_AT), CompanionRules.validate(start, "2026-10-04T12:59:00Z", null, 4, now))
        assertEquals(listOf(DraftField.STARTS_AT), CompanionRules.validate(start, "2026-10-04T09:59:00Z", null, 4, Instant.parse("2026-10-04T14:00:00Z")))
        assertEquals(listOf(DraftField.DESCRIPTION), CompanionRules.validate(start, start, "x".repeat(141), 4, now))
        assertEquals(emptyList(), CompanionRules.validate(start, start, " " + "x".repeat(140) + " ", 4, now), "trimmed like the server")
        assertEquals(listOf(DraftField.CAPACITY), CompanionRules.validate(start, start, null, 1, now))
        assertEquals(listOf(DraftField.CAPACITY), CompanionRules.validate(start, start, null, 9, now))
    }

    @Test fun fullCompanion() {
        val card = CompanionCard("c", start, "Europe/Kyiv", null, 4, 4, Membership.NONE, false)
        assertTrue(card.isFull)
        assertFalse(card.copy(attendeeCount = 3).isFull)
    }
}
