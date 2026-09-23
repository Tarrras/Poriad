package app.poruch.data.local

import app.poruch.domain.*
import app.poruch.data.api.string
import app.poruch.data.cache.PoruchDatabase
import kotlinx.serialization.json.*
import kotlin.uuid.Uuid
import kotlin.uuid.ExperimentalUuidApi

/** Відбиток чернетки з її ключем ідемпотентності, що переживає смерть процесу. */
class PersistentCreationIdentity(
    private val database: PoruchDatabase,
    private val auth: AuthRepository
) : CreationIdentityStore {
    private fun key() = "pending-creation:${auth.session.value?.userId ?: "guest"}"

    @OptIn(ExperimentalUuidApi::class)
    override fun idFor(draft: EventDraft): String {
        // Уся чернетка, а не перелік полів: вік, схвалення й контакт колись випадали з відбитка, і
        // повтор після збою мережі публікував подію без змін безпеки. `toString` data-класу бачить
        // кожне поле, включно з майбутніми.
        val fingerprint = draft.toString()
        val previous = database.cacheQueries.readDevice(key()).executeAsOneOrNull()
            ?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() }
        if (previous?.string("fingerprint") == fingerprint) return previous.string("id")
        val id = Uuid.random().toString()
        database.cacheQueries.writeDevice(
            key(),
            buildJsonObject { put("fingerprint", fingerprint); put("id", id) }.toString()
        )
        return id
    }

    override fun clear() {
        database.cacheQueries.writeDevice(key(), "{}")
    }
}
