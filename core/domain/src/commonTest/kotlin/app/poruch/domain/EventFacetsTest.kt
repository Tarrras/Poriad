package app.poruch.domain

import kotlin.test.*

/**
 * Межа між кімнатою та оголошенням тримається тут, а не в рев'ю. Кожен тест нижче охороняє одне
 * речення, яке до цього поділу можна було написати неправильно й не помітити.
 */
class EventFacetsTest {

    private fun base(gathering: Gathering? = null, listing: Listing? = null, description: String = "") = Event(
        id = "e", title = "Подія", description = description, category = "music",
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
        // Саме цей рядок і був вадою: конвеєр писав capacity=1, і картка казала «Лишилось 1 місце».
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

    /** Поріг «мало місць» один на обидві платформи — до цього кожна рахувала його сама. */
    @Test fun scarcityIsAFifthOfTheRoomAndNeverFewerThanThree() {
        assertTrue(room.copy(capacity = 100, attendeeCount = 80).isScarce)   // 20 з 100
        assertFalse(room.copy(capacity = 100, attendeeCount = 79).isScarce)  // 21 з 100
        assertTrue(room.copy(capacity = 6, attendeeCount = 3).isScarce)      // 3 місця з малої кімнати
        assertFalse(room.copy(capacity = 6, attendeeCount = 2).isScarce)
        // Порожньої терміновості не буває: коли місць немає, це «Місць немає», а не «лишилось 0».
        assertFalse(room.copy(capacity = 10, attendeeCount = 10).isScarce)
    }

    /**
     * docs/event-ingestion.md §8: факти не охороняються, чужий текст опису — охороняється. Тому
     * повний опис афіші не показуємо, а свій — показуємо цілком.
     */
    @Test fun onlyABorrowedDescriptionIsCut() {
        val long = "я".repeat(Event.LISTING_DESCRIPTION_PREVIEW + 50)
        val borrowed = base(listing = afisha, description = long)
        assertTrue(borrowed.descriptionTruncated)
        assertEquals(Event.LISTING_DESCRIPTION_PREVIEW + 1, borrowed.displayDescription.length)
        assertTrue(borrowed.displayDescription.endsWith("…"))

        val ours = base(gathering = room, description = long)
        assertFalse(ours.descriptionTruncated)
        assertEquals(long, ours.displayDescription)

        // Короткий чужий опис лишається собою — трьох крапок нізвідки не з'являється.
        val short = base(listing = afisha, description = "Концерт у МЦКМ")
        assertFalse(short.descriptionTruncated)
        assertEquals("Концерт у МЦКМ", short.displayDescription)
    }

    @Test fun aWithdrawnListingSaysSoAndAButtonWithoutAnAddressIsNotOffered() {
        assertFalse(afisha.isWithdrawn)
        assertTrue(afisha.hasSource)
        assertTrue(afisha.copy(status = ImportStatus.WITHDRAWN).isWithdrawn)
        assertFalse(afisha.copy(canonicalUrl = null).hasSource)
        assertFalse(afisha.copy(canonicalUrl = " ").hasSource)
    }
}
