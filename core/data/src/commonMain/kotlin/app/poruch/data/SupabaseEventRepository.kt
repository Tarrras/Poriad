package app.poruch.data

import app.poruch.domain.*
import app.poruch.data.cache.PoruchDatabase
import io.ktor.http.HttpMethod
import kotlinx.serialization.json.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString

class SupabaseEventRepository(private val api: ApiClient, private val auth: AuthRepository, private val database: PoruchDatabase): EventRepository {
    private fun cacheKey(query: EventQuery, uid: String? = auth.session.value?.userId) = "${uid ?: "guest"}:$query"
    override suspend fun discover(query: EventQuery): List<Event> {
        val owner = auth.session.value?.userId
        val key = cacheKey(query,owner)
        val response = rpc("events_in_view", buildJsonObject {
            put("p_south",query.south); put("p_west",query.west); put("p_north",query.north); put("p_east",query.east)
            put("p_category",query.category?.let(::JsonPrimitive) ?: JsonNull)
            put("p_from",query.from?.let(::JsonPrimitive) ?: JsonNull); put("p_to",query.to?.let(::JsonPrimitive) ?: JsonNull)
        })
        val rows = api.json.decodeFromJsonElement<List<EventDto>>(response)
        if(owner == auth.session.value?.userId) database.cacheQueries.write(key,api.json.encodeToString(rows))
        return rows.map { it.domain() }
    }
    override fun cached(query: EventQuery): List<Event> = database.cacheQueries.read(cacheKey(query)).executeAsOneOrNull()?.let {
        runCatching { api.json.decodeFromString<List<EventDto>>(it).map { row -> row.domain() } }.getOrDefault(emptyList())
    } ?: emptyList()
    override suspend fun details(id: String): Event? = api.json.decodeFromJsonElement<List<EventDto>>(rpc("event_details", idParams(id))).firstOrNull()?.domain()
    override suspend fun myEvents(): List<Event> = api.json.decodeFromJsonElement<List<EventDto>>(rpc("my_events",buildJsonObject {})).map { it.domain() }
    private fun userId() = auth.session.value?.userId ?: throw AppException(Failure.AUTH,"Увійдіть, щоб продовжити")
    override suspend fun savedIds(): List<String> {
        val uid = userId()
        return api.request("/rest/v1/saved_events", token=auth.accessToken(), query=mapOf("select" to "event_id", "user_id" to "eq.$uid")).jsonArray.map { it.jsonObject.string("event_id") }
    }
    override suspend fun save(id: String) {
        api.request("/rest/v1/saved_events", HttpMethod.Post, buildJsonObject { put("user_id",userId()); put("event_id",id) }, auth.accessToken(), query=mapOf("on_conflict" to "user_id,event_id"), prefer="resolution=ignore-duplicates,return=representation")
    }
    override suspend fun unsave(id: String) {
        api.request("/rest/v1/saved_events", HttpMethod.Delete, token=auth.accessToken(), query=mapOf("user_id" to "eq.${userId()}","event_id" to "eq.$id"))
    }
    override suspend fun create(id: String, draft: EventDraft): String = rpc("create_event",draftParams(id,draft)).jsonPrimitive.content
    override suspend fun update(id: String, draft: EventDraft): String = rpc("update_event",draftParams(id,draft)).jsonPrimitive.content
    override suspend fun join(id: String) { rpc("join_event",idParams(id)) }
    override suspend fun leave(id: String) { rpc("leave_event",idParams(id)) }
    override suspend fun cancel(id: String) { rpc("cancel_event",idParams(id)) }
    @OptIn(kotlin.uuid.ExperimentalUuidApi::class)
    override suspend fun uploadImage(eventId: String, bytes: ByteArray, contentType: String): String {
        val extension=when(contentType) { "image/jpeg" -> "jpg"; "image/png" -> "png"; "image/webp" -> "webp"; else -> throw AppException(Failure.VALIDATION,"Оберіть JPEG, PNG або WebP") }
        if(bytes.isEmpty() || bytes.size>5*1024*1024) throw AppException(Failure.VALIDATION,"Зображення має бути до 5 МБ")
        val uid=userId(); val token=auth.accessToken() ?: throw AppException(Failure.AUTH,"Увійдіть, щоб додати фото")
        return api.upload("$uid/$eventId/${kotlin.uuid.Uuid.random()}.$extension",bytes,contentType,token)
    }
    override fun clearPrivateCache() { database.cacheQueries.clearAll() }
    private suspend fun rpc(name: String, params: JsonObject) = api.request("/rest/v1/rpc/$name", HttpMethod.Post, params, auth.accessToken())
    private fun idParams(id: String) = buildJsonObject { put("p_event_id",id) }
    private fun draftParams(id: String, d: EventDraft) = buildJsonObject {
        put("p_id",id); put("p_title",d.title.trim()); put("p_description",d.description.trim()); put("p_category",d.category)
        put("p_city",d.city); put("p_address",d.address); put("p_latitude",d.latitude); put("p_longitude",d.longitude)
        put("p_starts_at",d.startsAt); put("p_ends_at",d.endsAt); put("p_time_zone",d.timeZone); put("p_capacity",d.capacity)
        put("p_image_url",d.imageUrl?.let(::JsonPrimitive) ?: JsonNull)
    }
}
