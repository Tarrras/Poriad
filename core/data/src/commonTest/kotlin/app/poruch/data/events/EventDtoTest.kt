package app.poruch.data.events

import app.poruch.domain.EventStatus
import app.poruch.domain.ImportStatus
import app.poruch.domain.Membership
import kotlinx.serialization.json.Json
import kotlin.test.*

/** Плоский рядок `event_result` розпадається на кімнату або оголошення тут, і далі `origin` ніхто не бачить. */
class EventDtoTest {
    private val json = Json { ignoreUnknownKeys = true; isLenient = false }

    private fun row(vararg extra: Pair<String, String>): String {
        val base = linkedMapOf(
            "id" to "\"e1\"", "title" to "\"Подія\"", "description" to "\"опис\"",
            "category" to "\"music\"", "city" to "\"Київ\"", "address" to "\"Поділ\"",
            "starts_at" to "\"2030-09-06T19:00:00Z\"", "ends_at" to "\"2030-09-06T22:00:00Z\"",
            "time_zone" to "\"Europe/Kyiv\"", "status" to "\"published\"",
            "latitude" to "50.45", "longitude" to "30.52"
        )
        extra.forEach { (k, v) -> base[k] = v }
        return base.entries.joinToString(",", "{", "}") { "\"${it.key}\":${it.value}" }
    }

    private fun parse(vararg extra: Pair<String, String>) =
        json.decodeFromString<EventDto>(row(*extra)).domain()

    @Test fun anImportedRowBecomesAListingAndNothingElse() {
        val event = parse(
            "origin" to "\"import\"", "organizer_id" to "null", "organizer_name" to "\"Karabas\"",
            "source_name" to "\"Karabas\"", "canonical_url" to "\"https://kyiv.karabas.com/e/1\"",
            "import_status" to "\"live\"", "price_min" to "350", "is_free" to "false",
            // Старий сервер віддає одиницю: до екранів вона долетіти не має.
            "capacity" to "1", "attendee_count" to "0"
        )
        assertNull(event.gathering)
        assertFalse(event.isCommunity)
        assertEquals("Karabas", event.listing?.sourceName)
        assertEquals("https://kyiv.karabas.com/e/1", event.listing?.canonicalUrl)
        assertEquals(350.0, event.listing?.priceMin)
        assertEquals(ImportStatus.LIVE, event.listing?.status)
    }

    @Test fun aCommunityRowBecomesARoomAndNothingElse() {
        val event = parse(
            "organizer_id" to "\"u1\"", "organizer_name" to "\"Оля\"", "capacity" to "10",
            "attendee_count" to "3", "joined" to "true", "membership" to "\"approved\"",
            "min_age" to "21", "approval_required" to "true"
        )
        assertNull(event.listing)
        assertEquals("u1", event.organizerId)
        assertEquals(7, event.gathering?.seatsLeft)
        assertTrue(event.gathering!!.joined)
        assertEquals(Membership.APPROVED, event.gathering!!.membership)
        assertTrue(event.gathering!!.hasAgeLimit)
        assertTrue(event.gathering!!.approvalRequired)
        assertEquals(EventStatus.PUBLISHED, event.status)
    }

    /** Афіша без місткості, як віддає сервер після 20260907150000. */
    @Test fun aListingWithoutCapacityParsesCleanly() {
        val event = parse("origin" to "\"import\"", "capacity" to "null", "source_name" to "\"concert.ua\"")
        assertNull(event.gathering)
        assertEquals("concert.ua", event.listing?.sourceName)
    }

    /** Зіпсований спільнотний рядок стає подією без дій, а список не падає. */
    @Test fun abrokenCommunityRowYieldsAnEventWithNeitherFace() {
        val event = parse("organizer_id" to "\"u1\"", "capacity" to "null")
        assertNull(event.gathering)
        assertNull(event.listing)
        assertNull(event.publisherName)
    }

    /** База без міграції імпорту не віддає `origin`: усе там спільнотне. */
    @Test fun anOlderServerWithoutOriginStillReadsAsCommunity() {
        val event = parse("organizer_id" to "\"u1\"", "organizer_name" to "\"Оля\"", "capacity" to "10")
        assertNotNull(event.gathering)
        assertNull(event.listing)
    }
}
