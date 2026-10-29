package app.poruch.domain

import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Зона «Моїх місць» (docs/my-places.md): район міста чи коло навколо точки. Список живе на телефоні ([ZoneStore]),
 * сервер знає його за токеном пуша й каже про нові події від людей у зонах.
 */
sealed interface Zone {
    /** Той самий ключ, що на сервері (`zone_areas.key`). */
    val key: String

    /** Район чи місцевість з `city_districts`. Назва — щоб показати список, не вантажачи районів. */
    data class Area(val districtId: Long, val city: String, val name: String) : Zone {
        override val key get() = "d:$districtId"
    }

    /** Коло [radiusM] навколо точки, округленої до ~100 м: місце, де людина живе, точніше знати не треба. */
    data class Circle(val latitude: Double, val longitude: Double, val radiusM: Int, val label: String?) : Zone {
        override val key get() = "c:${ZoneRules.fixed(latitude)},${ZoneRules.fixed(longitude)},$radiusM"
    }
}

/**
 * Зони на телефоні (`device:zones`): як артисти гостя, переживають вихід з акаунта. Назви методів свої, а не
 * `read`/`write`: Kotlin/Native інакше перейменував би їх у протоколах, які реалізує iOS.
 */
interface ZoneStore {
    fun zones(): List<Zone>
    fun saveZones(zones: List<Zone>)
}

object ZoneRules {
    /** Сервер приймає до 20 районів і 10 кіл; людині вистачить десяти зон загалом. */
    const val MAX = 10
    val RADII = listOf(1000, 2000, 3000)
    const val RADIUS = 2000
    /** Менше людей поруч організатору не показуємо: сервер і так віддає null. */
    const val AUDIENCE_MIN = 3

    /** Коло з точкою, округленою як на сервері; підпис — район, у якому центр (не місцевість), якщо такий є. */
    fun circle(latitude: Double, longitude: Double, radiusM: Int, districts: List<District>): Zone.Circle {
        val lat = round(latitude)
        val lon = round(longitude)
        return Zone.Circle(lat, lon, radiusM, districts.firstOrNull { !it.isLocality && it.contains(lat, lon) }?.name)
    }

    /** Чи точка в якійсь із зон. Район рахується лише з межами з [districts] — міста, яке зараз відкрите. */
    fun covers(zones: List<Zone>, districts: List<District>, latitude: Double, longitude: Double): Boolean = zones.any { zone ->
        when (zone) {
            is Zone.Area -> districts.firstOrNull { it.id == zone.districtId }?.contains(latitude, longitude) == true
            is Zone.Circle -> HomeLocation("", zone.latitude, zone.longitude).kmTo(latitude, longitude) * 1000 <= zone.radiusM
        }
    }

    /** Додає зону чи знімає ту саму; новіші — останніми, понад [MAX] найстаріша йде. */
    fun toggle(zones: List<Zone>, zone: Zone): List<Zone> =
        if (zones.any { it.key == zone.key }) zones.filter { it.key != zone.key } else (zones + zone).takeLast(MAX)

    internal fun round(value: Double): Double = (value * 1000).roundToLong() / 1000.0

    /** Три знаки після коми, як `to_char(…, 'FM90.000')` на сервері. */
    internal fun fixed(value: Double): String {
        val thousandths = abs((value * 1000).roundToLong())
        val sign = if (value < 0 && thousandths != 0L) "-" else ""
        return "$sign${thousandths / 1000}.${(thousandths % 1000).toString().padStart(3, '0')}"
    }
}
