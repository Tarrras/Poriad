package app.poruch.android.feature.explore

import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.CityResult
import app.poruch.shared.DateFilter
import app.poruch.shared.ExplorePresenter
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Тонка обгортка над [ExplorePresenter]: індекс, шторку й фільтри згортає спільний код, тут — положення
 * шторки, листи, камера, дозволи й переклад інтентів у дії стору та навігацію.
 */
class ExploreViewModel(private val app: PoruchApp) :
    MviViewModel<ExploreState, ExploreIntent, ExploreEffect>(ExploreState()) {
    private val presenter = ExplorePresenter(app, viewModelScope)
    private var arrivals = 0

    init {
        viewModelScope.launch {
            presenter.state.collect { screen ->
                // Свіжа видача означає, що мапа вже показує цю область: підказка «Шукати тут» зникає.
                val freshIndex = screen.indexVersion != state.value.screen.indexVersion
                // «Усі N» з головної: камера, шторки й «Шукати тут» — з чистого аркуша. Стос і плитки скинув презентер.
                // Перше значення — те, що було до моделі (свіжа модель уже чиста).
                val arrived = arrivals != 0 && screen.arrivals != arrivals
                arrivals = screen.arrivals
                reduce {
                    if (arrived) copy(
                        screen = screen, detent = SheetDetent.PEEK, sheet = ExploreSheet.NONE,
                        pendingArea = null, recenterToken = recenterToken + 1
                    ) else copy(screen = screen, pendingArea = if (freshIndex) null else pendingArea)
                }
            }
        }
    }

    private val screen get() = state.value.screen

    override fun onIntent(intent: ExploreIntent) {
        // Пошук, область і місто виводять із закладу в місто. Фільтри — ні: вони звужують його події (див. ExplorePresenter).
        when (intent) {
            is ExploreIntent.Search, ExploreIntent.SearchHere,
            ExploreIntent.Recenter, is ExploreIntent.SelectCity -> presenter.resetStack()
            else -> Unit
        }
        when (intent) {
            is ExploreIntent.Search -> app.setSearchText(intent.text)
            is ExploreIntent.PickDate -> app.setDateFilter(intent.filter)
            is ExploreIntent.PickCategory -> app.setCategory(intent.category)
            is ExploreIntent.OnlyAvailable -> app.setOnlyAvailable(intent.value)
            ExploreIntent.ResetFilters -> {
                val before = FilterSnapshot(screen.dateFilter, screen.category, screen.onlyAvailable)
                apply(FilterSnapshot(DateFilter.ANY, null, false))
                reduce { copy(undoFilters = before) }
                viewModelScope.launch {
                    delay(UNDO_MS)
                    reduce { if (undoFilters === before) copy(undoFilters = null) else this }
                }
            }
            ExploreIntent.UndoReset -> state.value.undoFilters?.let { before ->
                reduce { copy(undoFilters = null) }
                apply(before)
            }

            is ExploreIntent.AreaMoved -> reduce { copy(pendingArea = intent.area) }
            is ExploreIntent.Viewport -> intent.area.let { presenter.viewport(it.south, it.west, it.north, it.east) }
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
            // Мапу відкрили заради цієї події: шторки й стос закриваємо, щоб видно було пін і карусель на ній.
            is ExploreIntent.FocusEvent -> {
                reduce { copy(detent = SheetDetent.PEEK, sheet = ExploreSheet.NONE) }
                presenter.focusEvent(intent.id)
            }
            is ExploreIntent.SelectStack -> presenter.showStack(intent.ids)
            // Шторку опускаємо: людина хоче бачити заклад на мапі.
            is ExploreIntent.FocusPlace -> {
                reduce { copy(detent = SheetDetent.PEEK, sheet = ExploreSheet.NONE) }
                presenter.focusPlace(intent.place)
            }
            is ExploreIntent.OpenArtist -> {
                app.openArtist(intent.artist.id, intent.artist.name, intent.artist.kind)
                send(ExploreEffect.OpenArtist(intent.artist.id))
            }
            ExploreIntent.ClearStack -> presenter.clearStack()
            ExploreIntent.ToggleFollowStack -> if (!presenter.toggleFollowStack()) send(ExploreEffect.SignIn)
            is ExploreIntent.OpenEvent -> {
                app.selectEvent(intent.id)
                send(ExploreEffect.OpenDetail(intent.id))
            }
            // Довантажуємо голову звуженого списку: `loadMore` по індексу під фільтром її не дістає.
            is ExploreIntent.LoadMore -> presenter.loadHead(intent.upTo)
            is ExploreIntent.ToggleSaved -> app.toggleSaved(intent.id)
            ExploreIntent.CreateEvent -> { app.createStarted("map"); send(ExploreEffect.CreateEvent) }

            is ExploreIntent.ShowSheet -> reduce { copy(sheet = intent.sheet) }
            is ExploreIntent.SetDetent -> reduce { copy(detent = intent.detent) }
            is ExploreIntent.ToggleCategory -> presenter.toggleCategory(intent.category)

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

    /** Лише те, що відрізняється: кожен зайвий виклик — ще один запит до сервера. */
    private fun apply(target: FilterSnapshot) {
        if (screen.dateFilter != target.date) app.setDateFilter(target.date)
        if (screen.category != target.category) app.setCategory(target.category)
        if (screen.onlyAvailable != target.available) app.setOnlyAvailable(target.available)
    }

    private companion object {
        /** Скільки висить «Фільтри скинуто · Повернути». */
        const val UNDO_MS = 6_000L
    }
}
