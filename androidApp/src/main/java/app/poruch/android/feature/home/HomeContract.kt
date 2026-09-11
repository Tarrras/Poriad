package app.poruch.android.feature.home

import app.poruch.domain.Event
import app.poruch.shared.ALL_CATEGORIES

/** What the home screen draws. Everything here is already filtered and sorted for rendering. */
data class HomeState(
    val signedIn: Boolean = false,
    val cityName: String = "",
    val loading: Boolean = false,
    /** Plans this account joined, soonest first. */
    val plans: List<Event> = emptyList(),
    /** What the opening answers picked out. Empty when nothing was answered — never a filler. */
    val suggested: List<Event> = emptyList(),
    val today: List<Event> = emptyList(),
    val rest: List<Event> = emptyList(),
    /**
     * Категорія, обрана **на цьому екрані**. Мапа має свою.
     *
     * Доки категорія була одна на застосунок, вибір на головній переставляв фільтр мапи й навпаки:
     * два перемикачі, одне значення. Тепер кожен екран звужує те, що показує сам, а спільним
     * лишається те, що прийшло з сервера.
     */
    val category: String = ALL_CATEGORIES,
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    /**
     * Пошук — той самий, що й на мапі.
     *
     * Другий пошук поруч із першим означав би два джерела правди: тут знайшлось, там ні. Тому
     * головна не шукає сама, а відкриває двері до того ж запиту — і бачить ту саму видачу, з якої
     * і так малює свої списки.
     */
    val searchText: String = "",
    /** Уся видача одним списком: дайджест із результатів пошуку не складають. */
    val results: List<Event> = emptyList()
) {
    val searching get() = searchText.isNotBlank()
    val isEmpty get() = if (searching) results.isEmpty() else suggested.isEmpty() && today.isEmpty() && rest.isEmpty()
}

sealed interface HomeIntent {
    data class Search(val text: String) : HomeIntent
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
