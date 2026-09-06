package app.poruch.android.feature.explore

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.CityResult
import app.poruch.shared.ALL_CATEGORIES
import app.poruch.shared.DateFilter
import app.poruch.shared.PoruchApp

class ExploreViewModel(private val app: PoruchApp) :
    MviViewModel<ExploreState, ExploreIntent, ExploreEffect>(ExploreState()) {

    init {
        observe(app) { shared ->
            copy(
                // A fresh answer means the map is showing this area now, so the prompt goes away.
                pendingArea = if (shared.events !== events) null else pendingArea,
                events = shared.events,
                selectedId = shared.selectedEvent?.id,
                savedIds = shared.savedIds,
                waitlistedIds = shared.waitlistedIds,
                cityName = shared.cityName,
                cityLatitude = shared.cityLatitude,
                cityLongitude = shared.cityLongitude,
                cities = shared.cities,
                searchText = shared.searchText,
                category = shared.category,
                dateFilter = shared.dateFilter,
                onlyAvailable = shared.onlyAvailable,
                loading = shared.loading,
                offline = shared.offline
            )
        }
    }

    override fun onIntent(intent: ExploreIntent) {
        when (intent) {
            is ExploreIntent.Search -> app.setSearchText(intent.text)
            is ExploreIntent.PickDate -> app.setDateFilter(intent.filter)
            is ExploreIntent.PickCategory -> app.setCategory(intent.category)
            is ExploreIntent.OnlyAvailable -> app.setOnlyAvailable(intent.value)
            ExploreIntent.ResetFilters -> {
                app.setDateFilter(DateFilter.ANY); app.setCategory(ALL_CATEGORIES); app.setOnlyAvailable(false)
            }

            is ExploreIntent.AreaMoved -> reduce { copy(pendingArea = intent.area) }
            ExploreIntent.SearchHere -> {
                state.value.pendingArea?.let { app.searchArea(it.south, it.west, it.north, it.east) }
                reduce { copy(pendingArea = null) }
            }
            ExploreIntent.Recenter -> {
                app.dismissEvent()
                reduce { copy(recenterToken = recenterToken + 1) }
            }
            is ExploreIntent.MapFailed -> reduce { copy(mapFailed = intent.failed) }

            is ExploreIntent.SelectEvent -> app.selectEvent(intent.id)
            is ExploreIntent.OpenEvent -> {
                app.selectEvent(intent.id)
                send(ExploreEffect.OpenDetail(intent.id))
            }
            is ExploreIntent.ToggleSaved -> app.toggleSaved(intent.id)
            ExploreIntent.CreateEvent -> send(ExploreEffect.CreateEvent)

            is ExploreIntent.ShowSheet -> reduce { copy(sheet = intent.sheet) }
            is ExploreIntent.ListMode -> reduce { copy(listMode = intent.value) }

            is ExploreIntent.SearchCity -> app.searchCity(intent.query)
            is ExploreIntent.SelectCity -> {
                app.selectCity(intent.city)
                reduce { copy(sheet = ExploreSheet.NONE) }
            }
            ExploreIntent.RequestLocation -> {
                reduce { copy(locationDenied = false) }
                send(ExploreEffect.AskLocationPermission)
            }
            is ExploreIntent.LocatedAt -> app.selectCity(CityResult(intent.name, intent.latitude, intent.longitude))
            ExploreIntent.LocationDenied -> reduce { copy(locationDenied = true) }
        }
    }
}
