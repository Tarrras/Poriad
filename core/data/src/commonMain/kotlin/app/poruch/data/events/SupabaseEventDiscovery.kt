package app.poruch.data.events

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.*
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*

/**
 * Читання подій: єдина частина, доступна без акаунта, і єдина з кешем.
 *
 * [compute] — де розбираємо індекс і пишемо кеш у SQLite. Раніше це йшло на головному потоці
 * і пропускало кадри. `Default`, а не `IO`, бо `Dispatchers.IO` немає в `commonMain`.
 */
internal class SupabaseEventDiscovery(
    private val rpc: EventRpc,
    private val auth: AuthRepository,
    database: PoruchDatabase,
    private val compute: CoroutineDispatcher = Dispatchers.Default
) : EventDiscovery {

    private val cache = EventCache(database, rpc.json)

    /**
     * Чи вміє сервер віддавати індекс. Null — ще не питали. Без міграції `20260911070031`
     * `discover_events` відповідає `PGRST202`, і далі йде старий шлях.
     */
    private var hasIndexRpc: Boolean? = null

    override suspend fun discover(query: EventQuery): DiscoveryPage {
        val owner = auth.session.value?.userId
        if (hasIndexRpc != false) {
            val response = runCatching { rpc.read("discover_events", query.indexParams()) }
                .onSuccess { hasIndexRpc = true }
                .getOrElse { failure ->
                    if (!failure.isMissingFunction()) throw failure
                    PoruchLog.w("discovery") { "server has no discover_events, falling back to search_events_in_view" }
                    hasIndexRpc = false
                    null
                }
            if (response != null) return withContext(compute) {
                val text = response.toString()
                val page = rpc.json.decodeFromJsonElement<DiscoveryEnvelope>(response)
                // Акаунт міг змінитися, поки запит був у дорозі: тоді відповідь не пишемо.
                if (owner == auth.session.value?.userId) cache.write(cache.key(query, owner), text)
                page.domain()
            }
        }
        return legacyDiscover(query)
    }

    /** Старий шлях: одна відповідь на все, стеля 300 рядків, індекс будується з карток. */
    private suspend fun legacyDiscover(query: EventQuery): DiscoveryPage {
        val response = rpc.read("search_events_in_view", query.legacyParams())
        return withContext(compute) {
            val cards = rpc.json.decodeFromJsonElement<List<EventDto>>(response).map { it.domain() }
            // Кеш не пишемо: тримати другий формат заради бази без міграції не варто.
            DiscoveryPage(cards.map { it.asIndexEntry() }, cards.size, false, cards)
        }
    }

    override fun cached(query: EventQuery): DiscoveryPage =
        cache.read(cache.key(query, auth.session.value?.userId))?.domain() ?: DiscoveryPage.Empty

    override suspend fun cards(ids: List<String>): List<Event> {
        if (ids.isEmpty()) return emptyList()
        val batches = ids.distinct().chunked(DiscoveryRules.CARD_BATCH)
        val collected = mutableListOf<Event>()
        for (batch in batches) {
            val response = rpc.read("event_cards_by_ids", buildJsonObject {
                put("p_ids", JsonArray(batch.map(::JsonPrimitive)))
            })
            collected += withContext(compute) {
                rpc.json.decodeFromJsonElement<List<EventDto>>(response).map { it.domain() }
            }
        }
        PoruchLog.d("discovery") { "${collected.size} cards for ${ids.size} ids in ${batches.size} request(s)" }
        return collected
    }

    override suspend fun details(id: String): Event? =
        rpc.events("event_details", rpc.eventParams(id)).firstOrNull()

    override suspend fun myEvents(): List<Event> = rpc.events("my_events")

    override suspend fun attendees(id: String): List<Attendee> =
        rpc.people("event_attendees", buildJsonObject { put("p_event_id", id); put("p_limit", ROSTER_LIMIT) })

    /**
     * Сервер без міграції місць відповідає `PGRST202`: тоді місць просто нема, а пошук подій
     * працює як раніше. Порожній текст сервер віддав би `[]` і сам, але запит не вартий того.
     */
    override suspend fun searchPlaces(text: String, city: String?, bounds: EventQuery?): List<Place> {
        val trimmed = text.trim().take(DiscoveryRules.SEARCH_TEXT_LIMIT)
        if (trimmed.isEmpty()) return emptyList()
        val response = runCatching {
            rpc.read("search_places", buildJsonObject {
                put("p_text", trimmed)
                put("p_city", city?.let(::JsonPrimitive) ?: JsonNull)
                if (bounds != null) putBounds(bounds)
                put("p_limit", DiscoveryRules.PLACES_LIMIT)
            })
        }.getOrElse { failure ->
            if (!failure.isMissingFunction()) throw failure
            PoruchLog.w("discovery") { "server has no search_places" }
            return emptyList()
        }
        return withContext(compute) { rpc.json.decodeFromJsonElement<List<PlaceDto>>(response).map { it.domain() } }
    }

    override suspend fun placeEvents(placeId: String): List<Event> {
        val response = rpc.read("place_events", buildJsonObject {
            put("p_place_id", placeId)
            put("p_limit", DiscoveryRules.PLACE_EVENTS_LIMIT)
        })
        return withContext(compute) {
            rpc.json.decodeFromJsonElement<List<EventDto>>(response).map { it.domain() }
        }.also { PoruchLog.d("discovery") { "${it.size} events at place ${placeId.shortId()}" } }
    }

    override fun clearPrivateCache() { cache.clearPrivate() }

    private fun EventQuery.indexParams() = buildJsonObject {
        putBounds(this@indexParams)
        putFilters(this@indexParams)
        put("p_limit", DiscoveryRules.INDEX_CAP)
        put("p_cards", DiscoveryRules.FIRST_CARDS)
    }

    private fun EventQuery.legacyParams() = buildJsonObject {
        putBounds(this@legacyParams)
        putFilters(this@legacyParams)
    }

    private fun JsonObjectBuilder.putBounds(query: EventQuery) {
        put("p_south", query.south); put("p_west", query.west)
        put("p_north", query.north); put("p_east", query.east)
    }

    private fun JsonObjectBuilder.putFilters(query: EventQuery) {
        put("p_category", query.category?.let(::JsonPrimitive) ?: JsonNull)
        put("p_text", query.text?.let(::JsonPrimitive) ?: JsonNull)
        put("p_available", query.available)
        put("p_from", query.from?.let(::JsonPrimitive) ?: JsonNull)
        put("p_to", query.to?.let(::JsonPrimitive) ?: JsonNull)
    }

    private companion object {
        /** Скільки учасників показує картка. */
        const val ROSTER_LIMIT = 24
    }
}
