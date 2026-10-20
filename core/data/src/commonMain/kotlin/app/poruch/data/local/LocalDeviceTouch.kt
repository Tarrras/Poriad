package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.DeviceTouch
import app.poruch.domain.DeviceTouchStore
import kotlinx.serialization.json.*

/** Останнє, що почув сервер каналу повернення, під префіксом `device:`: пристрій, а не акаунт. */
class LocalDeviceTouch(private val database: PoruchDatabase) : DeviceTouchStore {
    override fun last(): DeviceTouch? {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return null
        val json = runCatching { Json.parseToJsonElement(stored).jsonObject }.getOrNull() ?: return null
        return DeviceTouch(
            json["token"]?.jsonPrimitive?.contentOrNull ?: return null,
            json["city"]?.jsonPrimitive?.contentOrNull,
            json["interests"]?.jsonArray?.map { it.jsonPrimitive.content } ?: return null,
            json["at"]?.jsonPrimitive?.longOrNull ?: return null
        )
    }

    override fun save(touch: DeviceTouch?) {
        val payload = touch?.let {
            buildJsonObject {
                put("token", it.token); put("city", it.city); put("at", it.at)
                putJsonArray("interests") { it.interests.forEach { key -> add(key) } }
            }.toString()
        } ?: "{}"
        database.cacheQueries.writeDevice(KEY, payload)
    }

    private companion object {
        const val KEY = "device:winback"
    }
}
