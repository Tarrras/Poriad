package app.poruch.data.events

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.AuthRepository
import app.poruch.domain.CachedMine
import kotlinx.serialization.json.Json

/**
 * Останні «Мої події» на телефоні: план видно дорогою й на місці, де мережі нема. Три відповіді — події, закладки й
 * черга, — бо розрізи «Іду» і «Збережені» будуються з усіх трьох. `device_store`, а не кеш видачі: його не витісняє
 * гортання мапи. Ключі без `device:`, тож вихід з акаунта забирає їх разом з рештою приватного.
 */
internal class MineCache(private val database: PoruchDatabase, private val json: Json, private val auth: AuthRepository) {

    /** Пише, лише коли акаунт той самий, що на початку запиту: відповідь попереднього не має пережити вихід. */
    fun write(key: String, owner: String?, payload: String) {
        if (owner != null && owner == auth.session.value?.userId) database.cacheQueries.writeDevice(PREFIX + key, payload)
    }

    fun read(): CachedMine? {
        val events = stored(EVENTS) ?: return null
        // Формат міг змінитися з оновленням: зіпсований кеш — порожньо до мережі, а не падіння.
        return runCatching {
            CachedMine(
                json.decodeFromString<List<EventDto>>(events).map { it.domain() },
                stored(SAVED)?.let { json.decodeFromString<List<String>>(it) }.orEmpty(),
                stored(QUEUED)?.let { json.decodeFromString<List<String>>(it) }.orEmpty()
            )
        }.getOrNull()
    }

    private fun stored(key: String) = database.cacheQueries.readDevice(PREFIX + key).executeAsOneOrNull()

    companion object {
        private const val PREFIX = "mine:"
        const val EVENTS = "events"
        const val SAVED = "saved"
        const val QUEUED = "queued"
    }
}
