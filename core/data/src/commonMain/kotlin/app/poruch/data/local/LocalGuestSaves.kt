package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.GuestSavedStore
import kotlinx.serialization.json.*

/**
 * Закладки гостя під префіксом `device:`: без нього `clearPrivateDevice` при вході стер би їх ще до перенесення в
 * акаунт (docs/guest-saves.md).
 */
class LocalGuestSaves(private val database: PoruchDatabase) : GuestSavedStore {
    override fun ids(): List<String> {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return emptyList()
        return runCatching { Json.parseToJsonElement(stored).jsonArray.map { it.jsonPrimitive.content } }.getOrDefault(emptyList())
    }

    override fun write(ids: List<String>) {
        database.cacheQueries.writeDevice(KEY, JsonArray(ids.map(::JsonPrimitive)).toString())
    }

    private companion object {
        const val KEY = "device:saved"
    }
}
