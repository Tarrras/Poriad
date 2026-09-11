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
 * Остання відповідь на кожну область, щоб мапа мала що малювати ще до відповіді мережі.
 *
 * Ключ несе власника: результат залежить від того, хто питає (приєднані, збережені, приховані
 * блокуванням), тож чужий рядок не має спливати після зміни акаунта. `clearPrivate` — те, що
 * робить вихід із акаунта справжнім, а не косметичним.
 *
 * **Ключ не містить жодного `Double`, і це головне, що тут є.** Раніше він складався з
 * `EventQuery.toString()`, тобто з координат у вигляді, який `Double.toString` дає за
 * замовчуванням: сімнадцять значущих цифр. Мапа ніколи не спиняється двічі на тій самій позиції
 * до останнього біта, тож кожен рух писав рядок, який ніхто вже не прочитає. Кеш не кешував — він
 * лише накопичував: 458 КБ за шість пошуків, без строку й без межі.
 *
 * Тепер область квантується: центр до ≈110 м, масштаб — у степінь двійки від висоти вікна. Панорама
 * в межах кварталу читає той самий рядок; інше місто чи інший зум — інший.
 */
internal class EventCache(private val database: PoruchDatabase, private val json: Json) {

    fun key(query: EventQuery, userId: String?): String {
        val centreLatitude = round(query.south + (query.north - query.south) / 2)
        val centreLongitude = round(query.west + (query.east - query.west) / 2)
        // Масштаб, а не самі межі: два вікна однакової висоти навколо однієї точки — це той самий
        // погляд, навіть коли їхні краї відрізняються на піксель.
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
        // Формат рядка міг змінитися разом із застосунком: зіпсований кеш — це порожня мапа
        // на секунду, а не падіння.
        return runCatching { json.decodeFromString<DiscoveryEnvelope>(stored) }.getOrNull()
    }

    /**
     * Пише відповідь і одразу підрізає таблицю. Обидва витіснення тут, а не в окремому прибиранні
     * за розкладом: запис — єдиний момент, коли ми точно знаємо, що таблиця виросла.
     */
    fun write(key: String, payload: String) {
        val now = Clock.System.now().toEpochMilliseconds()
        database.cacheQueries.transaction {
            database.cacheQueries.write(key, payload, now)
            database.cacheQueries.evictExpired(now - ttlMillis)
            database.cacheQueries.evictOverflow(DiscoveryRules.CACHE_ENTRIES.toLong())
        }
    }

    /**
     * Вихід із акаунта. Кеш відповідей іде повністю — він увесь був відповіддю комусь конкретному;
     * зі сховища пристрою йде все, крім того, що належить самому телефону.
     */
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
        /** Нижня межа перед логарифмом: висота рівно нуль трапляється на виродженому вікні. */
        const val MIN_SPAN = 1e-6
    }
}
