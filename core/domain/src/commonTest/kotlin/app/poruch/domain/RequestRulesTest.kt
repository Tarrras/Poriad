package app.poruch.domain

import kotlin.test.*

/** Про що дзвонити: лише нове, згруповане за подією, лише з назвою, лише за згодою. */
class RequestRulesTest {
    private fun event(id: String) = Event(
        id = id, title = "Подія $id", description = "", category = "games", city = "Київ",
        address = "Поділ", startsAt = "2026-09-20T18:00:00Z", endsAt = "2026-09-20T20:00:00Z",
        timeZone = "Europe/Kyiv", status = EventStatus.PUBLISHED, latitude = 50.45, longitude = 30.52,
        gathering = Gathering("me", "", 10, 1, false)
    )
    private fun request(eventId: String, userId: String) = JoinRequest(eventId, userId, "Гість", null, "2026-09-16T10:00:00Z")

    @Test fun freshRequestsAreGroupedPerEvent() {
        val alerts = RequestRules.alerts(
            listOf(request("a", "u1"), request("a", "u2"), request("b", "u3")),
            seen = emptySet(), events = listOf(event("a"), event("b")), enabled = true
        )
        assertEquals(listOf(RequestAlert("a", "Подія a", 2), RequestAlert("b", "Подія b", 1)), alerts)
    }

    @Test fun seenRequestsDoNotRingTwice() {
        val alerts = RequestRules.alerts(
            listOf(request("a", "u1"), request("a", "u2")),
            seen = setOf("a:u1:2026-09-16T10:00:00Z"), events = listOf(event("a")), enabled = true
        )
        assertEquals(listOf(RequestAlert("a", "Подія a", 1)), alerts)
    }

    @Test fun unknownEventsAndOptOutsGetNothing() {
        val requests = listOf(request("ghost", "u1"))
        assertTrue(RequestRules.alerts(requests, emptySet(), emptyList(), enabled = true).isEmpty())
        assertTrue(RequestRules.alerts(requests, emptySet(), listOf(event("ghost")), enabled = false).isEmpty())
    }

    @Test fun pendingCountsPerEvent() {
        val counts = RequestRules.pendingByEvent(listOf(request("a", "u1"), request("a", "u2"), request("b", "u3")))
        assertEquals(mapOf("a" to 2, "b" to 1), counts)
    }
}

/** Злиття хвоста чату: без дублів, за часом, потім за id. */
class ChatRulesTest {
    private fun message(id: String, at: String) = ChatMessage(id, "ev", "u", "U", null, "…", at)

    @Test fun mergeDeduplicatesAndOrders() {
        val known = listOf(message("a", "2026-09-16T10:00:00Z"), message("b", "2026-09-16T10:01:00Z"))
        val fresh = listOf(message("b", "2026-09-16T10:01:00Z"), message("c", "2026-09-16T10:00:30Z"))
        assertEquals(listOf("a", "c", "b"), ChatRules.merge(known, fresh).map { it.id })
        assertSame(known, ChatRules.merge(known, emptyList()))
    }

    @Test fun bodyLimits() {
        assertTrue(ChatRules.isBody("  привіт  "))
        assertFalse(ChatRules.isBody("   "))
        assertFalse(ChatRules.isBody("a".repeat(ChatRules.MAX_BODY + 1)))
    }
}

/** Про які чати дзвонити: не бачені, не відкритий, лише за згодою. */
class ChatAlertRulesTest {
    private fun unread(eventId: String, last: String) = ChatUnread(eventId, "Подія $eventId", 3, last, "Оля", "a".repeat(200), "2026-09-16T10:00:00Z")

    @Test fun unseenChatsRingWithATrimmedPreview() {
        val alerts = ChatAlertRules.alerts(listOf(unread("a", "m1"), unread("b", "m2")), seen = setOf("m2"), openEventId = null, enabled = true)
        assertEquals(listOf("a"), alerts.map { it.eventId })
        assertEquals(ChatAlertRules.PREVIEW, alerts.single().preview.length)
        assertEquals(3, alerts.single().count)
    }

    @Test fun theOpenChatAndOptOutsStaySilent() {
        val all = listOf(unread("a", "m1"))
        assertTrue(ChatAlertRules.alerts(all, emptySet(), openEventId = "a", enabled = true).isEmpty())
        assertTrue(ChatAlertRules.alerts(all, emptySet(), openEventId = null, enabled = false).isEmpty())
    }
}
