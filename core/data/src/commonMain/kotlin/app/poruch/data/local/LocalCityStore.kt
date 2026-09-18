package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.CityResult
import app.poruch.domain.CityStore
import kotlinx.serialization.json.*

/** Останнє місто під префіксом `device:`: як і смак, належить телефону, а не акаунту. */
class LocalCityStore(private val database: PoruchDatabase) : CityStore {
    override fun read(): CityResult? {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return null
        val json = runCatching { Json.parseToJsonElement(stored).jsonObject }.getOrNull() ?: return null
        val name = json["name"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() } ?: return null
        val latitude = json["latitude"]?.jsonPrimitive?.doubleOrNull ?: return null
        val longitude = json["longitude"]?.jsonPrimitive?.doubleOrNull ?: return null
        // Пошкоджений запис — не причина відкрити мапу посеред океану.
        if (latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return null
        return CityResult(name, latitude, longitude)
    }

    override fun write(city: CityResult) {
        val payload = buildJsonObject {
            put("name", city.name)
            put("latitude", city.latitude)
            put("longitude", city.longitude)
        }
        database.cacheQueries.writeDevice(KEY, payload.toString())
    }

    private companion object {
        const val KEY = "device:city"
    }
}
