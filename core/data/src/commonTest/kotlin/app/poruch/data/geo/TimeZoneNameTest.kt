package app.poruch.data.geo

import kotlinx.coroutines.test.runTest
import kotlinx.datetime.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** У базу йде `Europe/Kyiv`, навіть якщо пристрій каже `Europe/Kiev`. */
class TimeZoneNameTest {

    @Test
    fun theKyivZoneIsStoredUnderItsCurrentName() {
        // Передумова: без нової назви в tzdb підстановка мовчки не спрацює.
        assertTrue("Europe/Kyiv" in TimeZone.availableZoneIds, "tzdb цієї збірки не знає Europe/Kyiv")

        assertEquals("Europe/Kyiv", modernZoneName("Europe/Kiev"))
        // tzdb 2022b злила ці два з київським.
        assertEquals("Europe/Kyiv", modernZoneName("Europe/Uzhgorod"))
        assertEquals("Europe/Kyiv", modernZoneName("Europe/Zaporozhye"))
    }

    /** Наскрізь: платформа віддала стару назву, у чернетку потрапила сучасна. */
    @Test
    fun whatTheLocatorReturnsIsAlreadyRenamed() = runTest {
        val android = PlatformTimeZoneLocator { _, _ -> "Europe/Kiev" }
        assertEquals("Europe/Kyiv", android.zoneAt(50.45, 30.52))

        val ios = PlatformTimeZoneLocator { _, _ -> "Europe/Kyiv" }
        assertEquals("Europe/Kyiv", ios.zoneAt(50.45, 30.52))
    }

    /** Не визначили — не вигадуємо. */
    @Test
    fun anUnknownPlaceStaysUnknown() = runTest {
        assertNull(PlatformTimeZoneLocator { _, _ -> null }.zoneAt(0.0, 0.0))
        assertNull(PlatformTimeZoneLocator { _, _ -> error("геокодер недоступний") }.zoneAt(0.0, 0.0))
    }

    /** Неперевірені назви проходять недоторканими. */
    @Test
    fun everyOtherZoneKeepsItsName() {
        assertEquals("Europe/Warsaw", modernZoneName("Europe/Warsaw"))
        assertEquals("America/New_York", modernZoneName("America/New_York"))
        assertEquals("Europe/Simferopol", modernZoneName("Europe/Simferopol"))
    }
}
