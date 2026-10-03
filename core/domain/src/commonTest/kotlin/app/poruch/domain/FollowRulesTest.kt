package app.poruch.domain

import kotlin.test.*
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Instant

/**
 * «Стежити»: ліміт на добу й що рахується новим. Ті самі випадки, що в `supabase/tests/follows.sql`: правило
 * живе в базі (`notify_place_follows`), а тут — його опис, який не має від неї розійтись.
 */
class FollowRulesTest {
    private val now = Instant.parse("2026-10-04T12:00:00Z")
    private val followed = now - 2.hours

    private fun listing(
        id: String, title: String, place: String = "p1", startsIn: kotlin.time.Duration = 1.days,
        createdAgo: kotlin.time.Duration = 1.hours, endsAfter: kotlin.time.Duration = 2.hours
    ) = PlaceListing(id, place, title, now + startsIn, now + startsIn + endsAfter, now - createdAgo)

    @Test fun oneAdayPerPerson() {
        assertTrue(FollowRules.mayPushPlaces(null, now), "the first push is free")
        assertFalse(FollowRules.mayPushPlaces(now - 23.hours - 59.minutes, now))
        assertTrue(FollowRules.mayPushPlaces(now - 24.hours, now), "a whole day is enough")
        assertFalse(FollowRules.mayPushPlaces(now, now))
    }

    @Test fun newIsAfterTheFollowAndNotOverAndNotToldYet() {
        val fresh = listing("a", "Стендап")
        assertTrue(FollowRules.isNew(fresh, followed, emptySet(), now))
        assertFalse(FollowRules.isNew(listing("old", "Старий", createdAgo = 3.hours), followed, emptySet(), now), "was there before the follow")
        assertFalse(FollowRules.isNew(fresh, followed, setOf("a"), now), "already told about")
        assertTrue(FollowRules.isNew(fresh, followed, setOf("other"), now), "told about the others only")
        assertFalse(FollowRules.isNew(fresh.copy(createdAt = followed), followed, emptySet(), now), "strictly after the follow")
        assertFalse(FollowRules.isNew(listing("past", "Минулий", startsIn = (-5).hours, endsAfter = 2.hours), followed, emptySet(), now), "over")
        assertTrue(FollowRules.isNew(listing("run", "Виставка", startsIn = (-1).days, endsAfter = 3.days), followed, emptySet(), now), "a running exhibition still counts")
    }

    @Test fun oneRunIsOneEventAndOnePlaceLeads() {
        val listings = listOf(
            listing("n1", "Стендап А", startsIn = 1.days), listing("n2", "Джем Б", startsIn = 2.days),
            // Другий сеанс тієї ж вистави, інакше записаний: прокат рахується раз.
            listing("n3", " стендап а ", startsIn = 3.days),
            listing("old1", "Старий концерт", startsIn = 4.days, createdAgo = 3.hours),
            listing("past1", "Минулий", startsIn = (-5).hours, endsAfter = 2.hours),
            listing("q1", "Квартирник", place = "p2", startsIn = 1.days + 1.hours)
        )
        val a = FollowRules.placePush(listings, mapOf("p1" to followed), emptySet(), null, hasDevice = true, now = now)
        assertEquals(
            PlacePush(2, 1, listOf(PlaceShare("p1", 2)), listOf("n1", "n2"), setOf("n1", "n2", "n3")), a,
            "two runs at one place; old, past and unfollowed are out; the sessions of a run are told about too"
        )

        val b = FollowRules.placePush(listings, mapOf("p1" to followed, "p2" to followed), emptySet(), null, hasDevice = true, now = now)
        assertEquals(
            PlacePush(3, 2, listOf(PlaceShare("p1", 2), PlaceShare("p2", 1)), listOf("n1", "q1", "n2"), setOf("n1", "n2", "n3", "q1")), b,
            "three runs at two places, the busier place first, three closest events"
        )
    }

    @Test fun theLimitHoldsNewEventsForTheNextDay() {
        val listings = listOf(listing("n1", "Стендап А", createdAgo = 3.hours), listing("n4", "Новий вечір", createdAgo = 1.minutes))
        val follows = mapOf("p1" to now - 1.days)
        assertNull(
            FollowRules.placePush(listings, follows, emptySet(), lastPush = now - 2.hours, hasDevice = true, now = now),
            "sent two hours ago: hold, and nothing is used up"
        )
        // Минула доба: про n1 уже казали, лишається n4.
        val nextDay = now + 23.hours + 30.minutes
        assertEquals(
            PlacePush(1, 1, listOf(PlaceShare("p1", 1)), listOf("n4"), setOf("n4")),
            FollowRules.placePush(listings, follows, announced = setOf("n1"), lastPush = now - 30.minutes, hasDevice = true, now = nextDay)
        )
        assertNull(FollowRules.placePush(emptyList(), follows, emptySet(), null, hasDevice = true, now = now), "nothing new: silence")
        assertNull(FollowRules.placePush(listings, follows, setOf("n1", "n4"), null, hasDevice = true, now = now), "everything already told")
    }

    @Test fun noDeviceNothingIsSpentAndTheNewWaits() {
        val listings = listOf(listing("n1", "Стендап А"), listing("n2", "Джем Б", startsIn = 2.days))
        val follows = mapOf("p1" to followed)
        assertNull(FollowRules.placePush(listings, follows, emptySet(), null, hasDevice = false, now = now), "nowhere to send")
        assertEquals(
            PlacePush(2, 1, listOf(PlaceShare("p1", 2)), listOf("n1", "n2"), setOf("n1", "n2")),
            FollowRules.placePush(listings, follows, emptySet(), null, hasDevice = true, now = now),
            "the device turned up: everything held back goes out"
        )
    }

    @Test fun pushNamesThreeEventsAndFivePlaces() {
        val many = (1..8).map { listing("e$it", "Подія $it", place = "p$it", startsIn = it.days) }
        val push = FollowRules.placePush(many, many.associate { it.placeId to followed }, emptySet(), null, hasDevice = true, now = now)!!
        assertEquals(8, push.total)
        assertEquals(8, push.placeCount)
        assertEquals(5, push.places.size)
        assertEquals(listOf("e1", "e2", "e3"), push.eventIds)
        assertEquals(8, push.announced.size, "everything is told about, not only the named")
    }

    private fun profile(organized: Int) = Profile("u", "Олена", null, null, null, organized, 0)
    private fun event(placeId: String?) = Event(
        "e", "Концерт", "", EventCategory.MUSIC, "Київ", "Поділ", "2026-10-04T16:00:00Z", "2026-10-04T19:00:00Z", "Europe/Kyiv",
        EventStatus.PUBLISHED, 50.45, 30.52, listing = Listing("Concert.ua", placeId = placeId)
    )

    @Test fun whoAndWhatCanBeFollowed() {
        assertTrue(FollowRules.canFollowPlace(event("p1")))
        assertFalse(FollowRules.canFollowPlace(event(null)), "no place, nothing to follow")
        assertTrue(FollowRules.canFollowOrganizer(profile(organized = 2), isMe = false))
        assertFalse(FollowRules.canFollowOrganizer(profile(organized = 0), isMe = false), "not an organizer yet")
        assertFalse(FollowRules.canFollowOrganizer(profile(organized = 2), isMe = true), "not yourself")
    }

    @Test fun ratingSheetStartsOnForANewRatingOnly() {
        assertTrue(FollowRules.followOnRating(alreadyFollowing = false, alreadyRated = false), "default on")
        assertTrue(FollowRules.followOnRating(alreadyFollowing = true, alreadyRated = false))
        assertTrue(FollowRules.followOnRating(alreadyFollowing = true, alreadyRated = true))
        assertFalse(FollowRules.followOnRating(alreadyFollowing = false, alreadyRated = true), "do not re-follow on an edit")
    }

    @Test fun followKindsRoundTrip() {
        assertEquals(FollowKind.PLACE, FollowKind.fromKey("place"))
        assertEquals(FollowKind.ORGANIZER, FollowKind.fromKey("organizer"))
        assertEquals(FollowKind.ARTIST, FollowKind.fromKey("artist"))
        assertNull(FollowKind.fromKey("group"))
        val place = Follow(FollowKind.PLACE, "p1", "Клуб", "Київ", "Хрещатик", 50.45, 30.52, upcoming = 3)
        assertEquals(Place("p1", "Клуб", "Київ", "Хрещатик", 50.45, 30.52, 3), place.place)
        assertNull(Follow(FollowKind.ORGANIZER, "u", "Олена").place)
        assertNull(place.copy(latitude = null).place, "no coordinates, no map")
    }

    @Test fun artistFollowHasNoMapAndKnowsItsKindOnlyWhenTheServerDoes() {
        val artist = Follow(FollowKind.ARTIST, "a1", "Андрій Бережко", upcoming = 23, artistKind = ArtistKind.PERSON)
        assertNull(artist.place, "an artist is not on the map")
        assertNull(Follow(FollowKind.ARTIST, "a2", "Хтось").artistKind)
        assertEquals(ArtistKind.GROUP, ArtistKind.fromKey("group"))
        assertNull(ArtistKind.fromKey("band"), "unknown kind is not shown")
        assertEquals(ArtistRole.SUPPORT, ArtistRole.fromKey("opener"), "unknown role is a plain participant")
        assertEquals(ArtistRole.HOST, ArtistRole.fromKey("host"))
    }
}
