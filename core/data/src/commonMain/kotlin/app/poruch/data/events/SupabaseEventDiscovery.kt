package app.poruch.data.events

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.*
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*

/**
 * Читання подій. Єдина грань, яку має сенс питати без акаунта, — і єдина, що тримає кеш.
 *
 * [compute] — де відбувається все, що після відповіді: розбір індексу, кодування в кеш і запис у
 * SQLite. Досі це виконувалось там, звідки прийшов виклик, а приходив він із головного потоку —
 * 618 мс на нього, `Skipped 40 frames` і кадр на 1065 мс. Ktor чекає сокет поза потоком сам; сюди
 * ми виносимо процесор і один запис на диск.
 *
 * Саме `Default`, а не `IO`: у kotlinx-coroutines 1.10.2 `Dispatchers.IO` не існує в `commonMain`.
 */
internal class SupabaseEventDiscovery(
    private val rpc: EventRpc,
    private val auth: AuthRepository,
    database: PoruchDatabase,
    private val compute: CoroutineDispatcher = Dispatchers.Default
) : EventDiscovery {

    private val cache = EventCache(database, rpc.json)

    /**
     * Чи вміє цей сервер віддавати індекс. `null` — ще не питали.
     *
     * Збірка може дивитись на сервер без міграції `20260911070031`, і тоді `discover_events`
     * відповість `PGRST202`. Питати про це щоразу було б дивно, тож відповідь запамʼятовується
     * один раз, а далі йде старий шлях — вужчий, але робочий.
     */
    private var hasIndexRpc: Boolean? = null

    override suspend fun discover(query: EventQuery): DiscoveryPage {
        val owner = auth.session.value?.userId
        if (hasIndexRpc != false) {
            val response = runCatching { rpc.call("discover_events", query.indexParams()) }
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
                // Особа могла змінитися, поки запит був у дорозі: тоді ця відповідь належить уже
                // нікому, і записувати її під новим власником не можна.
                if (owner == auth.session.value?.userId) cache.write(cache.key(query, owner), text)
                page.domain()
            }
        }
        return legacyDiscover(query)
    }

    /**
     * Старий шлях: одна відповідь на все, зі стелею в 300 рядків і без лічильника.
     *
     * Індекс тут будується з тих самих карток — це єдине, що сервер уміє сказати. Мапа від цього
     * не ламається, просто показує стільки, скільки старий сервер дав.
     */
    private suspend fun legacyDiscover(query: EventQuery): DiscoveryPage {
        val response = rpc.call("search_events_in_view", query.legacyParams())
        return withContext(compute) {
            val cards = rpc.json.decodeFromJsonElement<List<EventDto>>(response).map { it.domain() }
            // Кеш тут навмисно не пишемо. Він зберігає ту саму форму, що приходить із сервера, а
            // цей шлях існує лише для бази без міграції — випадку, якого в жодному живому проєкті
            // немає. Писати заради нього другий формат означало б тримати два вічно.
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
            val response = rpc.call("event_cards_by_ids", buildJsonObject {
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

    /** PostgREST відповідає цим кодом, коли функції з такою сигнатурою на сервері немає. */
    private fun Throwable.isMissingFunction() = (this as? AppFailure)?.serverCode == "PGRST202"

    private companion object {
        /** Скільки облич показує картка: більше за це в неї не поміщається. */
        const val ROSTER_LIMIT = 24
    }
}
