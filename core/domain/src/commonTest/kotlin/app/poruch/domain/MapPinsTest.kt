package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MapPinsTest {

    // Піни групують афішу: її координати приходять з кеша майданчиків і збігаються.
    private fun event(id: String, lat: Double, lon: Double, startsAt: String) = EventIndexEntry(
        id = id, latitude = lat, longitude = lon, category = "music",
        startsAt = startsAt, timeZone = "Europe/Kyiv", title = id,
        origin = EventOrigin.IMPORT, source = "karabas"
    )

    @Test
    fun `venues three metres apart do not collapse`() {
        // Стара згортка ключа `lat*31 + lon` давала цим точкам одне число.
        val pins = MapPins.group(
            listOf(
                event("a", 50.450000, 30.520000, "2026-10-17T15:00:00Z"),
                event("b", 50.450001, 30.519969, "2026-10-17T15:00:00Z")
            )
        )
        assertEquals(2, pins.size)
    }

    @Test
    fun `events at one venue collapse into a single pin`() {
        // Кеш майданчиків дає всім подіям закладу ту саму точку.
        val pins = MapPins.group(
            listOf(
                event("a", 50.4498664, 30.5278357, "2026-10-17T15:00:00Z"),
                event("b", 50.4498664, 30.5278357, "2026-10-18T15:00:00Z"),
                event("c", 50.4498664, 30.5278357, "2026-10-19T15:00:00Z")
            )
        )
        assertEquals(1, pins.size)
        assertEquals(3, pins.single().count)
        assertTrue(pins.single().hasMany)
        assertEquals(listOf("a", "b", "c"), pins.single().eventIds)
    }

    @Test
    fun `different venues stay apart`() {
        val pins = MapPins.group(
            listOf(
                event("a", 50.4498664, 30.5278357, "2026-10-17T15:00:00Z"),
                event("b", 50.4222048, 30.5211548, "2026-10-17T15:00:00Z")
            )
        )
        assertEquals(2, pins.size)
        assertTrue(pins.none { it.hasMany })
    }

    @Test
    fun `the soonest event names the pin`() {
        val pins = MapPins.group(
            listOf(
                event("later", 50.45, 30.52, "2026-12-01T15:00:00Z"),
                event("sooner", 50.45, 30.52, "2026-09-10T15:00:00Z")
            )
        )
        assertEquals("sooner", pins.single().representative.id)
        assertEquals(listOf("sooner", "later"), pins.single().eventIds)
    }

    @Test
    fun `a pin knows whether the selection is inside it`() {
        val pin = MapPins.group(listOf(event("a", 50.45, 30.52, "2026-09-10T15:00:00Z"))).single()
        assertTrue(pin.contains("a"))
        assertTrue(!pin.contains("b"))
        assertTrue(!pin.contains(null))
    }

    @Test
    fun `others at the venue skip the opened card and its own run`() {
        val opened = event("a", 50.45, 30.52, "2026-10-17T15:00:00Z")
        val run = event("b", 50.45, 30.52, "2026-10-19T15:00:00Z").copy(
            sessions = listOf(EventSession("b", "2026-10-19T15:00:00Z", "Europe/Kyiv"), EventSession("a", opened.startsAt, "Europe/Kyiv"))
        )
        val index = listOf(
            event("later", 50.45, 30.52, "2026-10-20T15:00:00Z"),
            event("elsewhere", 50.46, 30.52, "2026-10-18T15:00:00Z"),
            event("sooner", 50.45, 30.52, "2026-10-18T15:00:00Z"),
            run, opened
        )
        val full = Event(
            id = "a", title = "a", description = "", category = "music", city = "Київ", address = "",
            startsAt = opened.startsAt, endsAt = opened.startsAt, timeZone = "Europe/Kyiv",
            status = EventStatus.PUBLISHED, latitude = 50.45, longitude = 30.52
        )
        assertEquals(listOf("sooner", "later"), MapPins.othersAt(full, index).map { it.id })
    }
}
