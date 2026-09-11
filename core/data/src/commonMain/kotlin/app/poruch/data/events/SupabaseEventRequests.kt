package app.poruch.data.events

import app.poruch.domain.Attendee
import app.poruch.domain.EventRequests
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Двері організатора. Окремо від [SupabaseEventParticipation], бо це протилежний бік тих самих
 * дверей: там просять увійти, тут вирішують. І права різні — сервер віддає ці функції лише
 * організаторові події.
 */
internal class SupabaseEventRequests(private val rpc: EventRpc) : EventRequests {

    override suspend fun joinRequests(id: String): List<Attendee> =
        rpc.people("event_requests", buildJsonObject { put("p_event_id", id); put("p_limit", QUEUE_LIMIT) })

    override suspend fun approveMember(eventId: String, userId: String) {
        rpc.call("approve_member", memberParams(eventId, userId))
    }

    override suspend fun declineMember(eventId: String, userId: String) {
        rpc.call("decline_member", memberParams(eventId, userId))
    }

    private fun memberParams(eventId: String, userId: String) =
        buildJsonObject { put("p_event_id", eventId); put("p_user_id", userId) }

    private companion object {
        /** Скільки запитів показуємо за раз: більше за це — вже не черга, а окремий екран. */
        const val QUEUE_LIMIT = 50
    }
}
