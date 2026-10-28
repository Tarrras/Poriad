package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.GuestArtist
import app.poruch.domain.GuestArtistStore
import kotlinx.serialization.json.*

/**
 * Артисти гостя під префіксом `device:`: як закладки гостя, вони переживають `clearPrivateDevice` при вході й
 * переїжджають в акаунт уже після нього (docs/artist-radar.md).
 */
class LocalGuestArtists(private val database: PoruchDatabase) : GuestArtistStore {
    override fun artists(): List<GuestArtist> {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return emptyList()
        return runCatching {
            Json.parseToJsonElement(stored).jsonArray.mapNotNull { item ->
                val json = item.jsonObject
                GuestArtist(json["id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null, json["name"]?.jsonPrimitive?.contentOrNull.orEmpty())
            }
        }.getOrDefault(emptyList())
    }

    override fun saveArtists(artists: List<GuestArtist>) {
        database.cacheQueries.writeDevice(KEY, buildJsonArray { artists.forEach { addJsonObject { put("id", it.id); put("name", it.name) } } }.toString())
    }

    private companion object {
        const val KEY = "device:artists"
    }
}
