package app.poruch.data.safety
import app.poruch.data.api.string
import app.poruch.data.api.ApiClient

import app.poruch.domain.*
import io.ktor.http.HttpMethod
import kotlinx.serialization.json.*

/** Скарги, блокування й факти про акаунт. Тонкі виклики: правила живуть у базі. */
class SupabaseSafetyRepository(private val api: ApiClient, private val auth: AuthRepository) : SafetyRepository {
    private fun uid() = auth.session.value?.userId ?: fail(AppError.SessionRequired)

    override suspend fun account(): AccountFacts {
        val row = api.request(
            "/rest/v1/account_facts", token = auth.accessToken(),
            query = mapOf("user_id" to "eq.${uid()}", "select" to "birth_date,status")
        ).jsonArray.firstOrNull()?.jsonObject ?: return AccountFacts()
        return AccountFacts(
            birthDate = row["birth_date"]?.jsonPrimitive?.contentOrNull,
            status = row["status"]?.jsonPrimitive?.contentOrNull ?: AccountStatus.ACTIVE
        )
    }

    override suspend fun declareBirthDate(date: String) {
        rpc("set_birth_date", buildJsonObject { put("p_birth", date) })
    }

    override suspend fun reportEvent(eventId: String, reason: String, details: String?) {
        if (!ReportReason.isReason(reason)) fail(AppError.Rejected)
        rpc("report_event", buildJsonObject { put("p_event_id", eventId); put("p_reason", reason); putDetails(details) })
    }

    override suspend fun reportUser(userId: String, reason: String, details: String?) {
        if (!ReportReason.isReason(reason)) fail(AppError.Rejected)
        rpc("report_user", buildJsonObject { put("p_user_id", userId); put("p_reason", reason); putDetails(details) })
    }

    override suspend fun reportMessage(messageId: String, reason: String, details: String?) {
        if (!ReportReason.isReason(reason)) fail(AppError.Rejected)
        rpc("report_message", buildJsonObject { put("p_message_id", messageId); put("p_reason", reason); putDetails(details) })
    }

    override suspend fun block(userId: String) {
        api.request(
            "/rest/v1/user_blocks", HttpMethod.Post,
            buildJsonObject { put("user_id", uid()); put("blocked_id", userId) }, auth.accessToken(),
            query = mapOf("on_conflict" to "user_id,blocked_id"),
            prefer = "resolution=ignore-duplicates,return=representation"
        )
    }

    override suspend fun unblock(userId: String) {
        api.request(
            "/rest/v1/user_blocks", HttpMethod.Delete, token = auth.accessToken(),
            query = mapOf("user_id" to "eq.${uid()}", "blocked_id" to "eq.$userId")
        )
    }

    /** Два запити замість вкладеного join: той прив'язав би нас до згенерованої назви обмеження. */
    override suspend fun blocked(): List<Attendee> {
        val ids = api.request(
            "/rest/v1/user_blocks", token = auth.accessToken(),
            query = mapOf("user_id" to "eq.${uid()}", "select" to "blocked_id")
        ).jsonArray.map { it.jsonObject.string("blocked_id") }
        if (ids.isEmpty()) return emptyList()
        val names = api.request(
            "/rest/v1/profiles", token = auth.accessToken(),
            query = mapOf("id" to "in.(${ids.joinToString(",")})", "select" to "id,display_name,avatar_url")
        ).jsonArray.associate { row ->
            row.jsonObject.string("id") to Pair(
                row.jsonObject.string("display_name"),
                row.jsonObject["avatar_url"]?.jsonPrimitive?.contentOrNull
            )
        }
        return ids.map { id -> Attendee(id, names[id]?.first.orEmpty(), names[id]?.second) }
    }

    private fun JsonObjectBuilder.putDetails(details: String?) {
        val text = details?.trim().orEmpty()
        if (text.isEmpty()) put("p_details", JsonNull) else put("p_details", text.take(2000))
    }

    private suspend fun rpc(name: String, params: JsonObject) =
        api.request("/rest/v1/rpc/$name", HttpMethod.Post, params, auth.accessToken())
}
