package app.poruch.android.feature.account

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.District
import app.poruch.domain.DistrictHit
import app.poruch.domain.ZoneRules
import app.poruch.shared.AppState
import app.poruch.shared.PoruchApp

class MyPlacesViewModel(private val app: PoruchApp) :
    MviViewModel<MyPlacesState, MyPlacesIntent, MyPlacesEffect>(MyPlacesState()) {
    /** Точка в полігоні для кожної події — лише коли райони чи індекс справді інші. */
    private var ranked: Triple<List<District>, Any, List<DistrictHit>>? = null

    init {
        observe(app) { shared ->
            copy(
                zones = shared.zones, districts = shared.city.districts, city = shared.city.name,
                latitude = shared.city.latitude, longitude = shared.city.longitude,
                hits = if (addingDistrict) rank(shared) else hits
            )
        }
    }

    override fun onIntent(intent: MyPlacesIntent) {
        when (intent) {
            MyPlacesIntent.Back -> send(MyPlacesEffect.Back)
            is MyPlacesIntent.Remove -> app.removeZone(intent.key)
            is MyPlacesIntent.ShowDistricts -> reduce {
                copy(addingDistrict = intent.show, hits = if (intent.show) rank(app.state.value) else emptyList())
            }
            is MyPlacesIntent.ToggleDistrict -> app.toggleDistrictZone(intent.district, "places")
            is MyPlacesIntent.ShowCircle -> reduce { copy(pickingCircle = intent.show) }
            is MyPlacesIntent.SaveCircle -> {
                // `followCircle` — перемикач: те саме коло вдруге зняло б його, а людина просила стежити.
                val key = ZoneRules.circle(intent.latitude, intent.longitude, intent.radiusM, emptyList()).key
                if (app.state.value.zones.none { it.key == key }) app.followCircle(intent.latitude, intent.longitude, intent.radiusM, "places")
                reduce { copy(pickingCircle = false) }
            }
        }
    }

    private fun rank(shared: AppState): List<DistrictHit> {
        val districts = shared.city.districts
        val index = shared.home.index
        ranked?.let { (d, i, hits) -> if (d === districts && i === index) return hits }
        return District.ranked(districts, index).also { ranked = Triple(districts, index, it) }
    }
}
