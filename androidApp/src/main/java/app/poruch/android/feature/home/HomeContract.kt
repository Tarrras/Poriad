package app.poruch.android.feature.home

import app.poruch.domain.Event

/** What the home screen draws. Everything here is already filtered and sorted for rendering. */
data class HomeState(
    val signedIn: Boolean = false,
    val cityName: String = "",
    val loading: Boolean = false,
    /** Plans this account joined, soonest first. */
    val plans: List<Event> = emptyList(),
    val today: List<Event> = emptyList(),
    val rest: List<Event> = emptyList(),
    val selectedCategory: String = "",
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList()
) {
    val isEmpty get() = today.isEmpty() && rest.isEmpty()
}

sealed interface HomeIntent {
    data class OpenEvent(val id: String) : HomeIntent
    data class ToggleSaved(val id: String) : HomeIntent
    data class PickCategory(val category: String) : HomeIntent
    data object CreateEvent : HomeIntent
    data object OpenMap : HomeIntent
    data object OpenProfile : HomeIntent
}

/** Things the screen cannot express as state: where to go next. */
sealed interface HomeEffect {
    data class Navigate(val destination: HomeDestination, val id: String = "") : HomeEffect
}

enum class HomeDestination { DETAIL, MAP, PROFILE, EDITOR }
