package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DistrictTest {
    /** Квадрат `lon 0..1, lat 0..1` кільцем `lon, lat…`, зсунутий на [dx], [dy] і стиснутий у [scale] раз. */
    private fun square(dx: Double = 0.0, dy: Double = 0.0, scale: Double = 1.0) =
        doubleArrayOf(0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0)
            .mapIndexed { i, v -> v * scale + if (i % 2 == 0) dx else dy }.toDoubleArray()

    private fun district(name: String, formerName: String? = null, aliases: List<String> = emptyList(), vararg rings: DoubleArray) =
        District(1, "Одеса", name, formerName, aliases, rings.toList().ifEmpty { listOf(square()) })

    /** Дірка в районі — не район, відрізаний шматок на іншому березі — район. Кільця йдуть поспіль, без ролей. */
    @Test
    fun containsCountsCrossings() {
        val district = district("Альфа район", rings = arrayOf(square(), square(0.4, 0.4, 0.2), square(2.0, 0.0)))
        assertTrue(district.contains(latitude = 0.2, longitude = 0.2))
        assertFalse(district.contains(latitude = 0.5, longitude = 0.5), "дірка")
        assertTrue(district.contains(latitude = 0.5, longitude = 2.5), "анклав")
        assertFalse(district.contains(latitude = 0.5, longitude = 1.5), "між кільцями")
        assertFalse(district.contains(latitude = 5.0, longitude = 0.5), "за межами")
        assertEquals(listOf(0.0, 0.0, 1.0, 3.0), listOf(district.south, district.west, district.north, district.east))
    }

    /** «Київський», «київський р-н», «КИЇВ» — той самий район; кожне слово — початок слова назви. */
    @Test
    fun matchesWordPrefixes() {
        val kyivskyi = district("Київський район")
        listOf("Київський", "київський район", "Київський р-н", "  КИЇВ ", "ки", "район київ").forEach {
            assertTrue(kyivskyi.matches(it), it)
        }
        listOf("Приморський", "ський", "київська", "к", "", "   ").forEach {
            assertFalse(kyivskyi.matches(it), it)
        }
    }

    /** Латиницею — тією самою таблицею, що сервер: «kyivskyi», «Solomianskyi». */
    @Test
    fun matchesLatin() {
        assertTrue(district("Київський район").matches("kyivsk"))
        assertTrue(district("Київський район").matches("Kyivskyi Raion"))
        assertTrue(district("Солом’янський район").matches("solomian"))
        assertFalse(district("Київський район").matches("kiev"))
    }

    /** Колишня назва й звичні назви — теж назви; апостроф будь-який. Подвійна назва знаходиться за другою половиною. */
    @Test
    fun matchesFormerAliasesApostrophesAndHyphens() {
        assertTrue(district("Хаджибейський район", formerName = "Малиновський район").matches("Малиновськ"), "колишня")
        assertTrue(district("Оболонський район", aliases = listOf("Оболонь")).matches("оболонь"), "звична")
        val solomianskyi = district("Солом’янський район")
        listOf("Солом'ян", "Соломʼян", "солом’янський", "Солом`ян").forEach { assertTrue(solomianskyi.matches(it), it) }
        assertTrue(district("Амур-Нижньодніпровський район").matches("нижньодніпр"), "дефіс")
    }

    /** Ті самі рядки, що віддає `private.search_translit` на dev (24.10). */
    @Test
    fun latinIsTheServerTable() {
        mapOf(
            "київський район" to "kyivskyi raion", "солом’янський район" to "solomianskyi raion",
            "хаджибейський" to "khadzhybeiskyi", "щастя" to "shchastia", "ґанок" to "ganok",
            "подольский район" to "podolskyi raion", "жовтневий" to "zhovtnevyi", "цюрупинськ" to "tsiurupynsk"
        ).forEach { (cyrillic, latin) -> assertEquals(latin, District.latin(cyrillic)) }
    }

    /** Місцевість — коло з радіусом: «1,5 км навколо», ціле — без коми; район — без радіуса. */
    @Test
    fun localityRadius() {
        assertEquals(listOf("1,5", "1", "2,3"), listOf(1500, 1000, 2250).map { District(1, "Одеса", "Аркадія", rings = emptyList(), radiusM = it).radiusKm })
        assertTrue(District(1, "Одеса", "Аркадія", rings = emptyList(), radiusM = 1500).isLocality)
        assertFalse(district("Київський район").isLocality)
        assertEquals(null, district("Київський район").radiusKm)
    }

    @Test
    fun equalById() {
        assertEquals(district("Київський район"), District(1, "Одеса", "Інша назва", rings = emptyList()))
    }
}
