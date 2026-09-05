package app.poruch.domain

import kotlin.test.*

class EventDraftTest {
    private fun draft() = EventDraft("Прогулянка", "Разом відкриваємо місто", "outdoors", "Київ", "Поділ", 50.45, 30.52, "2030-09-05T12:00:00Z", "2030-09-05T14:00:00Z", "Europe/Kyiv", 10)
    @Test fun validDraftHasNoErrors() { assertTrue(draft().validate("2030-09-04T00:00:00Z").isEmpty()) }
    @Test fun pastStartIsRejected() { assertTrue(draft().validate("2031-01-01T00:00:00Z").contains("startsAt")) }
    @Test fun zeroCapacityIsRejected() { assertTrue(draft().copy(capacity=0).validate("2030-01-01T00:00:00Z").contains("capacity")) }
    @Test fun invalidLatitudeIsRejected() { assertTrue(draft().copy(latitude=91.0).validate("2030-01-01T00:00:00Z").contains("location")) }
    @Test fun endBeforeStartIsRejected() { assertTrue(draft().copy(endsAt="2030-09-05T11:00:00Z").validate("2030-01-01T00:00:00Z").contains("endsAt")) }
    @Test fun badTimeZoneIsRejected() { assertTrue(draft().copy(timeZone="Mars/Olympus").validate("2030-01-01T00:00:00Z").contains("timeZone")) }
    @Test fun whitespaceTitleIsRejected() { assertTrue(draft().copy(title="   ").validate("2030-01-01T00:00:00Z").contains("title")) }
}
