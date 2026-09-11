package app.poruch.data.local

import app.poruch.domain.Crowd
import app.poruch.domain.Taste
import app.poruch.domain.TasteStore
import app.poruch.domain.TimeSlot
import app.poruch.data.cache.PoruchDatabase
import kotlinx.serialization.json.*

/**
 * The opening answers, kept on the device.
 *
 * They are asked before there is an account and they keep working after a sign-out, so they live
 * under the `device:` prefix the private-cache sweep leaves alone. When an account does appear its
 * categories go up to the server as well — that half is `SupabasePreferencesRepository`'s — and
 * this stays the copy that answers instantly at launch, before any request has been made.
 */
class LocalTasteStore(private val database: PoruchDatabase) : TasteStore {
    override fun read(): Taste {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return Taste()
        val json = runCatching { Json.parseToJsonElement(stored).jsonObject }.getOrNull() ?: return Taste()
        // A value we no longer recognise is dropped rather than carried: the vocabulary of
        // categories and slots is the app's, and a stale one would rank against nothing.
        return Taste(
            interests = json.strings("interests"),
            times = json.strings("times").filter(TimeSlot::isSlot),
            crowd = json["crowd"]?.jsonPrimitive?.contentOrNull?.takeIf(Crowd::isCrowd) ?: Crowd.ANY,
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
