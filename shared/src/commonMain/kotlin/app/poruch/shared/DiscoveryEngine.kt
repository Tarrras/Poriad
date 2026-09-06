package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.datetime.*
import kotlin.math.abs
import kotlin.time.Clock

/**
 * Owns the map query: where we are looking, what we are filtering by, and the one in-flight search.
 * Split out of [PoruchApp] because these are the only pieces of state that change on every pan of
 * the map, and keeping them together is what makes "a stale answer must not replace a fresh one"
 * checkable in one place.
 */
internal class DiscoveryEngine(
    private val events: EventRepository,
    private val geo: GeoSearchRepository,
    private val state: MutableStateFlow<AppState>,
    private val scope: CoroutineScope,
    home: HomeLocation
) {
    private var query = EventQuery(home.south, home.west, home.north, home.east)
    private var searchJob: Job? = null
    private var debounceJob: Job? = null
    private var cityJob: Job? = null

    /** Called whenever a query change should also drop the open event card. */
    var onQueryChanged: () -> Unit = {}

    fun refresh() {
        searchJob?.cancel()
        val snapshot = query
        searchJob = scope.launch {
            state.update { it.copy(loading = true) }
            PoruchLog.d("discovery") {
                "search ${snapshot.south},${snapshot.west}..${snapshot.north},${snapshot.east} " +
                    "category=${snapshot.category ?: ALL_CATEGORIES} from=${snapshot.from ?: "now"} " +
                    "text=${if (snapshot.text.isNullOrBlank()) "-" else "yes"} available=${snapshot.available}"
            }
            try {
                val result = events.discover(snapshot)
                PoruchLog.i("discovery") { "${result.size} events" }
                state.update {
                    it.copy(
                        events = result, loading = false, offline = false,
                        notice = if (result.size >= DiscoveryRules.RESULT_CAP) AppNotice.Told(AppMessage.ZOOM_IN_FOR_MORE) else it.notice
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Offline is not empty: the last answer for this area is still the best one we have.
                val cached = events.cached(snapshot)
                PoruchLog.w("discovery") { "offline, showing ${cached.size} cached events" }
                state.update { it.copy(events = cached, loading = false, offline = true, notice = AppNotice.Failed(e.asAppError())) }
            }
        }
    }

    fun searchArea(south: Double, west: Double, north: Double, east: Double) {
        if (listOf(south, west, north, east).any { !it.isFinite() } || south > north) return
        // Map SDKs can return unwrapped longitudes after panning across the dateline.
        fun longitude(value: Double) = ((value + 180.0) % 360.0 + 360.0) % 360.0 - 180.0
        val wholeWorld = abs(east - west) >= 360.0
        query = query.copy(
            south = south.coerceIn(-90.0, 90.0), west = if (wholeWorld) -180.0 else longitude(west),
            north = north.coerceIn(-90.0, 90.0), east = if (wholeWorld) 180.0 else longitude(east)
        )
        onQueryChanged(); refresh()
    }

    fun setSearchText(text: String) {
        val trimmed = text.take(DiscoveryRules.SEARCH_TEXT_LIMIT)
        if (trimmed == state.value.searchText) return
        state.update { it.copy(searchText = trimmed, loading = true) }
        query = query.copy(text = trimmed.trim().takeIf { it.isNotEmpty() })
        debounceJob?.cancel(); searchJob?.cancel(); onQueryChanged()
        debounceJob = scope.launch { delay(DiscoveryRules.SEARCH_DEBOUNCE_MS); refresh() }
    }

    fun setOnlyAvailable(available: Boolean) {
        state.update { it.copy(onlyAvailable = available) }
        query = query.copy(available = available); onQueryChanged(); refresh()
    }

    fun setCategory(category: String) {
        state.update { it.copy(category = category) }
        query = query.copy(category = category.takeUnless { it == ALL_CATEGORIES })
        onQueryChanged(); refresh()
    }

    fun setDateFilter(filter: String) {
        val zone = TimeZone.currentSystemDefault()
        val now = Clock.System.now()
        val today = now.toLocalDateTime(zone).date
        // The weekend runs from Saturday 00:00 to Monday 00:00, however far away it currently is.
        val daysToSaturday = (6 - today.dayOfWeek.isoDayNumber).coerceAtLeast(0)
        val start = when (filter) {
            DateFilter.TODAY -> today.atStartOfDayIn(zone)
            DateFilter.WEEKEND -> today.plus(daysToSaturday, DateTimeUnit.DAY).atStartOfDayIn(zone)
            else -> now
        }
        val end = when (filter) {
            DateFilter.TODAY -> today.plus(1, DateTimeUnit.DAY).atStartOfDayIn(zone)
            DateFilter.WEEKEND -> today.plus(8 - today.dayOfWeek.isoDayNumber, DateTimeUnit.DAY).atStartOfDayIn(zone)
            else -> null
        }
        state.update { it.copy(dateFilter = filter) }
        query = query.copy(from = start.toString(), to = end?.toString())
        refresh()
    }

    fun searchCity(text: String) {
        cityJob?.cancel()
        if (text.trim().length < DiscoveryRules.MIN_CITY_QUERY) {
            state.update { it.copy(cities = emptyList()) }
            return
        }
        cityJob = scope.launch {
            delay(DiscoveryRules.CITY_DEBOUNCE_MS)
            try {
                val result = geo.search(text)
                PoruchLog.d("geo") { "city suggestions: ${result.size}" }
                state.update { it.copy(cities = result) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                state.update { it.copy(notice = AppNotice.Failed(e.asAppError())) }
            }
        }
    }

    fun selectCity(city: CityResult) {
        PoruchLog.i("discovery") { "city → ${city.name}" }
        state.update {
            it.copy(cityName = city.name, cityLatitude = city.latitude, cityLongitude = city.longitude, cities = emptyList())
        }
        val view = HomeLocation(city.name, city.latitude, city.longitude)
        searchArea(view.south, view.west, view.north, view.east)
    }
}
