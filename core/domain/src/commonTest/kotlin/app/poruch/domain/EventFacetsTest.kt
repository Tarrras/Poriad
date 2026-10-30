package app.poruch.domain

import kotlin.test.*

/** Межа між кімнатою та оголошенням. Кожен тест охороняє одну помилку, яку раніше не помічали. */
class EventFacetsTest {

    private fun base(gathering: Gathering? = null, listing: Listing? = null, description: String = "") = Event(
        id = "e", title = "Подія", description = description, category = EventCategory.MUSIC,
        city = "Київ", address = "Поділ", startsAt = "2030-09-06T19:00:00Z",
        endsAt = "2030-09-06T22:00:00Z", timeZone = "Europe/Kyiv", status = EventStatus.PUBLISHED,
        latitude = 50.45, longitude = 30.52, gathering = gathering, listing = listing
    )

    private val room = Gathering(organizerId = "u1", organizerName = "Оля", capacity = 10, attendeeCount = 3, joined = false)
    private val afisha = Listing(sourceName = "Karabas", canonicalUrl = "https://kyiv.karabas.com/e/1", priceMin = 350.0)

    @Test fun aListingHasNoSeatsToShow() {
        val event = base(listing = afisha)
        assertNull(event.gathering)
        assertFalse(event.isCommunity)
        // Була вада: конвеєр писав capacity=1, і картка казала «Лишилось 1 місце».
        assertEquals("Karabas", event.publisherName)
        assertNull(event.organizerId)
    }

    @Test fun aRoomKnowsItsOwnArithmetic() {
        val event = base(gathering = room)
        assertEquals(7, event.gathering?.seatsLeft)
        assertFalse(event.gathering!!.isFull)
        assertTrue(event.isCommunity)
        assertEquals("u1", event.organizerId)
        assertEquals("Оля", event.publisherName)
    }

    /** Поріг «мало місць» спільний для обох платформ. */
    @Test fun scarcityIsAFifthOfTheRoomAndNeverFewerThanThree() {
        assertTrue(room.copy(capacity = 100, attendeeCount = 80).isScarce)   // 20 з 100
        assertFalse(room.copy(capacity = 100, attendeeCount = 79).isScarce)  // 21 з 100
        assertTrue(room.copy(capacity = 6, attendeeCount = 3).isScarce)      // 3 місця з малої кімнати
        assertFalse(room.copy(capacity = 6, attendeeCount = 2).isScarce)
        // Нуль місць — «Місць немає», а не «лишилось 0».
        assertFalse(room.copy(capacity = 10, attendeeCount = 10).isScarce)
        // Порожня кімната — ще ніхто не прийшов, поспішати нема куди; перший гість робить її дефіцитом.
        assertFalse(room.copy(capacity = 2, attendeeCount = 0).isScarce)
        assertTrue(room.copy(capacity = 2, attendeeCount = 1).isScarce)
    }

    /** docs/event-ingestion.md §8: чужий опис обрізаємо, свій показуємо цілком. */
    @Test fun onlyABorrowedDescriptionIsCut() {
        val long = "я".repeat(Event.LISTING_DESCRIPTION_PREVIEW + 50)
        val borrowed = base(listing = afisha, description = long)
        assertTrue(borrowed.descriptionTruncated)
        assertEquals(Event.LISTING_DESCRIPTION_PREVIEW + 1, borrowed.displayDescription.length)
        assertTrue(borrowed.displayDescription.endsWith("…"))

        val ours = base(gathering = room, description = long)
        assertFalse(ours.descriptionTruncated)
        assertEquals(long, ours.displayDescription)

        // Короткий чужий опис не обрізається.
        val short = base(listing = afisha, description = "Концерт у МЦКМ")
        assertFalse(short.descriptionTruncated)
        assertEquals("Концерт у МЦКМ", short.displayDescription)
    }

    @Test fun aWithdrawnListingSaysSoAndAButtonWithoutAnAddressIsNotOffered() {
        assertFalse(afisha.isWithdrawn)
        assertTrue(afisha.hasSource)
        // Стан рахується при створенні: `copy(status = …)` його не перераховує, тож знята — новим рядком.
        assertTrue(Listing("Karabas", status = ImportStatus.WITHDRAWN).isWithdrawn)
        assertEquals(ListingState.UNKNOWN, Listing("Karabas", status = ImportStatus.WITHDRAWN).state)
        assertFalse(afisha.copy(canonicalUrl = null).hasSource)
        assertFalse(afisha.copy(canonicalUrl = " ").hasSource)
    }

    @Test fun listingStatesDriveTheStubAndTheTicketButton() {
        val cancelled = base(listing = afisha.copy(state = ListingState.CANCELLED))
        val postponed = base(listing = afisha.copy(state = ListingState.POSTPONED))
        val unknown = base(listing = afisha.copy(state = ListingState.UNKNOWN))
        val moved = afisha.copy(previousStartsAt = "2030-09-05T16:00:00Z")
        assertTrue(cancelled.isCancelled && cancelled.isCalledOff)
        assertTrue(!postponed.isCancelled && postponed.isCalledOff, "postponed greys the stub but is not cancelled")
        assertTrue(!unknown.isCalledOff && unknown.listing!!.isWithdrawn, "not found: no alarm, no ticket button")
        assertTrue(moved.isMoved && !moved.isWithdrawn, "moved is alive")
        assertFalse(afisha.copy(state = ListingState.POSTPONED, previousStartsAt = "2030-09-05T16:00:00Z").isMoved)
    }

    @Test fun sellersPutThePrimaryFirstAndNameEveryLiveOne() {
        // Сервер без фази 4: продавець — лише основний з полів події.
        assertEquals(listOf(Offer("Karabas", afisha.canonicalUrl, afisha.priceMin, afisha.isFree, true)), afisha.sellers)
        assertEquals("Karabas", afisha.sellerNames)
        val many = afisha.copy(offers = listOf(
            Offer("Concert.ua", "https://concert.ua/1", 400.0), Offer("Karabas", "https://karabas.com/1", 450.0),
            Offer("Badseller", "https://badseller.net/1", 300.0, live = false), Offer("Без посилання", null)
        ))
        assertEquals("Concert.ua, Karabas, Без посилання", many.sellerNames, "badge names every live seller, not the withdrawn one")
        assertEquals(listOf("Concert.ua", "Karabas", "Badseller"), many.sellers.map { it.sourceName }, "no link, no button")
    }

    @Test fun aSellerReportShowsOnlyWhileTheEventStands() {
        val report = Offer("Badseller", "https://badseller.net/1", live = false, reported = ListingState.CANCELLED)
        val disputed = afisha.copy(offers = listOf(Offer("Concert.ua", "https://concert.ua/1", 400.0), report))
        assertEquals(report, disputed.sellerReport)
        assertTrue(disputed.needsAttention && !disputed.isWithdrawn, "the event stands, the tickets block comes first")
        assertNull(disputed.copy(state = ListingState.CANCELLED).sellerReport, "cancelled: the stamp already says it")
        assertFalse(afisha.needsAttention)
    }

    @Test fun checkedLabelSaysTodayYesterdayOrTheDate() {
        val zone = kotlinx.datetime.TimeZone.of("Europe/Kyiv")
        val now = kotlin.time.Instant.parse("2030-09-06T12:00:00Z")
        assertEquals(CheckedLabel(CheckedDay.TODAY, "09:00", "06.09"), CheckedLabel.of("2030-09-06T06:00:00Z", now, zone))
        assertEquals(CheckedDay.YESTERDAY, CheckedLabel.of("2030-09-05T20:30:00Z", now, zone)?.day)
        // 22:30 UTC 5-го — уже 6-те за Києвом.
        assertEquals(CheckedDay.TODAY, CheckedLabel.of("2030-09-05T22:30:00Z", now, zone)?.day)
        assertEquals(CheckedLabel(CheckedDay.EARLIER, "12:00", "01.09"), CheckedLabel.of("2030-09-01T09:00:00Z", now, zone))
        assertNull(CheckedLabel.of(null, now, zone))
        assertNull(CheckedLabel.of("вчора", now, zone))
    }
}
