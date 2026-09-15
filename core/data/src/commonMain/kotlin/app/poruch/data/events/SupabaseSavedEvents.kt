package app.poruch.data.events

import app.poruch.data.api.ApiClient
import app.poruch.data.api.string
import app.poruch.domain.*
import io.ktor.http.HttpMethod
import kotlinx.serialization.json.*

/** Закладки ходять у таблицю напряму, а не через RPC: єдине правило «рядок належить власнику» вже в RLS. */
internal class SupabaseSavedEvents(
    private val api: ApiClient,
    private val auth: AuthRepository
) : SavedEvents {

    private fun userId() = auth.session.value?.userId ?: fail(AppError.SessionRequired)

    override suspend fun savedIds(): List<String> =
        api.request(
            TABLE, token = auth.accessToken(),
            query = mapOf("select" to "event_id", "user_id" to "eq.${userId()}")
        ).jsonArray.map { it.jsonObject.string("event_id") }

    override suspend fun save(id: String) {
        api.request(
            TABLE, HttpMethod.Post,
            buildJsonObject { put("user_id", userId()); put("event_id", id) },
            auth.accessToken(),
            query = mapOf("on_conflict" to "user_id,event_id"),
            // Повторне збереження — не помилка.
            prefer = "resolution=ignore-duplicates,return=representation"
        )
    }

    override suspend fun unsave(id: String) {
        api.request(
            TABLE, HttpMethod.Delete, token = auth.accessToken(),
            query = mapOf("user_id" to "eq.${userId()}", "event_id" to "eq.$id")
        )
    }

    private companion object {
        const val TABLE = "/rest/v1/saved_events"
    }
}
