package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Підказки для редактора: адреси й пояс місця. Відповіді йдуть у колбек, а не в стан:
 * вони належать чернетці екрана. Без сервісів усе відповідає «нічого».
 */
internal class PlaceLookup(
    private val addresses: AddressSearch?,
    private val timeZones: TimeZoneLocator?,
    private val scope: CoroutineScope
) {
    /** Порожній список — просто нічого не знайшли, і збій мережі теж. */
    fun searchAddress(query: String, latitude: Double, longitude: Double, onFound: (List<PlaceResult>) -> Unit) {
        val search = addresses ?: return onFound(emptyList())
        scope.launch { onFound(quietly { search.places(query, latitude, longitude) } ?: emptyList()) }
    }

    /** Адреса поставленої крапки. Null — у полі лишається старе. */
    fun resolveAddress(latitude: Double, longitude: Double, onFound: (PlaceResult?) -> Unit) {
        val search = addresses ?: return onFound(null)
        scope.launch { onFound(quietly { search.placeAt(latitude, longitude) }) }
    }

    /** Null — не визначили, екран лишає пояс пристрою. */
    fun resolveTimeZone(latitude: Double, longitude: Double, onResolved: (String?) -> Unit) {
        val locator = timeZones ?: return onResolved(null)
        scope.launch { onResolved(locator.zoneAt(latitude, longitude)) }
    }

    private inline fun <T> quietly(block: () -> T): T? =
        try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { null }
}
