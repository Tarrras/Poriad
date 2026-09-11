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
            // Мапа малює індекс — усе, що є в області. Карусель і список показують картки, яких
            // може бути менше: вони приїжджають вікном. Порядок у обох один і той самий.
            copy(
                // A fresh answer means the map is showing this area now, so the prompt goes away.
                pendingArea = if (shared.index !== index) null else pendingArea,
                index = shared.index,
                totalFound = shared.totalFound,
                events = shared.events,
                cards = shared.cards,
                selectedId = shared.selectedEvent?.id,
                focused = shared.selectedEvent,
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
        // Будь-яка зміна самого результату робить фокус на точці безглуздим: у ньому лишились би
        // ідентифікатори подій, яких у видачі вже немає.
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
            // Мапа щойно відкрилася заради цієї події: стос від попереднього тапу тут ні до чого,
            // а вибір події — те, за чим мапа наведеться на неї (EventMap слухає selectedId).
            is ExploreIntent.FocusEvent -> {
                reduce { copy(stackIds = emptyList()) }
                app.selectEvent(intent.id)
            }
            is ExploreIntent.SelectStack -> {
                // Одна подія — звичайний вибір; кілька — фокус на точці, інакше решта стосу
                // лишається недосяжною з мапи.
                if (intent.ids.size <= 1) {
                    reduce { copy(stackIds = emptyList()) }
                    intent.ids.firstOrNull()?.let { app.selectEvent(it) }
                } else {
                    reduce { copy(stackIds = intent.ids) }
                    // Стос — це не початок стрічки, тож вікно його не покриває: у київському
                    // майданчику на 32 події в нього потрапляли дві.
                    app.loadCards(intent.ids)
                    app.selectEvent(intent.ids.first())
                }
            }
            ExploreIntent.ClearStack -> reduce { copy(stackIds = emptyList()) }
            is ExploreIntent.OpenEvent -> {
                app.selectEvent(intent.id)
                send(ExploreEffect.OpenDetail(intent.id))
            }
            // Довантажуємо голову **звуженого** списку: під фільтром перші події категорії
            // майже завжди лежать далі за край вікна, і `loadMore` по індексу їх не дістає.
            is ExploreIntent.LoadMore ->
                app.loadCards(state.value.visibleIndex.take(intent.upTo).map { it.id })
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
