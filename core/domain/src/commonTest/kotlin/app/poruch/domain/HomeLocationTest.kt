package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class HomeLocationTest {
    private fun match(query: String, current: String = "Київ") = HomeLocation.mentioned(query, current)?.city

    @Test
    fun namesCityInAnyCommonForm() {
        assertEquals("Харків", match("Харків"))
        assertEquals("Харків", match("концерт у Харкові"))
        assertEquals("Харків", match("харк"))
        assertEquals("Одеса", match("Одесі джаз"))
        assertEquals("Дніпро", match("Дніпрі"))
        assertEquals("Львів", match("Львові"))
    }

    @Test
    fun ignoresCurrentCityAndOrdinaryWords() {
        assertNull(match("Харків", current = "Харків"))
        assertNull(match("йога"))
        assertNull(match("ха"))
        assertNull(match("  "))
    }

    @Test
    fun pointInsideCoveredCityIsThatCity() {
        // Київський район Одеси: геокодер каже «Лиманка».
        assertEquals("Одеса", HomeLocation.around(46.405, 30.715)?.city)
        assertEquals("Київ", HomeLocation.around(50.45, 30.52)?.city)
        // Полтава далеко від усіх покритих міст.
        assertNull(HomeLocation.around(49.5883, 34.5514))
    }
}
