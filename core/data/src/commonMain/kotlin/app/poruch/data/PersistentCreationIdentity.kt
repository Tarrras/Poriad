package app.poruch.data

import app.poruch.domain.*
import app.poruch.data.cache.PoruchDatabase
import kotlinx.serialization.json.*
import kotlin.uuid.Uuid
import kotlin.uuid.ExperimentalUuidApi

/** A persisted draft fingerprint retains its idempotency key after process death. */
class PersistentCreationIdentity(private val database: PoruchDatabase, private val auth: AuthRepository): CreationIdentityStore {
    private fun key()="pending-creation:${auth.session.value?.userId ?: "guest"}"
    @OptIn(ExperimentalUuidApi::class)
    override fun idFor(draft: EventDraft): String {
        val fingerprint=JsonArray(listOf(draft.title,draft.description,draft.category,draft.city,draft.address,draft.latitude.toString(),draft.longitude.toString(),draft.startsAt,draft.endsAt,draft.timeZone,draft.capacity.toString(),draft.imageUrl.orEmpty()).map(::JsonPrimitive)).toString()
        val previous=database.cacheQueries.read(key()).executeAsOneOrNull()?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() }
        if(previous?.string("fingerprint")==fingerprint) return previous.string("id")
        val id=Uuid.random().toString()
        database.cacheQueries.write(key(),buildJsonObject { put("fingerprint",fingerprint); put("id",id) }.toString())
        return id
    }
    override fun clear() { database.cacheQueries.write(key(),"{}") }
}
