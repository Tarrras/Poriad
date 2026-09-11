package app.poruch.android.feature.home

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.Event
import app.poruch.domain.EventIndexEntry
import app.poruch.shared.ALL_CATEGORIES
import app.poruch.shared.AppState
import app.poruch.shared.PoruchApp
import kotlin.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Turns the shared store into the three lists home shows. The split by day happens here, once,
 * rather than inside the composition where it would run on every recomposition.
 */
class HomeViewModel(private val app: PoruchApp) : MviViewModel<HomeState, HomeIntent, HomeEffect>(HomeState()) {
    private val zone: ZoneId = ZoneId.systemDefault()

    /** Остання відповідь застосунку. Потрібна, щоб перебрати списки на зміну власного фільтра. */
    private var shared: AppState = AppState()

    init {
        observe(app) { shared ->
            this@HomeViewModel.shared = shared
            fold(shared, category)
        }
    }

    /**
     * Складає три списки головної зі спільного стану й **власної** категорії екрана.
     *
     * Звужується індекс, а не завантажені картки: під фільтром перші події категорії майже завжди
     * лежать далі за край вікна, і фільтрувати вікно означало б показати порожню головну там, де
     * подій насправді десятки.
     */
    private fun HomeState.fold(shared: AppState, category: String): HomeState {
        val today = LocalDate.now(zone)
        val chosen = { entry: EventIndexEntry -> category == ALL_CATEGORIES || entry.category == category }
        // Everything below reads the ranked list, so the whole screen is in one order.
        val ranked = shared.index.filter(chosen).mapNotNull { shared.cards[it.id] }
        val suggested = shared.suggestedIndex.filter(chosen).mapNotNull { shared.cards[it.id] }.take(SUGGESTED_LIMIT)
        // What is already under «Для вас» is not repeated further down the same screen.
        val remaining = ranked - suggested.toSet()
        val startingToday = remaining.filter { it.startsOn(today) }
        return copy(
            signedIn = shared.signedIn,
            cityName = shared.cityName,
            loading = shared.loading,
            // План — це те, що попереду. Подія, яка вже завершилась, у планах читається як помилка.
            plans = shared.myEvents
                .filter { it.gathering?.joined == true && it.isPublished && it.isCurrent(Clock.System.now()) }
                .sortedBy { it.startsAt },
            suggested = suggested,
            today = startingToday,
            rest = remaining - startingToday.toSet(),
            category = category,
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
        // Фільтрує головну на місці й не чіпає мапу. Картки для голови звуженого списку просимо
        // одразу — інакше екран був би порожнім, поки вікно стоїть на початку повного індексу.
        is HomeIntent.PickCategory -> {
            val picked = if (state.value.category == intent.category) ALL_CATEGORIES else intent.category
            reduce { fold(shared, picked) }
            val head = shared.index.filter { picked == ALL_CATEGORIES || it.category == picked }
            app.loadCards(head.take(HOME_CARDS).map { it.id })
        }
        HomeIntent.CreateEvent -> send(HomeEffect.Navigate(HomeDestination.EDITOR))
        HomeIntent.OpenMap -> send(HomeEffect.Navigate(HomeDestination.MAP))
        HomeIntent.OpenProfile -> send(HomeEffect.Navigate(HomeDestination.PROFILE))
    }

    private fun Event.startsOn(date: LocalDate) =
        runCatching { Instant.parse(startsAt).atZone(zone).toLocalDate() == date }.getOrDefault(false)
}

/** Home is a digest: past this many, «для вас» stops being a shortlist and becomes the list. */
private const val SUGGESTED_LIMIT = 4

/** Скільки карток головна просить під власний фільтр: більше за це вона не показує в жодному стані. */
private const val HOME_CARDS = 24
