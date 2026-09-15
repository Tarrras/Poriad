package app.poruch.android.feature.home

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.Event
import app.poruch.shared.AppState
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
        val ranked = shared.index.mapNotNull { shared.cards[it.id] }
        val suggested = shared.suggestedIndex.mapNotNull { shared.cards[it.id] }.take(SUGGESTED_LIMIT)
        // Те, що вже в «Для вас», нижче не повторюємо.
        val remaining = ranked - suggested.toSet()
        // «Сьогодні» — куди можна піти сьогодні, включно з прокатами. Але те, що сьогодні
        // починається, йде першим: прокат буде відкритий і завтра, а концерт можна пропустити.
        val (startingToday, later) = remaining.partition { it.startsOn(today) }
        val runningToday = later.filter { it.isUnderway(now) }
        val onToday = startingToday + runningToday
        return copy(
            signedIn = shared.signedIn,
            cityName = shared.cityName,
            loading = shared.loading,
            // У планах лише те, що ще не завершилось.
            plans = shared.myEvents
                .filter { it.gathering?.joined == true && it.isPublished && it.isCurrent(now) }
                .sortedBy { it.startsAt },
            suggested = suggested,
            today = onToday,
            rest = later - runningToday.toSet(),
            totalFound = shared.totalFound,
            customArea = shared.customArea,
            savedIds = shared.savedIds,
            waitlistedIds = shared.waitlistedIds,
            searchText = shared.searchText,
            results = ranked
        )
    }

    override fun onIntent(intent: HomeIntent) = when (intent) {
        is HomeIntent.OpenEvent -> {
            app.selectEvent(intent.id)
            send(HomeEffect.Navigate(HomeDestination.DETAIL, intent.id))
        }
        is HomeIntent.Search -> app.setSearchText(intent.text)
        is HomeIntent.ToggleSaved -> app.toggleSaved(intent.id)
        HomeIntent.CreateEvent -> send(HomeEffect.Navigate(HomeDestination.EDITOR))
        HomeIntent.OpenMap -> send(HomeEffect.Navigate(HomeDestination.MAP))
        HomeIntent.OpenProfile -> send(HomeEffect.Navigate(HomeDestination.PROFILE))
    }

    private fun Event.startsOn(date: LocalDate) =
        runCatching { Instant.parse(startsAt).atZone(zone).toLocalDate() == date }.getOrDefault(false)
}

/** Більше за це «для вас» перестає бути добіркою. */
private const val SUGGESTED_LIMIT = 4
