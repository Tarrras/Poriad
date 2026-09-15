package app.poruch.data.events

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.DiscoveryRules
import app.poruch.domain.EventQuery
import kotlinx.serialization.json.Json
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log2
import kotlin.math.pow
import kotlin.math.roundToLong
import kotlin.time.Clock

/**
 * Остання відповідь на кожну область, щоб мапа мала що малювати до відповіді мережі.
 *
 * Ключ включає користувача: відповідь залежить від того, хто питає, і чужий рядок не має
 * спливати після зміни акаунта. Ключ не містить Double: область квантується (центр до ~110 м,
 * зум — степінь двійки від висоти вікна), інакше кожен рух мапи писав унікальний рядок і кеш
 * лише накопичував.
 */
internal class EventCache(private val database: PoruchDatabase, private val json: Json) {

    fun key(query: EventQuery, userId: String?): String {
        val centreLatitude = round(query.south + (query.north - query.south) / 2)
        val centreLongitude = round(query.west + (query.east - query.west) / 2)
        // Масштаб, а не межі: вікна однакової висоти навколо однієї точки — той самий погляд.
        val span = abs(query.north - query.south).coerceAtLeast(MIN_SPAN)
        val zoom = floor(log2(span)).toLong()
        return listOf(
            userId ?: "guest",
            "$centreLatitude/$centreLongitude@$zoom",
            query.category ?: "-",
            query.from ?: "-",
            query.to ?: "-",
            query.text?.lowercase()?.trim().takeUnless { it.isNullOrEmpty() } ?: "-",
            if (query.available) "free" else "-"
        ).joinToString(":")
    }

    fun read(key: String): DiscoveryEnvelope? {
        val cutoff = Clock.System.now().toEpochMilliseconds() - ttlMillis
        val stored = database.cacheQueries.read(key, cutoff).executeAsOneOrNull() ?: return null
        // Формат міг змінитися з оновленням: зіпсований кеш — порожня мапа на секунду, а не падіння.
        return runCatching { json.decodeFromString<DiscoveryEnvelope>(stored) }.getOrNull()
    }

    /** Пише відповідь і одразу витісняє прострочене та зайве: запис — момент, коли таблиця виросла. */
    fun write(key: String, payload: String) {
        val now = Clock.System.now().toEpochMilliseconds()
        database.cacheQueries.transaction {
            database.cacheQueries.write(key, payload, now)
            database.cacheQueries.evictExpired(now - ttlMillis)
            database.cacheQueries.evictOverflow(DiscoveryRules.CACHE_ENTRIES.toLong())
        }
    }

    /** Вихід із акаунта: кеш відповідей повністю, зі сховища пристрою — все, крім належного телефону. */
    fun clearPrivate() {
        database.cacheQueries.transaction {
            database.cacheQueries.clearPrivate()
            database.cacheQueries.clearPrivateDevice()
        }
    }

    private fun round(value: Double): Long {
        val grid = 10.0.pow(DiscoveryRules.CACHE_KEY_PRECISION)
        return (value * grid).roundToLong()
    }

    private val ttlMillis get() = DiscoveryRules.CACHE_TTL_HOURS.toLong() * 60 * 60 * 1000

    private companion object {
        /** Нижня межа перед логарифмом: вироджене вікно має нульову висоту. */
        const val MIN_SPAN = 1e-6
    }
}
