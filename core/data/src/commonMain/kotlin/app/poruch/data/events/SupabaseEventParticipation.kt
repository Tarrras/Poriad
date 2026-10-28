package app.poruch.data.events

import app.poruch.domain.AuthRepository
import app.poruch.domain.CompanyMatch
import app.poruch.domain.EventParticipation
import app.poruch.domain.EventRating
import app.poruch.domain.RatingTag
import kotlinx.serialization.json.*

/** Участь і черга. Перевірок тут нема навмисно: усі на сервері в `assert_can_join`. */
internal class SupabaseEventParticipation(
    private val rpc: EventRpc,
    private val auth: AuthRepository? = null,
    private val mine: MineCache? = null
) : EventParticipation {
    override suspend fun join(id: String) { rpc.call("join_event", rpc.eventParams(id)) }
    override suspend fun leave(id: String) { rpc.call("leave_event", rpc.eventParams(id)) }

    override suspend fun waitlistIds(): List<String> {
        val owner = auth?.session?.value?.userId
        val response = rpc.read("my_waitlist")
        mine?.write(MineCache.QUEUED, owner, response.toString())
        return response.jsonArray.map { it.jsonPrimitive.content }
    }

    override suspend fun joinWaitlist(id: String) { rpc.call("join_waitlist", rpc.eventParams(id)) }
    override suspend fun leaveWaitlist(id: String) { rpc.call("leave_waitlist", rpc.eventParams(id)) }

    override suspend fun setCompanyIntent(id: String, on: Boolean): Int =
        rpc.call("set_company_intent", buildJsonObject { put("p_event_id", id); put("p_on", on) }).jsonPrimitive.int

    override suspend fun companyYes(id: String, userId: String): CompanyMatch {
        val row = rpc.call("company_yes", buildJsonObject { put("p_event_id", id); put("p_user_id", userId) }).jsonObject
        return CompanyMatch(row["matched"]?.jsonPrimitive?.boolean == true, row["companion_id"]?.jsonPrimitive?.contentOrNull)
    }

    override suspend fun invite(id: String): String = rpc.call("create_invite", rpc.eventParams(id)).jsonPrimitive.content

    override suspend fun ratings(id: String): List<EventRating> =
        rpc.read("event_ratings", rpc.eventParams(id)).jsonArray.map {
            val row = it.jsonObject
            EventRating(row.getValue("score").jsonPrimitive.int, row["comment"]?.jsonPrimitive?.contentOrNull,
                row.getValue("created_at").jsonPrimitive.content, row["mine"]?.jsonPrimitive?.boolean == true,
                (row["tags"] as? JsonArray).orEmpty().mapNotNull { tag -> RatingTag.fromKey(tag.jsonPrimitive.content) })
        }

    override suspend fun myRatings(): Map<String, Int> =
        rpc.read("my_ratings").jsonArray.associate {
            val row = it.jsonObject
            row.getValue("event_id").jsonPrimitive.content to row.getValue("score").jsonPrimitive.int
        }

    override suspend fun rate(id: String, score: Int, comment: String?, tags: List<RatingTag>) {
        rpc.call("rate_event", buildJsonObject {
            put("p_event_id", id); put("p_score", score); put("p_comment", comment)
            putJsonArray("p_tags") { tags.forEach { add(it.key) } }
        })
    }
}
