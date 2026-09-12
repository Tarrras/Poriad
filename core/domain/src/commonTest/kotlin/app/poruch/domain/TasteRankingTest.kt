package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

/**
 * The ranking is the one place where the answers to the opening questions turn into what a person
 * sees, so what is guarded here is the promise made to them: their subject wins, nothing is hidden,
 * and the order does not change when the taste is empty.
 */
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

    /** Афіша: та сама подія на мапі, але без кімнати — саме тому вона рахується інакше. */
    private fun listing(id: String, category: String = "music", startsAt: String = "2030-09-06T19:00:00+03:00") = Event(
        id = id, title = id, description = "", category = category, city = "Київ", address = "Поділ",
        startsAt = startsAt, endsAt = startsAt, timeZone = "Europe/Kyiv", status = EventStatus.PUBLISHED,
        latitude = 50.45, longitude = 30.52, listing = Listing(sourceName = "Karabas")
    )

    // 2030-09-06 is a Friday, 2030-09-07 a Saturday.
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

    /**
     * docs/event-discovery.md §4.2: імпорт заповнює тло, а не змагається за увагу. Це виходить
     * само собою — бали за вільні місця отримує лише кімната, — і саме тому тут немає окремого
     * штрафу «бо це імпорт», який довелося б підкручувати.
     */
    @Test fun aListingNeverOutranksACommunityEventItTies() {
        val taste = Taste(interests = listOf("music"), answered = true)
        val ranked = TasteRanking.rank(listOf(listing("afisha"), event("community")), taste, now)
        assertEquals(listOf("community", "afisha"), ranked.map { it.id })
        assertTrue(TasteRanking.score(event("community"), taste, now) > TasteRanking.score(listing("afisha"), taste, now))
    }

    /** «Яка компанія» — питання про кімнату. Афіші його не ставлять, тож вона його й не проходить. */
    @Test fun crowdSizeIsNotAskedOfAListing() {
        val taste = Taste(crowd = Crowd.INTIMATE, answered = true)
        // Кімната на 8 місць відповідає «камерно» і має вільні місця; афіша не заробляє ні того, ні того.
        assertEquals(
            TasteRanking.score(listing("afisha"), taste, now) + TasteRanking.CROWD + TasteRanking.SEATS,
            TasteRanking.score(event("table", capacity = 8), taste, now)
        )
    }

    /**
     * Подія, що вже йде, змагається як «зараз», а не як дата, з якої вона йде.
     *
     * Поки ключем був `startsAt`, найдовший прокат ставав першим у стрічці й лишався там до
     * кінця: виставка, що почалась у липні, обганяла все, що почалось учора. Той самий ключ
     * рахує сервер (`greatest(starts_at, now())`), і розійтись їм не можна — вікно карток
     * приїжджає під серверний порядок.
     */
    @Test fun whatIsAlreadyUnderwayCountsAsNowNotAsTheDayItBegan() {
        val underway = listOf(
            listing("вчорашній", startsAt = "2030-09-03T19:00:00+03:00"),
            listing("липневий", startsAt = "2030-07-16T10:00:00+03:00")
        ).map { it.copy(endsAt = "2030-09-30T20:00:00+03:00") }
        val future = listing("завтрашній", startsAt = "2030-09-06T19:00:00+03:00")

        val ranked = TasteRanking.rank(underway + future, Taste(), now)
        // Обидва, що вже йдуть, попереду майбутнього — і між собою лишаються в порядку сервера,
        // а не в порядку того, хто почався давніше.
        assertEquals(listOf("вчорашній", "липневий", "завтрашній"), ranked.map { it.id })
    }

    /** A bad time zone in a row from the server must not take the whole list down with it. */
    @Test fun brokenTimestampsRankWithoutThrowing() {
        val broken = event("broken", startsAt = "not-a-date").copy(timeZone = "Mars/Olympus")
        val ranked = TasteRanking.rank(listOf(broken, event("fine")), Taste(interests = listOf("music"), answered = true), now)
        assertEquals(2, ranked.size)
        assertNull(TasteRanking.slotOf(broken))
    }
}
