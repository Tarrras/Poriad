package app.poruch.data.events

import app.poruch.data.api.ApiClient
import app.poruch.data.api.string
import app.poruch.domain.*
import io.ktor.http.HttpMethod
import kotlinx.serialization.json.*

/** Закладки ходять у таблицю напряму, а не через RPC: єдине правило «рядок належить власнику» вже в RLS. */
internal class SupabaseSavedEvents(
    private val api: ApiClient,
    private val auth: AuthRepository,
    private val mine: MineCache? = null
) : SavedEvents {

    private fun userId() = auth.session.value?.userId ?: fail(AppError.SessionRequired)

    override suspend fun savedIds(): List<String> {
        val owner = userId()
        return api.request(
            TABLE, token = auth.accessToken(),
            query = mapOf("select" to "event_id", "user_id" to "eq.$owner")
        ).jsonArray.map { it.jsonObject.string("event_id") }
            .also { ids -> mine?.write(MineCache.SAVED, owner, JsonArray(ids.map(::JsonPrimitive)).toString()) }
    }

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

    /** Один запит масивом: RLS перевіряє кожен рядок, а наявні пропускає `ignore-duplicates`. */
    override suspend fun saveAll(ids: List<String>) {
        if (ids.isEmpty()) return
        val uid = userId()
        api.request(
            TABLE, HttpMethod.Post,
            JsonArray(ids.map { id -> buildJsonObject { put("user_id", uid); put("event_id", id) } }),
            auth.accessToken(),
            query = mapOf("on_conflict" to "user_id,event_id"),
            prefer = "resolution=ignore-duplicates,return=minimal"
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
