package app.poruch.data.geo

import kotlinx.coroutines.suspendCancellableCoroutine
import platform.CoreLocation.CLGeocoder
import platform.CoreLocation.CLLocation
import platform.CoreLocation.CLPlacemark
import kotlin.coroutines.resume

/**
 * `CLGeocoder` віддає пояс місця напряму й точно — не за країною, а за самою точкою, тож працює
 * й там, де в країні поясів кілька.
 */
actual suspend fun timeZoneAt(latitude: Double, longitude: Double): String? =
    suspendCancellableCoroutine { continuation ->
        val geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(CLLocation(latitude, longitude)) { placemarks, _ ->
            val zone = placemarks?.filterIsInstance<CLPlacemark>()?.firstOrNull()?.timeZone?.name
            if (continuation.isActive) continuation.resume(zone)
        }
        continuation.invokeOnCancellation { geocoder.cancelGeocode() }
    }
