package app.poruch.data.geo

import android.location.Address
import android.location.Geocoder
import android.os.Build
import app.poruch.data.AndroidStorage
import app.poruch.domain.PoruchLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * Android не має API «пояс за координатами», тому в два кроки: країна з `Geocoder`, пояси
 * країни з ICU. Для України ICU дає два (`Europe/Kyiv` і `Europe/Simferopol`), тож із кількох
 * беремо той, що збігається з поясом пристрою за правилами, а не за назвою. Не збіглося — не вгадуємо.
 */
actual suspend fun timeZoneAt(latitude: Double, longitude: Double): String? {
    val country = countryAt(latitude, longitude)
    if (country == null) {
        PoruchLog.d("geo") { "no country for $latitude,$longitude — лишаємо пояс пристрою" }
        return null
    }
    val zones = android.icu.util.TimeZone.getAvailableIDs(country)
    val zone = when {
        zones.isEmpty() -> null
        zones.size == 1 -> zones.first()
        else -> zones.firstOrNull(::sameRulesAsDevice)
    }
    // Канонічна назва ICU. На Android 16 для України це досі `Europe/Kiev`; до `Kyiv` зводить modernZoneName.
    val canonical = zone?.let { android.icu.util.TimeZone.getCanonicalID(it) ?: it }
    PoruchLog.d("geo") { "$country → ${zones.joinToString()} — chose ${canonical ?: "none"}" }
    return canonical
}

private fun sameRulesAsDevice(id: String): Boolean {
    val device = java.util.TimeZone.getDefault()
    return runCatching { java.util.TimeZone.getTimeZone(id).hasSameRules(device) }.getOrDefault(false)
}

private suspend fun countryAt(latitude: Double, longitude: Double): String? {
    val context = runCatching { AndroidStorage.context }.getOrNull() ?: return null
    if (!Geocoder.isPresent()) {
        PoruchLog.d("geo") { "geocoder unavailable on this device" }
        return null
    }
    val geocoder = Geocoder(context)
    val addresses = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            suspendCancellableCoroutine { continuation ->
                geocoder.getFromLocation(latitude, longitude, 1, object : Geocoder.GeocodeListener {
                    override fun onGeocode(results: MutableList<Address>) {
                        if (continuation.isActive) continuation.resume(results.toList())
                    }
                    override fun onError(message: String?) {
                        PoruchLog.d("geo") { "geocoder failed: ${message ?: "unknown"}" }
                        if (continuation.isActive) continuation.resume(emptyList())
                    }
                })
            }
        } else {
            // Синхронний виклик ходить у мережу, тому не на головному потоці.
            withContext(Dispatchers.IO) {
                @Suppress("DEPRECATION")
                geocoder.getFromLocation(latitude, longitude, 1).orEmpty()
            }
        }
    }.getOrDefault(emptyList())
    return addresses.firstOrNull()?.countryCode?.takeIf { it.isNotBlank() }
}
