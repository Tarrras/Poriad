package app.poruch.data.events

import app.poruch.domain.EventParticipation
import app.poruch.domain.EventRating
import kotlinx.serialization.json.*

/** Участь і черга. Перевірок тут нема навмисно: усі на сервері в `assert_can_join`. */
internal class SupabaseEventParticipation(private val rpc: EventRpc) : EventParticipation {
    override suspend fun join(id: String) { rpc.call("join_event", rpc.eventParams(id)) }
    override suspend fun leave(id: String) { rpc.call("leave_event", rpc.eventParams(id)) }

    override suspend fun waitlistIds(): List<String> =
        rpc.read("my_waitlist").jsonArray.map { it.jsonPrimitive.content }

    override suspend fun joinWaitlist(id: String) { rpc.call("join_waitlist", rpc.eventParams(id)) }
    override suspend fun leaveWaitlist(id: String) { rpc.call("leave_waitlist", rpc.eventParams(id)) }

    override suspend fun ratings(id: String): List<EventRating> =
        rpc.read("event_ratings", rpc.eventParams(id)).jsonArray.map {
            val row = it.jsonObject
            EventRating(row.getValue("score").jsonPrimitive.int, row["comment"]?.jsonPrimitive?.contentOrNull,
                row.getValue("created_at").jsonPrimitive.content, row["mine"]?.jsonPrimitive?.boolean == true)
        }

    override suspend fun rate(id: String, score: Int, comment: String?) {
        rpc.call("rate_event", buildJsonObject { put("p_event_id", id); put("p_score", score); put("p_comment", comment) })
    }
}
