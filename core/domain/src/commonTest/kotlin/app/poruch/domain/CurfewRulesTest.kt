package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

/** Рядок «до комендантської» у деталях: коли він потрібен і що в ньому. */
class CurfewRulesTest {
    private fun event(startsAt: String, endsAt: String, zone: String = "Europe/Kyiv") = Event(
        id = "e", title = "Вечір", description = "", category = EventCategory.MUSIC, city = "Київ",
        address = "Поділ", startsAt = startsAt, endsAt = endsAt, timeZone = zone,
        status = EventStatus.PUBLISHED, latitude = 50.45, longitude = 30.52
    )

    private val kyiv = Curfew("01:00", "05:00")
    private val now = Instant.parse("2026-09-28T09:00:00Z")

    @Test fun eveningEventShowsTimeLeftInEventZone() {
        val note = CurfewRules.note(event("2026-09-28T19:00:00+03:00", "2026-09-28T22:30:00+03:00"), kyiv, now)
        assertEquals(CurfewNote("22:30", kyiv, 150), note)
    }

    @Test fun endingAfterCurfewStartsIsDuring() {
        assertEquals(0, CurfewRules.note(event("2026-09-28T22:00:00+03:00", "2026-09-29T02:00:00+03:00"), kyiv, now)?.minutesLeft)
        assertEquals(0, CurfewRules.note(event("2026-09-28T22:00:00+03:00", "2026-09-29T01:00:00+03:00"), kyiv, now)?.minutesLeft)
        // Комендантська з опівночі: кінець о 00:30 — уже під час неї.
        assertEquals(0, CurfewRules.note(event("2026-09-28T21:00:00+03:00", "2026-09-29T00:30:00+03:00"), Curfew("00:00", "05:00"), now)?.minutesLeft)
    }

    @Test fun daytimeLongAndPastEventsAreSilent() {
        assertNull(CurfewRules.note(event("2026-09-28T12:00:00+03:00", "2026-09-28T15:00:00+03:00"), kyiv, now))
        assertNull(CurfewRules.note(event("2026-09-01T10:00:00+03:00", "2026-10-30T23:00:00+03:00"), kyiv, now))
        assertNull(CurfewRules.note(event("2026-09-27T19:00:00+03:00", "2026-09-27T23:00:00+03:00"), kyiv, now))
        assertNull(CurfewRules.note(event("2026-09-28T19:00:00+03:00", "2026-09-28T23:00:00+03:00"), null, now))
        assertNull(CurfewRules.note(event("2026-09-28T19:00:00+03:00", "2026-09-28T23:00:00+03:00", zone = "Nowhere/City"), kyiv, now))
    }

    @Test fun unknownShelterKindIsABasement() = assertEquals(ShelterKind.BASEMENT, ShelterKind.fromKey("bunker"))
}
