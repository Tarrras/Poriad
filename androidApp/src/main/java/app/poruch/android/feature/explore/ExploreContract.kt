package app.poruch.android.feature.explore

import app.poruch.domain.CityResult
import app.poruch.domain.Event
import app.poruch.shared.ALL_CATEGORIES
import app.poruch.shared.DateFilter

data class ExploreState(
    val events: List<Event> = emptyList(),
    val selectedId: String? = null,
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    val cityName: String = "",
    val cityLatitude: Double = 0.0,
    val cityLongitude: Double = 0.0,
    val cities: List<CityResult> = emptyList(),
    val searchText: String = "",
    val category: String = ALL_CATEGORIES,
    val dateFilter: String = DateFilter.ANY,
    val onlyAvailable: Boolean = false,
    val loading: Boolean = false,
    val offline: Boolean = false,
    // ---- local to this screen
    val listMode: Boolean = false,
    val sheet: ExploreSheet = ExploreSheet.NONE,
    /** Set once the camera moved: the map holds results until the reader asks to search here. */
    val pendingArea: Area? = null,
    val locationDenied: Boolean = false,
    val mapFailed: Boolean = false,
    /** Bumped to ask the map to fly back to the city centre. */
    val recenterToken: Int = 0
) {
    val activeFilters get() =
        listOf(dateFilter != DateFilter.ANY, category != ALL_CATEGORIES, onlyAvailable).count { it }
}

data class Area(val south: Double, val west: Double, val north: Double, val east: Double)

enum class ExploreSheet { NONE, FILTERS, CITY }

sealed interface ExploreIntent {
    data class Search(val text: String) : ExploreIntent
    data class PickDate(val filter: String) : ExploreIntent
    data class PickCategory(val category: String) : ExploreIntent
    data class OnlyAvailable(val value: Boolean) : ExploreIntent
    data object ResetFilters : ExploreIntent

    data class AreaMoved(val area: Area?) : ExploreIntent
    data object SearchHere : ExploreIntent
    data object Recenter : ExploreIntent
    data class MapFailed(val failed: Boolean) : ExploreIntent

    data class SelectEvent(val id: String) : ExploreIntent
    data class OpenEvent(val id: String) : ExploreIntent
    data class ToggleSaved(val id: String) : ExploreIntent
    data object CreateEvent : ExploreIntent

    data class ShowSheet(val sheet: ExploreSheet) : ExploreIntent
    data class ListMode(val value: Boolean) : ExploreIntent

    data class SearchCity(val query: String) : ExploreIntent
    data class SelectCity(val city: CityResult) : ExploreIntent
    data object RequestLocation : ExploreIntent
    data class LocatedAt(val name: String, val latitude: Double, val longitude: Double) : ExploreIntent
    data object LocationDenied : ExploreIntent
}

sealed interface ExploreEffect {
    data class OpenDetail(val id: String) : ExploreEffect
    data object CreateEvent : ExploreEffect
    data object AskLocationPermission : ExploreEffect
}
