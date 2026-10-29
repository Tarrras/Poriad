package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ZoneRulesTest {
    /** Квадрат `lon 30..31, lat 50..51` — «район» для перевірок. */
    private val podil = District(7, "Київ", "Подільський район", rings = listOf(doubleArrayOf(30.0, 50.0, 31.0, 50.0, 31.0, 51.0, 30.0, 51.0, 30.0, 50.0)))
    private val locality = District(-9, "Київ", "Виноградар", rings = podil.rings, radiusM = 1500)

    /** Ключ — той самий, що складає сервер (`to_char(…, 'FM90.000')`): інакше `created_at` зони скидався б щоразу. */
    @Test fun keysMatchTheServer() {
        val circle = ZoneRules.circle(50.51049, 30.60012, 1000, emptyList())
        assertEquals("c:50.510,30.600,1000", circle.key)
        assertEquals(50.51, circle.latitude)
        assertEquals("c:46.005,30.700,2000", ZoneRules.circle(46.0049, 30.6999, 2000, emptyList()).key)
        assertEquals("d:-9", Zone.Area(-9, "Київ", "Виноградар").key)
    }

    /** Підпис кола — район центру, не місцевість. */
    @Test fun circleIsLabelledByItsDistrict() {
        assertEquals("Подільський район", ZoneRules.circle(50.5, 30.5, 2000, listOf(locality, podil)).label)
        assertNull(ZoneRules.circle(49.0, 30.5, 2000, listOf(podil)).label)
    }

    @Test fun coversCirclesAndDistrictsOfTheOpenCity() {
        val circle = ZoneRules.circle(50.45, 30.52, 1000, emptyList())
        assertTrue(ZoneRules.covers(listOf(circle), emptyList(), 50.458, 30.52), "~890 м на північ")
        assertFalse(ZoneRules.covers(listOf(circle), emptyList(), 50.46, 30.52), "~1,1 км — уже ні")
        val area = Zone.Area(7, "Київ", "Подільський район")
        assertTrue(ZoneRules.covers(listOf(area), listOf(podil), 50.5, 30.5))
        assertFalse(ZoneRules.covers(listOf(area), emptyList(), 50.5, 30.5), "межі району іншого міста не відомі")
    }

    @Test fun toggleAddsRemovesAndKeepsTheNewest() {
        val area = Zone.Area(7, "Київ", "Подільський район")
        assertEquals(listOf<Zone>(area), ZoneRules.toggle(emptyList(), area))
        assertEquals(emptyList(), ZoneRules.toggle(listOf(area), area.copy(name = "інша назва")), "той самий ключ — зняти")
        val many = (101L..100L + ZoneRules.MAX).map { Zone.Area(it, "Київ", "$it") }
        val next = ZoneRules.toggle(many, area)
        assertEquals(ZoneRules.MAX, next.size)
        assertEquals(area, next.last())
        assertFalse(next.any { it.key == "d:101" }, "найстаріша йде")
    }
}
