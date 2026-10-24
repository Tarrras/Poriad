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

    @Test fun readsInviteTokenFromBothForms() {
        val token = "AbCdEfGhIjKlMnOpQrSt_-"
        assertEquals(token, EventLinks.invite(EventLinks.url(id, token)))
        assertEquals(id, EventLinks.eventId(EventLinks.url(id, token)))
        assertEquals(token, EventLinks.invite("poriad-dev://event/$id?by=$token"))
        assertEquals(token, EventLinks.invite("https://poriad.app/e/$id/?utm_source=telegram&by=$token#top"))
        assertEquals(id, EventLinks.eventId("poriad://event/$id?utm_source=x&by=$token"))
    }

    @Test fun ignoresMissingOrForeignTokens() {
        assertNull(EventLinks.invite(EventLinks.url(id)))
        assertNull(EventLinks.invite("https://poriad.app/e/$id?by=short"))
        assertNull(EventLinks.invite("https://poriad.app/e/$id?by=AbCdEfGhIjKlMnOpQrSt_-x"))
        assertNull(EventLinks.invite("https://poriad.app/e/$id?nearby=AbCdEfGhIjKlMnOpQrSt_-"))
        assertNull(EventLinks.invite("https://poriad.app/e/$id#by=AbCdEfGhIjKlMnOpQrSt_-"))
        assertNull(EventLinks.invite("https://evil.example/e/$id?by=AbCdEfGhIjKlMnOpQrSt_-"))
        // Зіпсований токен не ламає саме посилання: подія відкривається звичайною.
        assertEquals(id, EventLinks.eventId("https://poriad.app/e/$id?by=short"))
    }
}
