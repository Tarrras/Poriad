package app.poruch.android.feature.home

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.Event
import app.poruch.shared.PoruchApp
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
            val startingToday = shared.events.filter { it.startsOn(today) }
            copy(
                signedIn = shared.signedIn,
                cityName = shared.cityName,
                loading = shared.loading,
                plans = shared.myEvents.filter { it.joined && it.isPublished }.sortedBy { it.startsAt },
                today = startingToday,
                rest = shared.events - startingToday.toSet(),
                selectedCategory = shared.category,
                savedIds = shared.savedIds,
                waitlistedIds = shared.waitlistedIds
            )
        }
    }

    override fun onIntent(intent: HomeIntent) = when (intent) {
        is HomeIntent.OpenEvent -> {
            app.selectEvent(intent.id)
            send(HomeEffect.Navigate(HomeDestination.DETAIL, intent.id))
        }
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
