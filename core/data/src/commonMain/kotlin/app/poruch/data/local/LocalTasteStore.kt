package app.poruch.data.local

import app.poruch.domain.EventCategory
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
            interests = json.strings("interests").map(EventCategory::fromKey).filter { it != EventCategory.UNKNOWN },
            times = json.strings("times").mapNotNull(TimeSlot::fromKey),
            crowd = Crowd.fromKey(json["crowd"]?.jsonPrimitive?.contentOrNull) ?: Crowd.ANY,
            answered = json["answered"]?.jsonPrimitive?.booleanOrNull ?: false,
            interestsOwner = json["owner"]?.jsonPrimitive?.contentOrNull
        )
    }

    override fun write(taste: Taste) {
        val payload = buildJsonObject {
            put("interests", JsonArray(taste.interests.map { JsonPrimitive(it.key) }))
            put("times", JsonArray(taste.times.map { JsonPrimitive(it.key) }))
            put("crowd", taste.crowd.key)
            put("answered", taste.answered)
            taste.interestsOwner?.let { put("owner", it) }
        }
        database.cacheQueries.writeDevice(KEY, payload.toString())
    }

    private fun JsonObject.strings(name: String) =
        this[name]?.jsonArray?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty()

    private companion object {
        const val KEY = "device:taste"
    }
}
