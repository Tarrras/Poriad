package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

class RatingRulesTest {
    private fun event(joined: Boolean, status: String = EventStatus.PUBLISHED) = Event(
        id = "e", title = "Пікнік", description = "", category = "outdoors", city = "Київ", address = "Труханів",
        startsAt = "2026-09-20T11:00:00Z", endsAt = "2026-09-20T14:00:00Z", timeZone = "Europe/Kyiv", status = status,
        latitude = 0.0, longitude = 0.0,
        gathering = Gathering(organizerId = "o", organizerName = "Оля", capacity = 10, attendeeCount = 3, joined = joined)
    )
    private fun at(iso: String) = Instant.parse(iso)

    @Test fun onlyMembersRateAfterTheEndWithinTwoWeeks() {
        assertFalse(RatingRules.canRate(event(joined = true), at("2026-09-20T13:00:00Z")))
        assertTrue(RatingRules.canRate(event(joined = true), at("2026-09-20T14:00:00Z")))
        assertTrue(RatingRules.canRate(event(joined = true), at("2026-10-04T13:59:00Z")))
        assertFalse(RatingRules.canRate(event(joined = true), at("2026-10-04T14:00:00Z")))
        assertFalse(RatingRules.canRate(event(joined = false), at("2026-09-21T00:00:00Z")))
        assertFalse(RatingRules.canRate(event(joined = true, status = EventStatus.CANCELLED), at("2026-09-21T00:00:00Z")))
    }

    @Test fun averageRoundsToOneDecimal() {
        assertNull(RatingRules.average(emptyList()))
        val r = listOf(5, 4, 4).map { EventRating(it, null, "", false) }
        assertEquals(4.3, RatingRules.average(r))
    }

    @Test fun tagCountsMostFrequentFirst() {
        val r = listOf(
            listOf(RatingTag.PEOPLE, RatingTag.MUSIC), listOf(RatingTag.MUSIC), listOf(RatingTag.ATMOSPHERE)
        ).map { EventRating(5, null, "", false, it) }
        assertEquals(
            listOf(TagCount(RatingTag.MUSIC, 2), TagCount(RatingTag.ATMOSPHERE, 1), TagCount(RatingTag.PEOPLE, 1)),
            RatingRules.tagCounts(r)
        )
        assertNull(RatingTag.fromKey("bribe"))
    }

    @Test fun everyCategoryOffersSixDistinctTags() {
        EventRules.categories.forEach { category ->
            val tags = RatingRules.tagsFor(category)
            assertEquals(6, tags.toSet().size, category)
        }
        assertTrue(RatingTag.GAME_CHOICE in RatingRules.tagsFor("games"))
        assertFalse(RatingTag.MUSIC in RatingRules.tagsFor("games"))
        assertEquals(5, RatingRules.tagsFor("невідома").size)
    }
}
