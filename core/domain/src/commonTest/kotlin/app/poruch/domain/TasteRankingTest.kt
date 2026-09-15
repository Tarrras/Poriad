package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

/** Обіцянка ранжування: інтерес перемагає, нічого не ховається, порожній смак не змінює порядок. */
class TasteRankingTest {
    private val now = Instant.parse("2030-09-04T09:00:00Z")

    private fun event(
        id: String, category: String = "music", startsAt: String = "2030-09-06T19:00:00+03:00",
        capacity: Int = 20, attendees: Int = 0, status: String = EventStatus.PUBLISHED
    ) = Event(
        id = id, title = id, description = "", category = category, city = "Київ", address = "Поділ",
        startsAt = startsAt, endsAt = startsAt, timeZone = "Europe/Kyiv", status = status,
        latitude = 50.45, longitude = 30.52,
        gathering = Gathering(
            organizerId = "organizer", organizerName = "Організатор",
            capacity = capacity, attendeeCount = attendees, joined = false
        )
    )

    /** Афіша: та сама подія без кімнати. */
    private fun listing(id: String, category: String = "music", startsAt: String = "2030-09-06T19:00:00+03:00") = Event(
        id = id, title = id, description = "", category = category, city = "Київ", address = "Поділ",
        startsAt = startsAt, endsAt = startsAt, timeZone = "Europe/Kyiv", status = EventStatus.PUBLISHED,
        latitude = 50.45, longitude = 30.52, listing = Listing(sourceName = "Karabas")
    )

    // 2030-09-06 — п'ятниця, 2030-09-07 — субота.
    private val fridayEvening = "2030-09-06T19:00:00+03:00"
    private val fridayMorning = "2030-09-06T10:00:00+03:00"
    private val saturdayEvening = "2030-09-07T20:00:00+03:00"
    private val saturdayMorning = "2030-09-07T11:00:00+03:00"

    @Test fun slotsFollowTheEventsOwnClock() {
        assertEquals(TimeSlot.WEEKDAY_EVENING, TasteRanking.slotOf(event("a", startsAt = fridayEvening)))
        assertEquals(TimeSlot.WEEKDAY_DAY, TasteRanking.slotOf(event("b", startsAt = fridayMorning)))
        assertEquals(TimeSlot.WEEKEND_EVENING, TasteRanking.slotOf(event("c", startsAt = saturdayEvening)))
        assertEquals(TimeSlot.WEEKEND_DAY, TasteRanking.slotOf(event("d", startsAt = saturdayMorning)))
    }

    @Test fun theChosenSubjectComesFirst() {
        val taste = Taste(interests = listOf("art"), answered = true)
        val ranked = TasteRanking.rank(listOf(event("music"), event("art", category = "art")), taste, now)
        assertEquals("art", ranked.first().id)
    }

    @Test fun nothingIsEverDropped() {
        val taste = Taste(interests = listOf("art"), times = listOf(TimeSlot.WEEKEND_DAY), answered = true)
        val all = listOf(event("a"), event("b", category = "food"), event("c", category = "sport"))
        assertEquals(all.map { it.id }.toSet(), TasteRanking.rank(all, taste, now).map { it.id }.toSet())
    }

    @Test fun aFreeEveningOutranksASubjectlessMatch() {
        val taste = Taste(times = listOf(TimeSlot.WEEKEND_EVENING), answered = true)
        val ranked = TasteRanking.rank(
            listOf(event("friday", startsAt = fridayEvening), event("saturday", startsAt = saturdayEvening)), taste, now
        )
        assertEquals("saturday", ranked.first().id)
    }

    @Test fun aFullEventSinksBelowAnOpenOne() {
        val taste = Taste(interests = listOf("music"), answered = true)
        val ranked = TasteRanking.rank(
            listOf(event("full", capacity = 10, attendees = 10), event("open", capacity = 10)), taste, now
        )
        assertEquals("open", ranked.first().id)
    }

    @Test fun aCancelledEventGoesLast() {
        val taste = Taste(interests = listOf("music"), answered = true)
        val ranked = TasteRanking.rank(
            listOf(event("cancelled", status = EventStatus.CANCELLED), event("other", category = "food")), taste, now
        )
        assertEquals("cancelled", ranked.last().id)
    }

    @Test fun anIntimateTasteRanksTheSmallRoomHigher() {
        val taste = Taste(crowd = Crowd.INTIMATE, answered = true)
        val ranked = TasteRanking.rank(listOf(event("hall", capacity = 200), event("table", capacity = 8)), taste, now)
        assertEquals("table", ranked.first().id)
    }

    @Test fun withoutAnswersTheOrderIsSimplyChronological() {
        val ranked = TasteRanking.rank(
            listOf(event("later", startsAt = saturdayEvening), event("sooner", startsAt = fridayMorning)),
            Taste(answered = true), now
        )
        assertEquals(listOf("sooner", "later"), ranked.map { it.id })
    }

    @Test fun onlyAnAnsweredQuestionMakesASuggestion() {
        val taste = Taste(interests = listOf("art"), times = listOf(TimeSlot.WEEKEND_EVENING), answered = true)
        assertTrue(TasteRanking.matches(event("a", category = "art"), taste))
        assertTrue(TasteRanking.matches(event("b", category = "food", startsAt = saturdayEvening), taste))
        assertFalse(TasteRanking.matches(event("c", category = "food", startsAt = fridayMorning), taste))
        assertFalse(TasteRanking.matches(event("d", category = "art", status = EventStatus.CANCELLED), taste))
    }

    /** docs/event-discovery.md §4.2: імпорт — тло. Виходить само собою, бо бали за місця отримує лише кімната. */
    @Test fun aListingNeverOutranksACommunityEventItTies() {
        val taste = Taste(interests = listOf("music"), answered = true)
        val ranked = TasteRanking.rank(listOf(listing("afisha"), event("community")), taste, now)
        assertEquals(listOf("community", "afisha"), ranked.map { it.id })
        assertTrue(TasteRanking.score(event("community"), taste, now) > TasteRanking.score(listing("afisha"), taste, now))
    }

    /** «Яка компанія» — питання про кімнату, афіша його не проходить. */
    @Test fun crowdSizeIsNotAskedOfAListing() {
        val taste = Taste(crowd = Crowd.INTIMATE, answered = true)
        // Кімната на 8 місць — «камерно» плюс вільні місця; афіша не заробляє нічого.
        assertEquals(
            TasteRanking.score(listing("afisha"), taste, now) + TasteRanking.CROWD + TasteRanking.SEATS,
            TasteRanking.score(event("table", capacity = 8), taste, now)
        )
    }

    /** Подія, що вже йде, змагається як «зараз». Той самий ключ рахує сервер: `greatest(starts_at, now())`. */
    @Test fun whatIsAlreadyUnderwayCountsAsNowNotAsTheDayItBegan() {
        val underway = listOf(
            listing("вчорашній", startsAt = "2030-09-03T19:00:00+03:00"),
            listing("липневий", startsAt = "2030-07-16T10:00:00+03:00")
        ).map { it.copy(endsAt = "2030-09-30T20:00:00+03:00") }
        val future = listing("завтрашній", startsAt = "2030-09-06T19:00:00+03:00")

        val ranked = TasteRanking.rank(underway + future, Taste(), now)
        // Обидва, що вже йдуть, попереду майбутнього і в порядку сервера між собою.
        assertEquals(listOf("вчорашній", "липневий", "завтрашній"), ranked.map { it.id })
    }

    /** Битий часовий пояс не має валити весь список. */
    @Test fun brokenTimestampsRankWithoutThrowing() {
        val broken = event("broken", startsAt = "not-a-date").copy(timeZone = "Mars/Olympus")
        val ranked = TasteRanking.rank(listOf(broken, event("fine")), Taste(interests = listOf("music"), answered = true), now)
        assertEquals(2, ranked.size)
        assertNull(TasteRanking.slotOf(broken))
    }
}
