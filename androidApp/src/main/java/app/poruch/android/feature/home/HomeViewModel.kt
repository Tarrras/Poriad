package app.poruch.android.feature.home

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.Event
import app.poruch.domain.FeedFilter
import app.poruch.domain.HomeLocation
import app.poruch.domain.HomeRules
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

    /** Дві зони головної. Власного фільтра категорій у неї нема: каталог живе на мапі. */
    private fun HomeState.fold(shared: AppState): HomeState {
        val now = Clock.System.now()
        val zoneId = zone.id
        val today = LocalDate.now(zone)
        // Увесь екран в одному порядку — ранжованому.
        // Своя стрічка: та сама область, що на мапі, але без її фільтрів.
        // Картки до індексу прив'язує спільний код: тут лише завантажені, а не тисячі записів.
        val home = shared.home
        val ranked = home.events
        val suggested = home.suggested.take(SUGGESTED_LIMIT)
        // Те, що вже в «Для вас», у списку міста не повторюємо.
        val remaining = ranked - suggested.toSet()
        // Місто: куди можна піти сьогодні, включно з прокатами, далі решта за рангом. Але те, що сьогодні
        // починається, йде першим: прокат буде відкритий і завтра, а концерт можна пропустити.
        val (startingToday, later) = remaining.partition { it.startsOn(today) }
        val runningToday = later.filter { it.isUnderway(now) }
        val city = startingToday + runningToday + (later - runningToday.toSet())
        // Стрічка приїхала з сервера, а події за час у застосунку встигають скінчитись.
        val followed = shared.library.followEvents.filter { it.isPublished && it.isCurrent(now) }

        // «Ваше»: чат із непрочитаним (навіть минулої події) і запити чекають на людину, тож вони першими.
        val mine = shared.library.myEvents.associateBy { it.id }
        val plans = shared.library.myEvents.filter { shared.concerns(it) && it.isPublished && it.isCurrent(now) }.sortedBy { it.startsAt }
        val chats = shared.chatUnread.associateBy { it.eventId }
        val asks = RequestRules.pendingByEvent(shared.library.pendingRequests)
        val waiting = shared.chatUnread.mapNotNull { mine[it.eventId] } + asks.keys.mapNotNull { mine[it] }.filter { it.isCurrent(now) }
        val mineFirst = (waiting + plans).distinctBy { it.id }
        val personal = mineFirst.take(HomeRules.PERSONAL_LIMIT)
            .map { PersonalRow(it, chats[it.id], asks[it.id] ?: 0, shared.organizes(it)) }
        val shown = personal.mapTo(HashSet()) { it.event.id }
        // Усі свої плани, а не лише три з «Ваше»: решта живе в «Моїх подіях», а в місті стояла б безіменним постером.
        val mineIds = mineFirst.mapTo(HashSet()) { it.id }
        val people = HomeRules.people(suggested, city, followed, mineIds)
        // Кімнати, що дістали власну секцію, у стрічці не повторюємо й уперед їх більше не ставимо.
        val all = HomeRules.feed(suggested, city, followed, mineIds + people.map { it.event.id }, roomsFirst = people.isEmpty())
        val rest = all.drop(HomeRules.HERO_COUNT)
        val chips = HomeRules.chips(rest, now, zoneId)
        val filter = feedFilter.takeIf { it in chips } ?: FeedFilter()
        return copy(
            signedIn = shared.signedIn,
            cityName = shared.city.name,
            cities = shared.city.suggestions,
            loading = home.loading,
            personal = personal,
            moreWaiting = waiting.mapTo(HashSet()) { it.id }.count { it !in shown },
            people = people,
            followed = followed,
            feed = all.take(HomeRules.HERO_COUNT) + HomeRules.apply(rest, filter, now, zoneId),
            chips = chips,
            feedFilter = filter,
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
            app.selectEvent(intent.id, intent.from)
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
            reduce { copy(citySheet = false) }
            app.selectCity(intent.city)
        }
        is HomeIntent.ShowCitySheet -> reduce { copy(citySheet = intent.show) }
        is HomeIntent.SearchCity -> app.searchCity(intent.query)
        is HomeIntent.ToggleSaved -> app.toggleSaved(intent.id)
        HomeIntent.ShowMoreFeed -> reduce { copy(feedLimit = feedLimit + HomeRules.FEED_PAGE) }
        // Чип міняє й сітку, а її збирає `fold`: перезбираємо зі свіжого спільного стану.
        is HomeIntent.SelectFeedFilter -> reduce { copy(feedFilter = intent.filter, feedLimit = HomeRules.FEED_PAGE).fold(app.state.value) }
        is HomeIntent.CreateEvent -> {
            app.createStarted(intent.from)
            send(HomeEffect.Navigate(HomeDestination.EDITOR))
        }
        HomeIntent.OpenMap -> send(HomeEffect.Navigate(HomeDestination.MAP))
        HomeIntent.ShowResultsOnMap -> {
            app.setSearchText(state.value.searchText)
            send(HomeEffect.Navigate(HomeDestination.MAP))
        }
        HomeIntent.OpenProfile -> send(HomeEffect.Navigate(HomeDestination.PROFILE))
        HomeIntent.OpenMyEvents -> send(HomeEffect.Navigate(HomeDestination.MINE))
        HomeIntent.OpenFollows -> send(HomeEffect.Navigate(HomeDestination.FOLLOWS))
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

    private fun Event.startsOn(date: LocalDate) =
        runCatching { Instant.parse(startsAt).atZone(zone).toLocalDate() == date }.getOrDefault(false)
}

/** Більше за це «для вас» перестає бути добіркою. */
private const val SUGGESTED_LIMIT = 4
