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
            // Мапа малює індекс, карусель і список — картки, яких може бути менше.
            copy(
                // Свіжа відповідь означає, що мапа вже показує цю область: підказка зникає.
                pendingArea = if (shared.map.index !== index) null else pendingArea,
                index = shared.map.index,
                totalFound = shared.map.totalFound,
                events = shared.map.events,
                cards = shared.cards,
                selectedId = shared.detail.event?.id,
                focused = shared.detail.event,
                savedIds = shared.library.savedIds,
                waitlistedIds = shared.library.waitlistedIds,
                cityName = shared.city.name,
                cityLatitude = shared.city.latitude,
                cityLongitude = shared.city.longitude,
                cities = shared.city.suggestions,
                searchText = shared.map.searchText,
                category = shared.map.category,
                dateFilter = shared.map.dateFilter,
                onlyAvailable = shared.map.onlyAvailable,
                loading = shared.map.loading,
                offline = shared.map.offline,
                customArea = shared.city.custom
            )
        }
    }

    override fun onIntent(intent: ExploreIntent) {
        // Зміна результату скидає фокус на точці: у ньому лишились би id подій, яких уже нема.
        when (intent) {
            is ExploreIntent.Search, is ExploreIntent.PickDate, is ExploreIntent.PickCategory,
            is ExploreIntent.OnlyAvailable, ExploreIntent.ResetFilters, ExploreIntent.SearchHere,
            ExploreIntent.Recenter, is ExploreIntent.SelectCity ->
                reduce { copy(stackIds = emptyList()) }
            else -> Unit
        }
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
            // Мапу відкрили заради цієї події: шторки й стос закриваємо, щоб видно було пін і карусель
            // на ній; плитки категорій теж скидаємо, інакше картки в каруселі могло не бути.
            // Вибір наводить мапу (EventMap слухає selectedId).
            is ExploreIntent.FocusEvent -> {
                reduce {
                    copy(stackIds = emptyList(), detent = SheetDetent.PEEK, sheet = ExploreSheet.NONE, listCategory = ALL_CATEGORIES)
                }
                app.selectEvent(intent.id)
            }
            is ExploreIntent.SelectStack -> {
                // Одна подія — звичайний вибір; кілька — стос.
                if (intent.ids.size <= 1) {
                    reduce { copy(stackIds = emptyList()) }
                    intent.ids.firstOrNull()?.let { app.selectEvent(it) }
                } else {
                    reduce { copy(stackIds = intent.ids) }
                    // Стос — не початок стрічки, вікно його не покриває.
                    app.loadCards(intent.ids)
                    app.selectEvent(intent.ids.first())
                }
            }
            // Знімає і підсвітку піна, інакше мапа й список розходились.
            ExploreIntent.ClearStack -> {
                reduce { copy(stackIds = emptyList()) }
                app.dismissEvent()
            }
            is ExploreIntent.OpenEvent -> {
                app.selectEvent(intent.id)
                send(ExploreEffect.OpenDetail(intent.id))
            }
            // Довантажуємо голову звуженого списку: `loadMore` по індексу під фільтром її не дістає.
            is ExploreIntent.LoadMore -> loadHead(intent.upTo)
            is ExploreIntent.ToggleSaved -> app.toggleSaved(intent.id)
            ExploreIntent.CreateEvent -> send(ExploreEffect.CreateEvent)

            is ExploreIntent.ShowSheet -> reduce { copy(sheet = intent.sheet) }
            is ExploreIntent.SetDetent -> reduce { copy(detent = intent.detent) }
            is ExploreIntent.PickListCategory -> {
                reduce { copy(listCategory = if (listCategory == intent.category) ALL_CATEGORIES else intent.category) }
                // Голова нового списку майже напевно ще не завантажена.
                loadHead(PAGE)
            }

            is ExploreIntent.SearchCity -> app.searchCity(intent.query)
            is ExploreIntent.SelectCity -> {
                app.selectCity(intent.city)
                reduce { copy(sheet = ExploreSheet.NONE) }
            }
            ExploreIntent.RequestLocation -> {
                reduce { copy(locationDenied = false) }
                send(ExploreEffect.AskLocationPermission)
            }
            is ExploreIntent.LocatedAt -> app.followLocation(CityResult(intent.name, intent.latitude, intent.longitude))
            ExploreIntent.LocationDenied -> reduce { copy(locationDenied = true) }
        }
    }

    /** Картки початку того списку, який шторка зараз показує. */
    private fun loadHead(count: Int) {
        val ids = state.value.listEntries.take(count).map { it.id }
        if (ids.isNotEmpty()) app.loadCards(ids)
    }
}
