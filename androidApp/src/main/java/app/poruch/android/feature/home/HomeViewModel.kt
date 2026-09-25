package app.poruch.android.feature.home

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.CityResult
import app.poruch.domain.Event
import app.poruch.domain.HomeLocation
import app.poruch.domain.RequestRules
import app.poruch.shared.AppState
import app.poruch.shared.HomeFeed
import app.poruch.shared.PoruchApp
import kotlin.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Складає списки головної зі спільного стору тут, а не в композиції, щоб не рахувати на кожну рекомпозицію. */
class HomeViewModel(private val app: PoruchApp) : MviViewModel<HomeState, HomeIntent, HomeEffect>(HomeState()) {
    private val zone: ZoneId = ZoneId.systemDefault()

    init {
        observe(app) { shared -> fold(shared) }
    }

    /** Три списки головної. Власного фільтра категорій у неї нема: каталог живе на мапі. */
    private fun HomeState.fold(shared: AppState): HomeState {
        val now = Clock.System.now()
        val today = LocalDate.now(zone)
        // Увесь екран в одному порядку — ранжованому.
        // Своя стрічка: та сама область, що на мапі, але без її фільтрів.
        // Картки до індексу прив'язує спільний код: тут лише завантажені, а не тисячі записів.
        val home = shared.home
        val ranked = home.events
        val suggested = home.suggested.take(SUGGESTED_LIMIT)
        // Те, що вже в «Для вас», нижче не повторюємо.
        val remaining = ranked - suggested.toSet()
        // «Сьогодні» — куди можна піти сьогодні, включно з прокатами. Але те, що сьогодні
        // починається, йде першим: прокат буде відкритий і завтра, а концерт можна пропустити.
        val (startingToday, later) = remaining.partition { it.startsOn(today) }
        val runningToday = later.filter { it.isUnderway(now) }
        val onToday = startingToday + runningToday
        return copy(
            signedIn = shared.signedIn,
            cityName = shared.city.name,
            loading = home.loading,
            // У планах лише те, що ще не завершилось: і свої, і ті, куди йду.
            plans = shared.library.myEvents
                .filter { shared.concerns(it) && it.isPublished && it.isCurrent(now) }
                .sortedBy { it.startsAt },
            requests = pendingRequests(shared),
            unread = shared.chatUnread,
            suggested = suggested,
            today = onToday,
            rest = later - runningToday.toSet(),
            totalFound = home.totalFound,
            savedIds = shared.library.savedIds,
            waitlistedIds = shared.library.waitlistedIds,
            searchText = home.searchText,
            results = inOrder(home),
            resultsIndexed = home.results.size,
            resultsTotal = home.resultsTotal,
            places = home.places,
            searchLoading = home.searchLoading,
            searchEverywhere = home.searchEverywhere,
            searchCategory = home.searchCategory,
            searchDate = home.searchDate,
            // Пошук усюди вже бачить інші міста: підказка «лише в межах міста» була б неправдою.
            cityMatch = if (home.searching && !home.searchEverywhere) HomeLocation.mentioned(home.searchText, shared.city.name) else null
        )
    }

    override fun onIntent(intent: HomeIntent) = when (intent) {
        is HomeIntent.OpenEvent -> {
            app.selectEvent(intent.id)
            send(HomeEffect.Navigate(HomeDestination.DETAIL, intent.id))
        }
        is HomeIntent.OpenPlace -> {
            app.focusPlace(intent.place)
            send(HomeEffect.Navigate(HomeDestination.MAP))
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
            app.loadCards(app.state.value.home.results.take(limit).map { it.id })
        }
        is HomeIntent.SwitchCity -> {
            // Спершу текст: інакше назва міста лишилася б фільтром і в новому місті.
            app.setHomeSearchText("")
            app.selectCity(CityResult(intent.city.city, intent.city.latitude, intent.city.longitude))
        }
        is HomeIntent.ToggleSaved -> app.toggleSaved(intent.id)
        HomeIntent.CreateEvent -> send(HomeEffect.Navigate(HomeDestination.EDITOR))
        HomeIntent.OpenMap -> send(HomeEffect.Navigate(HomeDestination.MAP))
        HomeIntent.ShowResultsOnMap -> {
            app.setSearchText(state.value.searchText)
            send(HomeEffect.Navigate(HomeDestination.MAP))
        }
        is HomeIntent.OpenCategory -> {
            app.setCategory(intent.category)
            send(HomeEffect.Navigate(HomeDestination.MAP))
        }
        HomeIntent.OpenProfile -> send(HomeEffect.Navigate(HomeDestination.PROFILE))
        HomeIntent.Refresh -> refresh({ refreshing }, { copy(refreshing = it) }) { app.reloadAll() }
    }

    private fun firstPage() = reduce { copy(resultsLimit = RESULTS_PAGE) }

    /**
     * Картки видачі в її порядку, до першої, що ще їде: [HomeFeed.found] її пропускає,
     * і після довантаження нижні картки стрибали б.
     */
    private fun inOrder(home: HomeFeed): List<Event> {
        val cards = home.found.associateBy { it.id }
        val shown = ArrayList<Event>(home.found.size)
        for (entry in home.results) shown += cards[entry.id] ?: break
        return shown
    }

    /** Запити за подіями, у порядку стрічки (свіжіші першими). Подія без картки в «моїх» пропускається. */
    private fun pendingRequests(shared: AppState): List<PendingRequests> {
        if (shared.library.pendingRequests.isEmpty()) return emptyList()
        val counts = RequestRules.pendingByEvent(shared.library.pendingRequests)
        val cards = shared.library.myEvents.associateBy { it.id }
        return shared.library.pendingRequests.map { it.eventId }.distinct()
            .mapNotNull { id -> cards[id]?.let { PendingRequests(it, counts.getValue(id)) } }
    }

    private fun Event.startsOn(date: LocalDate) =
        runCatching { Instant.parse(startsAt).atZone(zone).toLocalDate() == date }.getOrDefault(false)
}

/** Більше за це «для вас» перестає бути добіркою. */
private const val SUGGESTED_LIMIT = 4
