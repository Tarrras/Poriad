package app.poruch.data.events

import app.poruch.domain.AppFailure
import app.poruch.domain.Attendee
import app.poruch.domain.EventRequests
import app.poruch.domain.JoinRequest
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Запити на участь з боку організатора. Окремо від [SupabaseEventParticipation], бо інші права. */
internal class SupabaseEventRequests(private val rpc: EventRpc) : EventRequests {

    override suspend fun joinRequests(id: String): List<Attendee> =
        rpc.people("event_requests", buildJsonObject { put("p_event_id", id); put("p_limit", QUEUE_LIMIT) })

    /** Сервер без міграції `20260915223806` не має цієї функції: тоді стрічка порожня, а не зламана. */
    override suspend fun pendingRequests(): List<JoinRequest> = try {
        rpc.json.decodeFromJsonElement(
            kotlinx.serialization.builtins.ListSerializer(JoinRequestDto.serializer()),
            rpc.read("my_join_requests", buildJsonObject { put("p_limit", FEED_LIMIT) })
        ).map { it.domain() }
    } catch (e: CancellationException) {
        throw e
    } catch (e: AppFailure) {
        if (e.isMissingFunction()) emptyList() else throw e
    }

    override suspend fun approveMember(eventId: String, userId: String) {
        rpc.call("approve_member", memberParams(eventId, userId))
    }

    override suspend fun declineMember(eventId: String, userId: String) {
        rpc.call("decline_member", memberParams(eventId, userId))
    }

    private fun memberParams(eventId: String, userId: String) =
        buildJsonObject { put("p_event_id", eventId); put("p_user_id", userId) }

    private companion object {
        /** Скільки запитів показуємо за раз. */
        const val QUEUE_LIMIT = 50

        /** Скільки запитів тягне стрічка головної. Більше — це вже не «відповісти», а модерація. */
        const val FEED_LIMIT = 100
    }
}
