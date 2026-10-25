package app.poruch.data.events

import app.poruch.data.api.ApiClient
import app.poruch.data.api.ImageStorage
import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.*

/**
 * Єдиний вхід до подій ззовні модуля. Реалізації `internal`, назовні видно лише доменні
 * інтерфейси, тож модуль можна перекроювати без змін у графі залежностей.
 */
class EventData(
    api: ApiClient,
    auth: AuthRepository,
    database: PoruchDatabase,
    storage: ImageStorage
) {
    private val rpc = EventRpc(api, auth)
    private val mine = MineCache(database, rpc.json, auth)

    val discovery: EventDiscovery = SupabaseEventDiscovery(rpc, auth, database, mine)
    val saved: SavedEvents = SupabaseSavedEvents(api, auth, mine)
    val authoring: EventAuthoring = SupabaseEventAuthoring(rpc, auth, storage)
    val participation: EventParticipation = SupabaseEventParticipation(rpc, auth, mine)
    val requests: EventRequests = SupabaseEventRequests(rpc)
    val chat: EventChat = SupabaseEventChat(rpc)
    val push: PushTokens = SupabasePushTokens(rpc)
    val follows: Follows = SupabaseFollows(rpc)
}
