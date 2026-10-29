package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.Zone
import app.poruch.domain.ZoneStore
import kotlinx.serialization.json.*

/** «Мої місця» під префіксом `device:`: зони пристрою переживають вихід з акаунта (docs/my-places.md). */
class LocalZones(private val database: PoruchDatabase) : ZoneStore {
    override fun zones(): List<Zone> {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return emptyList()
        return runCatching {
            Json.parseToJsonElement(stored).jsonArray.mapNotNull { item ->
                val json = item.jsonObject
                val district = json["district"]?.jsonPrimitive?.longOrNull
                if (district != null) Zone.Area(district, json["city"]?.jsonPrimitive?.contentOrNull.orEmpty(), json["name"]?.jsonPrimitive?.contentOrNull.orEmpty())
                else Zone.Circle(
                    json["lat"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null,
                    json["lon"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null,
                    json["r"]?.jsonPrimitive?.intOrNull ?: return@mapNotNull null,
                    json["label"]?.jsonPrimitive?.contentOrNull
                )
            }
        }.getOrDefault(emptyList())
    }

    override fun saveZones(zones: List<Zone>) {
        database.cacheQueries.writeDevice(KEY, buildJsonArray {
            zones.forEach { zone ->
                addJsonObject {
                    when (zone) {
                        is Zone.Area -> { put("district", zone.districtId); put("city", zone.city); put("name", zone.name) }
                        is Zone.Circle -> { put("lat", zone.latitude); put("lon", zone.longitude); put("r", zone.radiusM); zone.label?.let { put("label", it) } }
                    }
                }
            }
        }.toString())
    }

    private companion object {
        const val KEY = "device:zones"
    }
}
