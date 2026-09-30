package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

class HomeRulesTest {
    /** Вівторок, 12:00 у Києві. */
    private val now = Instant.parse("2026-09-29T09:00:00Z")
    private val zone = "Europe/Kyiv"

    private fun event(
        id: String, startsAt: String = "2026-09-30T16:00:00Z", endsAt: String = "2026-09-30T18:00:00Z",
        category: EventCategory = EventCategory.GAMES, listing: Listing? = null, gathering: Gathering? = null,
        status: EventStatus = EventStatus.PUBLISHED
    ) = Event(
        id = id, title = id, description = "", category = category, city = "Київ", address = "Поділ",
        startsAt = startsAt, endsAt = endsAt, timeZone = "Europe/Kyiv", status = status, latitude = 0.0, longitude = 0.0,
        gathering = gathering, listing = listing
    )

    private fun feed(
        forYou: List<String> = emptyList(), city: List<String> = emptyList(), following: List<String> = emptyList(),
        skip: Set<String> = emptySet()
    ) = HomeRules.feed(forYou.map { event(it) }, city.map { event(it) }, following.map { event(it) }, skip).map { it.event.id to it.source }

    @Test fun takesOneFromEachSourceInTurn() {
        assertEquals(
            listOf(
                "a1" to FeedSource.FOR_YOU, "c1" to FeedSource.CITY, "f1" to FeedSource.FOLLOWING,
                "a2" to FeedSource.FOR_YOU, "c2" to FeedSource.CITY
            ),
            feed(forYou = listOf("a1", "a2"), city = listOf("c1", "c2"), following = listOf("f1"))
        )
    }

    @Test fun exhaustedSourceDoesNotStopTheOthers() {
        assertEquals(listOf("c1", "c2", "c3"), feed(city = listOf("c1", "c2", "c3")).map { it.first })
    }

    @Test fun eventStandsOnceAndStrongestSignalNamesIt() {
        // «x» — і в місті, і в підписках: стоїть там, де знайдена першою, а підпис — «Підписки».
        val result = feed(forYou = listOf("a1"), city = listOf("x", "c2"), following = listOf("x"))
        assertEquals(listOf("a1" to FeedSource.FOR_YOU, "x" to FeedSource.FOLLOWING, "c2" to FeedSource.CITY), result)
    }

    @Test fun skipsWhatIsAlreadyShownAbove() {
        assertEquals(listOf("c2"), feed(city = listOf("c1", "c2"), skip = setOf("c1")).map { it.first })
    }

    @Test fun nothingInNothingOut() {
        assertTrue(feed().isEmpty())
    }

    // ---- Зустрічі від людей

    private fun room(id: String, seatsLeft: Int = 3, status: EventStatus = EventStatus.PUBLISHED) =
        event(id, gathering = Gathering("u", "Оксана", 8, 8 - seatsLeft, false), status = status)

    private fun feedOf(forYou: List<Event> = emptyList(), city: List<Event> = emptyList(), following: List<Event> = emptyList()) =
        HomeRules.feed(forYou, city, following).map { it.event.id }

    @Test fun openRoomsTakeTheBigCardsBeforeTheListings() {
        val city = listOf(event("c1"), event("c2"), event("c3"), room("r1"), room("r2"))
        // Афіша стоїть вище за кімнати в рангу міста, а на головній — навпаки.
        assertEquals(listOf("r1", "r2"), feedOf(city = city).take(2))
    }

    @Test fun onlyHeroCountRoomsAreFrontLoadedTheRestGoFirstInEachRound() {
        val rooms = (1..5).map { room("r$it") }
        val listings = (1..5).map { event("c$it") }
        val ids = feedOf(city = listings + rooms)
        assertEquals(listOf("r1", "r2", "r3"), ids.take(HomeRules.HERO_COUNT))
        // Далі по колу: кімната, афіша, кімната, афіша… Кімнати не витісняють афішу зовсім.
        assertEquals(listOf("r4", "c1", "r5", "c2"), ids.drop(HomeRules.HERO_COUNT).take(4))
        assertEquals(10, ids.size)
    }

    @Test fun fullOrCancelledRoomsAreNotPushedForward() {
        val city = listOf(event("c1"), room("full", seatsLeft = 0), room("gone", status = EventStatus.CANCELLED), event("c2"))
        assertEquals(listOf("c1", "full", "gone", "c2"), feedOf(city = city))
    }

    @Test fun aRoomStandsOnceAndKeepsItsStrongestLabel() {
        val r = room("r1")
        val result = HomeRules.feed(forYou = listOf(r), city = listOf(r, event("c1")), following = emptyList())
        assertEquals(listOf("r1" to FeedSource.FOR_YOU, "c1" to FeedSource.CITY), result.map { it.event.id to it.source })
    }

    @Test fun roomsFromForYouComeBeforeRoomsFromTheCity() {
        val ids = feedOf(forYou = listOf(room("mine")), city = listOf(room("other"), event("c1")))
        assertEquals(listOf("mine", "other"), ids.take(2))
    }

    // ---- Секція «Від людей»

    private fun rooms(count: Int, prefix: String = "r") = (1..count).map { room("$prefix$it") }
    private fun people(city: List<Event> = emptyList(), forYou: List<Event> = emptyList(), skip: Set<String> = emptySet()) =
        HomeRules.people(forYou, city, emptyList(), skip)

    @Test fun peopleSectionWaitsForEnoughRooms() {
        assertTrue(people(city = rooms(HomeRules.PEOPLE_SECTION_MIN - 1)).isEmpty())
        assertEquals(HomeRules.PEOPLE_SECTION_MIN, people(city = rooms(HomeRules.PEOPLE_SECTION_MIN)).size)
    }

    @Test fun peopleSectionIsCappedAndKeepsListOrder() {
        val ids = people(forYou = listOf(room("mine")), city = rooms(12)).map { it.event.id }
        assertEquals(HomeRules.PEOPLE_SECTION_MAX, ids.size)
        assertEquals(listOf("mine", "r1", "r2"), ids.take(3))
    }

    @Test fun peopleSectionSkipsFullCancelledAndAlreadyShownRooms() {
        val city = listOf(room("full", seatsLeft = 0), room("gone", status = EventStatus.CANCELLED), room("own")) + rooms(HomeRules.PEOPLE_SECTION_MIN)
        val ids = people(city = city, skip = setOf("own")).map { it.event.id }
        assertEquals(rooms(HomeRules.PEOPLE_SECTION_MIN).map { it.id }, ids)
    }

    @Test fun peopleSectionLabelsEntriesByStrongestSignal() {
        val followed = room("f")
        val result = HomeRules.people(forYou = listOf(room("y")), city = rooms(HomeRules.PEOPLE_SECTION_MIN - 2), following = listOf(followed))
        assertEquals(
            listOf("y" to FeedSource.FOR_YOU, "r1" to FeedSource.CITY, "r2" to FeedSource.CITY, "r3" to FeedSource.CITY, "f" to FeedSource.FOLLOWING),
            result.map { it.event.id to it.source }
        )
    }

    @Test fun roomsFirstFalseLeavesRoomsToTheirOwnSection() {
        val city = listOf(event("c1"), event("c2"), event("c3")) + rooms(6)
        val shown = people(city = city).map { it.event.id }.toSet()
        val ids = HomeRules.feed(emptyList(), city, emptyList(), skip = shown, roomsFirst = false).map { it.event.id }
        // Секція взяла вісім із шести — усі шість; у стрічці лишились лише афіші, кімнати не повторюються.
        assertEquals(listOf("c1", "c2", "c3"), ids)
    }

    @Test fun leftoverRoomsBeyondTheCapFlowLikeAnyEventWhenTheSectionExists() {
        val city = listOf(event("c1")) + rooms(HomeRules.PEOPLE_SECTION_MAX + 2)
        val shown = people(city = city).map { it.event.id }.toSet()
        val ids = HomeRules.feed(emptyList(), city, emptyList(), skip = shown, roomsFirst = false).map { it.event.id }
        // Дві зайві кімнати не рвуться вперед великими картками: ідуть у порядку списку міста.
        assertEquals(listOf("c1", "r${HomeRules.PEOPLE_SECTION_MAX + 1}", "r${HomeRules.PEOPLE_SECTION_MAX + 2}"), ids)
    }

    @Test fun noRoomsMeansTheOldOrder() {
        assertEquals(
            listOf("a1", "c1", "f1", "a2", "c2"),
            feedOf(forYou = listOf(event("a1"), event("a2")), city = listOf(event("c1"), event("c2")), following = listOf(event("f1")))
        )
    }

    // ---- Найближчий план

    @Test fun planIsLeadWhenSoonOrWaitedFor() {
        val today = event("t", "2026-09-29T15:00:00Z", "2026-09-29T17:00:00Z")
        val tomorrow = event("m", "2026-09-30T15:00:00Z", "2026-09-30T17:00:00Z")
        val inThreeWeeks = event("f", "2026-10-20T15:00:00Z", "2026-10-20T17:00:00Z")
        assertTrue(HomeRules.isLead(today, false, now, zone))
        assertTrue(HomeRules.isLead(tomorrow, false, now, zone))
        assertFalse(HomeRules.isLead(inThreeWeeks, false, now, zone))
        assertTrue(HomeRules.isLead(inThreeWeeks, true, now, zone))
    }

    @Test fun dayAfterTomorrowIsNotSoonEvenAtMidnightSharp() {
        // Завтра закінчується о 00:00 за Києвом (21:00 UTC): подія рівно тоді вже післязавтрашня.
        assertFalse(HomeRules.isLead(event("x", "2026-09-30T21:00:00Z", "2026-09-30T23:00:00Z"), false, now, zone))
        assertTrue(HomeRules.isLead(event("y", "2026-09-30T20:59:00Z", "2026-09-30T23:00:00Z"), false, now, zone))
    }

    @Test fun endedOrCancelledPlanIsNeverLead() {
        val ended = event("e", "2026-09-29T05:00:00Z", "2026-09-29T07:00:00Z")
        val cancelled = event("c", "2026-09-29T15:00:00Z", "2026-09-29T17:00:00Z", status = EventStatus.CANCELLED)
        assertFalse(HomeRules.isLead(ended, true, now, zone))
        assertFalse(HomeRules.isLead(cancelled, true, now, zone))
    }

    @Test fun planThatIsUnderwayIsLead() {
        assertTrue(HomeRules.isLead(event("u", "2026-09-29T08:00:00Z", "2026-09-29T11:00:00Z"), false, now, zone))
    }

    // ---- Чипи

    private fun entries(vararg events: Event) = events.map { FeedEntry(it, FeedSource.CITY) }

    private val tomorrowAt = "2026-09-30T15:00:00Z"
    private val todayAt = "2026-09-29T15:00:00Z"

    @Test fun smallFeedHasNoChips() {
        assertTrue(HomeRules.chips(entries(event("a"), event("b"), event("c")), now, zone).isEmpty())
    }

    @Test fun chipsOfferOnlyWhatNarrows() {
        val music = (1..5).map { event("m$it", tomorrowAt, tomorrowAt, EventCategory.MUSIC) }
        val art = (1..3).map { event("a$it", todayAt, todayAt, EventCategory.ART) }
        val chips = HomeRules.chips(entries(*(music + art).toTypedArray()), now, zone)
        // Усе; сьогодні (3 з 8) і завтра (5 з 8) звужують; вихідні й безкоштовне — нікого; музика (5) — так, мистецтво (3) — замало.
        assertEquals(
            listOf(
                FeedFilter(), FeedFilter(FeedFilterKind.TODAY), FeedFilter(FeedFilterKind.TOMORROW),
                FeedFilter(FeedFilterKind.CATEGORY, EventCategory.MUSIC)
            ),
            chips
        )
    }

    @Test fun chipThatKeepsEverythingIsNotShown() {
        val all = (1..7).map { event("t$it", tomorrowAt, tomorrowAt) }
        assertTrue(HomeRules.chips(entries(*all.toTypedArray()), now, zone).isEmpty())
    }

    @Test fun categoriesAreOrderedByCountAndCapped() {
        val counts = listOf(
            EventCategory.MUSIC to 9, EventCategory.ART to 8, EventCategory.COMEDY to 7, EventCategory.KIDS to 6,
            EventCategory.SPORT to 5, EventCategory.GAMES to 4
        )
        val all = counts.flatMap { (category, n) -> (1..n).map { event("${category.key}$it", category = category) } }
        val shown = HomeRules.chips(entries(*all.toTypedArray()), now, zone).mapNotNull { it.category }
        assertEquals(listOf(EventCategory.MUSIC, EventCategory.ART, EventCategory.COMEDY, EventCategory.KIDS), shown)
    }

    @Test fun timeFiltersOverlapTheDay() {
        val today = event("today", todayAt, todayAt)
        val tomorrow = event("tomorrow", tomorrowAt, tomorrowAt)
        // Виставка з понеділка до наступного вівторка: і сьогодні, і завтра, і на вихідних.
        val exhibition = event("show", "2026-09-28T07:00:00Z", "2026-10-06T18:00:00Z")
        val all = entries(today, tomorrow, exhibition)
        fun ids(kind: FeedFilterKind) = HomeRules.apply(all, FeedFilter(kind), now, zone).map { it.event.id }
        assertEquals(listOf("today", "show"), ids(FeedFilterKind.TODAY))
        assertEquals(listOf("tomorrow", "show"), ids(FeedFilterKind.TOMORROW))
        assertEquals(listOf("show"), ids(FeedFilterKind.WEEKEND))
        assertEquals(all, HomeRules.apply(all, FeedFilter(), now, zone))
    }

    @Test fun weekendIsSaturdayAndSundayInLocalTime() {
        // П'ятниця 23:00 за Києвом — ще ні; субота 00:30 — вже так; понеділок 00:30 — ні.
        val friday = event("fri", "2026-10-02T20:00:00Z", "2026-10-02T20:30:00Z")
        val saturday = event("sat", "2026-10-02T21:30:00Z", "2026-10-02T22:00:00Z")
        val monday = event("mon", "2026-10-04T21:30:00Z", "2026-10-04T22:00:00Z")
        val hits = HomeRules.apply(entries(friday, saturday, monday), FeedFilter(FeedFilterKind.WEEKEND), now, zone)
        assertEquals(listOf("sat"), hits.map { it.event.id })
    }

    @Test fun freeMeansFreeListingOrPlainMeetupButNotCompanionToPaidShow() {
        fun room(companion: Boolean) = Gathering(
            "u", "Ім'я", 8, 1, false, companionOf = if (companion) CompanionParent("p", "Концерт") else null
        )
        val freeListing = event("free", listing = Listing("Афіша", isFree = true))
        val unknownPrice = event("unknown", listing = Listing("Афіша"))
        val paid = event("paid", listing = Listing("Афіша", priceMin = 300.0))
        val meetup = event("meetup", gathering = room(false))
        val companion = event("companion", gathering = room(true))
        val hits = HomeRules.apply(entries(freeListing, unknownPrice, paid, meetup, companion), FeedFilter(FeedFilterKind.FREE), now, zone)
        assertEquals(listOf("free", "meetup"), hits.map { it.event.id })
    }
}
