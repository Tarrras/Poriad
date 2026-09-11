package app.poruch.data.geo

import kotlinx.coroutines.test.runTest
import kotlinx.datetime.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ім'я поясу, яке потрапляє в базу.
 *
 * Пристрій може називати київський пояс `Europe/Kiev` — так його звала tzdb до 2022b, і саме так
 * ICU на Android 16 досі вважає канонічним. Але міграції, конвеєр імпорту й наявні дані знають
 * `Europe/Kyiv`, і двох написань одного поясу в одній таблиці бути не повинно.
 */
class TimeZoneNameTest {

    @Test
    fun theKyivZoneIsStoredUnderItsCurrentName() {
        // Передумова, а не припущення: якби tzdb цієї збірки не знала нової назви, підстановка
        // мусила б мовчки не спрацювати — і цей рядок сказав би про це першим.
        assertTrue("Europe/Kyiv" in TimeZone.availableZoneIds, "tzdb цієї збірки не знає Europe/Kyiv")

        assertEquals("Europe/Kyiv", modernZoneName("Europe/Kiev"))
        // tzdb 2022b злила ці два з київським.
        assertEquals("Europe/Kyiv", modernZoneName("Europe/Uzhgorod"))
        assertEquals("Europe/Kyiv", modernZoneName("Europe/Zaporozhye"))
    }

    /**
     * Той самий шлях, яким іде застосунок: платформа віддала стару назву — у чернетку потрапила
     * сучасна. Саме цю ланку не видно в попередньому тесті, бо там перевіряється сама функція.
     */
    @Test
    fun whatTheLocatorReturnsIsAlreadyRenamed() = runTest {
        val android = PlatformTimeZoneLocator { _, _ -> "Europe/Kiev" }
        assertEquals("Europe/Kyiv", android.zoneAt(50.45, 30.52))

        val ios = PlatformTimeZoneLocator { _, _ -> "Europe/Kyiv" }
        assertEquals("Europe/Kyiv", ios.zoneAt(50.45, 30.52))
    }

    /** Не змогли визначити — не вигадуємо: екран лишає пояс пристрою. */
    @Test
    fun anUnknownPlaceStaysUnknown() = runTest {
        assertNull(PlatformTimeZoneLocator { _, _ -> null }.zoneAt(0.0, 0.0))
        assertNull(PlatformTimeZoneLocator { _, _ -> error("геокодер недоступний") }.zoneAt(0.0, 0.0))
    }

    /** Список навмисно короткий: усе, чого ми не перевіряли, має проходити недоторканим. */
    @Test
    fun everyOtherZoneKeepsItsName() {
        assertEquals("Europe/Warsaw", modernZoneName("Europe/Warsaw"))
        assertEquals("America/New_York", modernZoneName("America/New_York"))
        assertEquals("Europe/Simferopol", modernZoneName("Europe/Simferopol"))
    }
}
