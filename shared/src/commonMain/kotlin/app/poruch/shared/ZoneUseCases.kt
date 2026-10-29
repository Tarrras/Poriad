package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * «Мої місця» (docs/my-places.md): район чи коло, гостю й акаунту однаково. Список одразу в стані й на телефоні;
 * сервер дізнається від [PushSync] разом із токеном пуша. Організатору — скільки людей поруч почують про подію.
 */
internal class ZoneUseCases(
    private val store: AppStore,
    private val library: UserLibrary,
    private val authoring: EventAuthoring,
    private val zones: ZoneStore? = null
) {
    /** Район з мапи, профілю чи онбордингу: стежити чи перестати. [from] — для аналітики. */
    fun toggleDistrict(district: District, from: String) =
        toggle(Zone.Area(district.id, district.city, district.name), from)

    /** Коло [radiusM] навколо точки; підпис — район центру. Те саме коло вдруге — нічого: «Стежити за колом» не знімає. */
    fun followCircle(latitude: Double, longitude: Double, radiusM: Int, from: String) {
        val circle = ZoneRules.circle(latitude, longitude, radiusM, store.value.city.districts)
        if (store.value.zones.none { it.key == circle.key }) toggle(circle, from)
    }

    fun remove(key: String) {
        store.value.zones.firstOrNull { it.key == key }?.let { toggle(it, "places") }
    }

    private fun toggle(zone: Zone, from: String) {
        val before = store.value.zones
        val next = ZoneRules.toggle(before, zone)
        val following = next.size > before.size || next.any { it.key == zone.key }
        zones?.saveZones(next)
        store.update { it.copy(zones = next) }
        PoruchAnalytics.track(
            if (following) "zone_follow" else "zone_unfollow",
            "kind" to if (zone is Zone.Circle) "circle" else "district", "from" to from, "zones" to next.size
        )
        // Перше стеження — та сама нагода спитати про сповіщення, що й «Стежити» за артистом: без них зона мовчить.
        if (following) library.followMade()
    }

    /** Скільки людей поруч почують про подію в точці; null — менше [ZoneRules.AUDIENCE_MIN] або не вийшло. */
    fun audience(latitude: Double, longitude: Double, onCounted: (Int?) -> Unit) {
        store.scope.launch {
            val count = try {
                authoring.zoneAudience(latitude, longitude)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("zones") { "audience failed: ${e.asAppError()}" }
                null
            }
            onCounted(count?.takeIf { it >= ZoneRules.AUDIENCE_MIN })
        }
    }
}
