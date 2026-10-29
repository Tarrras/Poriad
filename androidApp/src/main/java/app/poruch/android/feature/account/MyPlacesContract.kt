package app.poruch.android.feature.account

import app.poruch.domain.District
import app.poruch.domain.DistrictHit
import app.poruch.domain.Zone
import app.poruch.domain.ZoneRules

/** «Мої місця» (docs/my-places.md): райони й кола, про нові зустрічі в яких скажемо пушем. */
data class MyPlacesState(
    val zones: List<Zone> = emptyList(),
    /** Райони відкритого міста: чи зона — місцевість, і що є в «Додати район». */
    val districts: List<District> = emptyList(),
    /** Райони з числами подій для шторки «Додати район»; рахуються, лише поки вона відкрита. */
    val hits: List<DistrictHit> = emptyList(),
    val city: String = "",
    /** Звідки починається коло: центр міста. */
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
    val addingDistrict: Boolean = false,
    val pickingCircle: Boolean = false
) {
    val followed: Set<Long> get() = zones.mapNotNullTo(HashSet()) { (it as? Zone.Area)?.districtId }
    val full get() = zones.size >= ZoneRules.MAX
}

sealed interface MyPlacesIntent {
    data object Back : MyPlacesIntent
    data class Remove(val key: String) : MyPlacesIntent
    data class ShowDistricts(val show: Boolean) : MyPlacesIntent
    data class ToggleDistrict(val district: District) : MyPlacesIntent
    data class ShowCircle(val show: Boolean) : MyPlacesIntent
    data class SaveCircle(val latitude: Double, val longitude: Double, val radiusM: Int) : MyPlacesIntent
}

sealed interface MyPlacesEffect {
    data object Back : MyPlacesEffect
}
