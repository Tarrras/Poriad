package app.poruch.domain

import kotlin.test.*

class EventLinksTest {
    private val id = "a1000000-0000-4000-8000-000000000005"

    @Test fun ownLinkRoundTrips() = assertEquals(id, EventLinks.eventId(EventLinks.url(id)))

    @Test fun acceptsWebAndSchemeForms() {
        assertEquals(id, EventLinks.eventId("https://www.poriad.app/e/$id/?utm_source=telegram"))
        assertEquals(id, EventLinks.eventId("poriad://event/${id.uppercase()}"))
        assertEquals(id, EventLinks.eventId("poriad-dev://event/$id#top"))
    }

    @Test fun rejectsEverythingElse() {
        assertNull(EventLinks.eventId("poriad://auth/callback#access_token=x"))
        assertNull(EventLinks.eventId("https://poriad.app/privacy.html"))
        assertNull(EventLinks.eventId("https://evil.example/e/$id"))
        assertNull(EventLinks.eventId("https://poriad.app/e/not-an-id"))
    }
}
