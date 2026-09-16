package app.poruch.android.feature.home

import app.poruch.domain.ChatUnread
import app.poruch.domain.Event

/** Стан головної: усе вже відфільтроване й посортоване для рендеру. */
data class HomeState(
    val signedIn: Boolean = false,
    val cityName: String = "",
    val loading: Boolean = false,
    /** Плани: організую або йду, найближчі першими. */
    val plans: List<Event> = emptyList(),
    /** Мої події, де чекають запити на участь, зі скількома. Лише в організатора. */
    val requests: List<PendingRequests> = emptyList(),
    /** Чати з непрочитаним, свіжіші першими. */
    val unread: List<ChatUnread> = emptyList(),
    /** Добірка за відповідями онбордингу. Порожня, якщо не відповідали. */
    val suggested: List<Event> = emptyList(),
    val today: List<Event> = emptyList(),
    val rest: List<Event> = emptyList(),
    /** Скільки подій в області, те саме число, що на мапі. */
    val totalFound: Int = 0,
    /** Область поставили рукою через «Шукати тут». */
    val customArea: Boolean = false,
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    /** Той самий пошук, що на мапі: другого джерела правди нема. */
    val searchText: String = "",
    /** Результати пошуку одним списком, без дайджесту. */
    val results: List<Event> = emptyList()
) {
    val searching get() = searchText.isNotBlank()
    val isEmpty get() = if (searching) results.isEmpty() else suggested.isEmpty() && today.isEmpty() && rest.isEmpty()
}

/** Подія й скільки людей просяться до неї. */
data class PendingRequests(val event: Event, val count: Int)

sealed interface HomeIntent {
    data class Search(val text: String) : HomeIntent
    data class OpenEvent(val id: String) : HomeIntent
    /** Прямо в чат події, минаючи деталі. */
    data class OpenChat(val id: String) : HomeIntent
    data class ToggleSaved(val id: String) : HomeIntent
    data object CreateEvent : HomeIntent
    data object OpenMap : HomeIntent
    data object OpenProfile : HomeIntent
}

/** Куди переходити: те, чого стан не виразить. */
sealed interface HomeEffect {
    data class Navigate(val destination: HomeDestination, val id: String = "") : HomeEffect
}

enum class HomeDestination { DETAIL, CHAT, MAP, PROFILE, EDITOR }
