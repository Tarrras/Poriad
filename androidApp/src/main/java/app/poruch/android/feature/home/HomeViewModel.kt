package app.poruch.android.feature.home

import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.HomeRules
import app.poruch.shared.HomePresenter
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.launch

/**
 * Тонка обгортка над [HomePresenter]: списки головної складає спільний код раз на зміну входів, тут —
 * локальний стан екрана (режим пошуку, ліміти, листи) і переклад інтентів у дії стору та навігацію.
 */
class HomeViewModel(private val app: PoruchApp) : MviViewModel<HomeState, HomeIntent, HomeEffect>(HomeState()) {
    private val presenter = HomePresenter(app, viewModelScope)

    init {
        viewModelScope.launch { presenter.state.collect { screen -> reduce { copy(screen = screen) } } }
    }

    override fun onIntent(intent: HomeIntent) = when (intent) {
        is HomeIntent.OpenEvent -> {
            app.selectEvent(intent.id, intent.from)
            send(HomeEffect.Navigate(HomeDestination.DETAIL, intent.id))
        }
        is HomeIntent.OpenPlace -> {
            app.focusPlace(intent.place)
            send(HomeEffect.Navigate(HomeDestination.MAP))
        }
        is HomeIntent.OpenArtist -> {
            app.openArtist(intent.artist.id, intent.artist.name, intent.artist.kind)
            send(HomeEffect.Navigate(HomeDestination.ARTIST, intent.artist.id))
        }
        is HomeIntent.OpenChat -> {
            app.selectEvent(intent.id)
            send(HomeEffect.Navigate(HomeDestination.CHAT, intent.id))
        }
        HomeIntent.EnterSearch -> reduce { copy(searchMode = true) }
        HomeIntent.CancelSearch -> {
            reduce { copy(searchMode = false, resultsLimit = RESULTS_PAGE) }
            app.cancelHomeSearch()
        }
        // Нова видача — знову з першої сторінки.
        is HomeIntent.Search -> { firstPage(); app.setHomeSearchText(intent.text) }
        is HomeIntent.SearchEverywhere -> { firstPage(); app.setHomeSearchEverywhere(intent.everywhere) }
        is HomeIntent.SearchCategory -> { firstPage(); app.setHomeSearchCategory(intent.category) }
        is HomeIntent.SearchDate -> { firstPage(); app.setHomeSearchDate(intent.filter) }
        HomeIntent.ShowMoreResults -> {
            val limit = state.value.resultsLimit + RESULTS_PAGE
            reduce { copy(resultsLimit = limit) }
            // Спільний код везе картки лише початку видачі; решту просимо шматками. Відомі він пропустить сам.
            app.loadCards(state.value.screen.resultIds.take(limit))
        }
        is HomeIntent.SwitchCity -> {
            // Спершу текст: інакше назва міста лишилася б фільтром і в новому місті.
            app.setHomeSearchText("")
            reduce { copy(citySheet = false) }
            app.selectCity(intent.city)
        }
        is HomeIntent.ShowCitySheet -> reduce { copy(citySheet = intent.show) }
        is HomeIntent.SearchCity -> app.searchCity(intent.query)
        is HomeIntent.ToggleSaved -> app.toggleSaved(intent.id)
        HomeIntent.ShowMoreFeed -> reduce { copy(feedLimit = feedLimit + HomeRules.FEED_PAGE) }
        // Чип міняє сітку, а її збирає презентер: він і перезбере.
        is HomeIntent.SelectFeedFilter -> {
            reduce { copy(feedLimit = HomeRules.FEED_PAGE) }
            presenter.selectFeedFilter(intent.filter)
        }
        is HomeIntent.CreateEvent -> {
            app.createStarted(intent.from)
            send(HomeEffect.Navigate(HomeDestination.EDITOR))
        }
        HomeIntent.OpenMap -> send(HomeEffect.Navigate(HomeDestination.MAP))
        HomeIntent.ShowPeopleOnMap -> { app.showPeopleOnMap(); send(HomeEffect.Navigate(HomeDestination.MAP)) }
        HomeIntent.ShowEverythingOnMap -> { app.showEverythingOnMap(); send(HomeEffect.Navigate(HomeDestination.MAP)) }
        HomeIntent.ShowResultsOnMap -> {
            app.setSearchText(state.value.screen.searchText)
            send(HomeEffect.Navigate(HomeDestination.MAP))
        }
        HomeIntent.OpenProfile -> send(HomeEffect.Navigate(HomeDestination.PROFILE))
        HomeIntent.OpenMyEvents -> send(HomeEffect.Navigate(HomeDestination.MINE))
        HomeIntent.OpenFollows -> send(HomeEffect.Navigate(HomeDestination.FOLLOWS))
        HomeIntent.Refresh -> refresh({ refreshing }, { copy(refreshing = it) }) { app.reloadAll() }
    }

    private fun firstPage() = reduce { copy(resultsLimit = RESULTS_PAGE) }
}
