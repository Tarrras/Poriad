package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.*

@OptIn(ExperimentalCoroutinesApi::class)
class PlaceLookupTest {
    private val place = PlaceResult("Фролівська, 9", "Поділ, Київ", "Київ", 50.46, 30.51)
    private class Addresses(var fail: Boolean = false, val found: List<PlaceResult>) : AddressSearch {
        override suspend fun places(query: String, latitude: Double, longitude: Double) = if (fail) fail(AppError.Network) else found
        override suspend fun placeAt(latitude: Double, longitude: Double) = if (fail) fail(AppError.Network) else found.firstOrNull()
    }

    /** Без сервісу і при збої мережі редактор отримує «нічого», а не банер. */
    @Test fun missingServiceAndFailuresBothAnswerNothing() = runTest {
        var answers = mutableListOf<Any?>()
        PlaceLookup(null, null, backgroundScope).apply {
            searchAddress("Фролівська", 50.0, 30.0) { answers.add(it) }
            resolveAddress(50.0, 30.0) { answers.add(it) }
            resolveTimeZone(50.0, 30.0) { answers.add(it) }
        }
        assertEquals(listOf<Any?>(emptyList<PlaceResult>(), null, null), answers)

        answers = mutableListOf()
        val broken = Addresses(fail = true, found = listOf(place))
        PlaceLookup(broken, null, backgroundScope).apply {
            searchAddress("Фролівська", 50.0, 30.0) { answers.add(it) }
            resolveAddress(50.0, 30.0) { answers.add(it) }
        }
        runCurrent()
        assertEquals(listOf<Any?>(emptyList<PlaceResult>(), null), answers)
    }

    @Test fun answersComeBackThroughTheCallbacks() = runTest {
        val zones = object : TimeZoneLocator { override suspend fun zoneAt(latitude: Double, longitude: Double) = "Europe/Kyiv" }
        val answers = mutableListOf<Any?>()
        PlaceLookup(Addresses(found = listOf(place)), zones, backgroundScope).apply {
            searchAddress("Фролівська", 50.0, 30.0) { answers.add(it) }
            resolveAddress(50.0, 30.0) { answers.add(it) }
            resolveTimeZone(50.0, 30.0) { answers.add(it) }
        }
        runCurrent()
        assertEquals(listOf<Any?>(listOf(place), place, "Europe/Kyiv"), answers)
    }

    /** Пояс повільної старої крапки не перепише пояс нової: останній запит виграє. */
    @Test fun theLastTimeZoneRequestWins() = runTest {
        val zones = object : TimeZoneLocator {
            override suspend fun zoneAt(latitude: Double, longitude: Double): String {
                kotlinx.coroutines.delay(if (latitude > 0) 500 else 100)
                return if (latitude > 0) "Europe/Kyiv" else "America/Lima"
            }
        }
        val answers = mutableListOf<String?>()
        PlaceLookup(null, zones, backgroundScope).apply {
            resolveTimeZone(50.0, 30.0) { answers.add(it) }
            resolveTimeZone(-12.0, -77.0) { answers.add(it) }
        }
        advanceTimeBy(1000); runCurrent()
        assertEquals(listOf<String?>("America/Lima"), answers)
    }
}
