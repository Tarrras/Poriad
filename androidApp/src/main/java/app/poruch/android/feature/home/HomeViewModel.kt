package app.poruch.android.feature.home

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.Event
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

    init {
        observe(app) { shared ->
            val today = LocalDate.now(zone)
            // Everything below reads the ranked list, so the whole screen is in one order.
            val ranked = shared.events
            val suggested = shared.suggested.take(SUGGESTED_LIMIT)
            // What is already under «Для вас» is not repeated further down the same screen.
            val remaining = ranked - suggested.toSet()
            val startingToday = remaining.filter { it.startsOn(today) }
            copy(
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
                selectedCategory = shared.category,
                savedIds = shared.savedIds,
                waitlistedIds = shared.waitlistedIds,
                searchText = shared.searchText,
                results = ranked
            )
        }
    }

    override fun onIntent(intent: HomeIntent) = when (intent) {
        is HomeIntent.OpenEvent -> {
            app.selectEvent(intent.id)
            send(HomeEffect.Navigate(HomeDestination.DETAIL, intent.id))
        }
        is HomeIntent.Search -> app.setSearchText(intent.text)
        is HomeIntent.ToggleSaved -> app.toggleSaved(intent.id)
        is HomeIntent.PickCategory -> {
            app.setCategory(intent.category)
            send(HomeEffect.Navigate(HomeDestination.MAP))
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
