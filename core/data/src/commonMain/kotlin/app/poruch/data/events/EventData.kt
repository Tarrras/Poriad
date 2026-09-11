package app.poruch.data.events

import app.poruch.data.api.ApiClient
import app.poruch.data.api.ImageStorage
import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.*

/**
 * Єдиний вхід до подій ззовні модуля.
 *
 * П'ять реалізацій за цією межею лишаються `internal`: назовні видно тільки доменні грані. Це не
 * формальність — так модуль може розділити клас надвоє, склеїти два в один або замінити RPC на
 * щось інше, не питаючи дозволу в графа залежностей.
 *
 * Сам об'єкт нічого не робить: він лише зв'язує п'ять реалізацій зі спільним каналом [EventRpc].
 * Хто просить `EventDiscovery`, той і отримує рівно `EventDiscovery`.
 */
class EventData(
    api: ApiClient,
    auth: AuthRepository,
    database: PoruchDatabase,
    storage: ImageStorage
) {
    private val rpc = EventRpc(api, auth)

    val discovery: EventDiscovery = SupabaseEventDiscovery(rpc, auth, database)
    val saved: SavedEvents = SupabaseSavedEvents(api, auth)
    val authoring: EventAuthoring = SupabaseEventAuthoring(rpc, auth, storage)
    val participation: EventParticipation = SupabaseEventParticipation(rpc)
    val requests: EventRequests = SupabaseEventRequests(rpc)
}
