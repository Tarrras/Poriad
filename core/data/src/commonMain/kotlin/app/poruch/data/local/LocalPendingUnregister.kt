package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.PendingUnregister
import app.poruch.domain.PendingUnregisterStore
import kotlinx.serialization.json.*

/**
 * Незнятий пуш-токен під префіксом `device:`: вихід з акаунта чистить приватне, а цей запис має
 * пережити саме вихід. Лише токен і акаунт: ключа доступу в звичайному SQLite не тримаємо, а
 * `access_token` і `expires_at` у записі старої версії просто ігноруємо — наступний запис їх затре.
 */
class LocalPendingUnregister(private val database: PoruchDatabase) : PendingUnregisterStore {
    override fun read(): PendingUnregister? {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return null
        val json = runCatching { Json.parseToJsonElement(stored).jsonObject }.getOrNull() ?: return null
        fun field(name: String) = json[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
        return PendingUnregister(field("token") ?: return null, field("user_id") ?: return null)
    }

    override fun write(value: PendingUnregister?) {
        val payload = value?.let {
            buildJsonObject {
                put("token", it.token); put("user_id", it.userId)
            }.toString()
        } ?: "{}"
        database.cacheQueries.writeDevice(KEY, payload)
    }

    private companion object {
        const val KEY = "device:push-unregister"
    }
}
