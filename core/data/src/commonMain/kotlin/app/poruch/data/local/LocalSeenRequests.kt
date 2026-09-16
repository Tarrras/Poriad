package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.AuthRepository
import app.poruch.domain.RequestRules
import app.poruch.domain.SeenRequestStore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive

/**
 * Ключі запитів, про які вже дзвонили. Під ключем акаунта і без префікса `device:`, тож вихід
 * з акаунта прибирає їх разом з рештою приватного стану, а інший акаунт на тому ж телефоні
 * починає з чистого. Тримаємо останні [RequestRules.SEEN_CAPACITY]: старіші запити або
 * отримали відповідь, або подія минула.
 */
class LocalSeenRequests(
    private val database: PoruchDatabase,
    private val auth: AuthRepository,
    /** Простір ключів: запити й повідомлення тримають окремі списки. */
    private val namespace: String = "requests-seen"
) : SeenRequestStore {
    private fun key() = "$namespace:${auth.session.value?.userId ?: "guest"}"

    override fun seen(): Set<String> {
        val raw = database.cacheQueries.readDevice(key()).executeAsOneOrNull() ?: return emptySet()
        return runCatching { Json.parseToJsonElement(raw).jsonArray.map { it.jsonPrimitive.content } }
            .getOrDefault(emptyList()).toSet()
    }

    override fun markSeen(keys: Set<String>) {
        if (keys.isEmpty()) return
        // Нові в кінець: обрізаємо з голови, де найстаріше.
        val merged = (seen() - keys).toList() + keys
        val kept = merged.takeLast(RequestRules.SEEN_CAPACITY)
        database.cacheQueries.writeDevice(key(), JsonArray(kept.map(::JsonPrimitive)).toString())
    }
}
