package app.poruch.data.local

import app.poruch.domain.Crowd
import app.poruch.domain.Taste
import app.poruch.domain.TasteStore
import app.poruch.domain.TimeSlot
import app.poruch.data.cache.PoruchDatabase
import kotlinx.serialization.json.*

/**
 * Відповіді онбордингу на пристрої. Живуть під префіксом `device:`, який не чистить вихід
 * з акаунта. З акаунтом категорії їдуть і на сервер (`SupabasePreferencesRepository`), а ця
 * копія відповідає миттєво на старті.
 */
class LocalTasteStore(private val database: PoruchDatabase) : TasteStore {
    override fun read(): Taste {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return Taste()
        val json =
            runCatching { Json.parseToJsonElement(stored).jsonObject }.getOrNull() ?: return Taste()
        // Невідомі значення відкидаємо: застаріле ранжувало б проти нічого.
        return Taste(
            interests = json.strings("interests"),
            times = json.strings("times").filter(TimeSlot::isSlot),
            crowd = json["crowd"]?.jsonPrimitive?.contentOrNull?.takeIf(Crowd::isCrowd)
                ?: Crowd.ANY,
            answered = json["answered"]?.jsonPrimitive?.booleanOrNull ?: false
        )
    }

    override fun write(taste: Taste) {
        val payload = buildJsonObject {
            put("interests", JsonArray(taste.interests.map(::JsonPrimitive)))
            put("times", JsonArray(taste.times.map(::JsonPrimitive)))
            put("crowd", taste.crowd)
            put("answered", taste.answered)
        }
        database.cacheQueries.writeDevice(KEY, payload.toString())
    }

    private fun JsonObject.strings(name: String) =
        this[name]?.jsonArray?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty()

    private companion object {
        const val KEY = "device:taste"
    }
}
