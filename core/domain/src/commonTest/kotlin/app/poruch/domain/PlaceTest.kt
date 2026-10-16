package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals

class PlaceTest {
    private fun event(id: String, lat: Double, lon: Double) = EventIndexEntry(
        id = id, latitude = lat, longitude = lon, category = EventCategory.MUSIC,
        startsAt = "2030-09-06T19:00:00Z", timeZone = "Europe/Kyiv", title = id,
        origin = EventOrigin.IMPORT, source = "karabas"
    )

    private val bochka = Place("p1", "Бочка пивна", "Київ", "Хрещатик, 19А", 50.447, 30.522, upcoming = 26)

    /** Рядок закладу каже стільки, скільки покаже стос піна, а не скільки різних назв нарахував сервер. */
    @Test
    fun countsWhatThePinWillShow() {
        val index = List(24) { event("e$it", 50.447, 30.522) } + event("other", 50.45, 30.52)
        assertEquals(24, bochka.countedIn(index).upcoming)
    }

    /** Закладу нема в індексі (інше місто, «Всюди») — лишається серверне число. */
    @Test
    fun keepsServerCountOutsideTheIndex() {
        assertEquals(26, bochka.countedIn(listOf(event("other", 50.45, 30.52))).upcoming)
    }
}
