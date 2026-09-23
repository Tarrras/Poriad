package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.PendingUnregister
import app.poruch.domain.PendingUnregisterStore
import kotlinx.serialization.json.*

/**
 * Незнятий пуш-токен під префіксом `device:`: вихід з акаунта чистить приватне, а цей запис має
 * пережити саме вихід. Access-токен тут живе до свого строку (година) — після нього запис марний.
 */
class LocalPendingUnregister(private val database: PoruchDatabase) : PendingUnregisterStore {
    override fun read(): PendingUnregister? {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return null
        val json = runCatching { Json.parseToJsonElement(stored).jsonObject }.getOrNull() ?: return null
        fun field(name: String) = json[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
        return PendingUnregister(
            field("token") ?: return null, field("user_id") ?: return null,
            field("access_token") ?: return null, json["expires_at"]?.jsonPrimitive?.longOrNull ?: return null
        )
    }

    override fun write(value: PendingUnregister?) {
        val payload = value?.let {
            buildJsonObject {
                put("token", it.token); put("user_id", it.userId)
                put("access_token", it.accessToken); put("expires_at", it.expiresAt)
            }.toString()
        } ?: "{}"
        database.cacheQueries.writeDevice(KEY, payload)
    }

    private companion object {
        const val KEY = "device:push-unregister"
    }
}
