package app.poruch.android.feature.mine

import app.poruch.domain.Event
import app.poruch.domain.JoinRequest
import app.poruch.domain.MyEventsBoard
import app.poruch.domain.MyEventsTab

/** «Мої події» — три розрізи з секціями за часом (docs/my-events.md). Розклад рахує `MyEventsRules`. */
data class MyEventsState(
    val tab: MyEventsTab = MyEventsTab.GOING,
    val board: MyEventsBoard = MyEventsBoard(),
    val waitlistedIds: List<String> = emptyList(),
    /** Мої бали за id події: «Оцінити» чи «Ваша оцінка ★ N». */
    val myRatings: Map<String, Int> = emptyMap(),
    /** Запити на участь до моїх подій: перший — на панелі найближчої. */
    val requests: List<JoinRequest> = emptyList(),
    val signedIn: Boolean = false,
    val loading: Boolean = false,
    val mutating: Boolean = false,
    /** Потяг униз у дорозі. */
    val refreshing: Boolean = false,
    /** Непрочитані повідомлення за id події: бейдж на рядку. */
    val unread: Map<String, Int> = emptyMap(),
    /** «Минулі» розгорнуто цілком. Скидається зі зміною розрізу. */
    val allPast: Boolean = false,
    /** Подія, яку оцінюють у шторці. */
    val rating: Event? = null
)

sealed interface MyEventsIntent {
    data class PickTab(val tab: MyEventsTab) : MyEventsIntent
    data object Refresh : MyEventsIntent
    data class OpenEvent(val id: String) : MyEventsIntent
    data class OpenChat(val id: String) : MyEventsIntent
    data object FindNearby : MyEventsIntent
    data object ShowAllPast : MyEventsIntent
    data class StartRating(val event: Event) : MyEventsIntent
    data object DismissRating : MyEventsIntent
    data class Rate(val id: String, val score: Int, val comment: String) : MyEventsIntent
    data class Approve(val eventId: String, val userId: String) : MyEventsIntent
    data class Decline(val eventId: String, val userId: String) : MyEventsIntent
    data class Unsave(val id: String) : MyEventsIntent
    data object SignIn : MyEventsIntent
    data object CreateEvent : MyEventsIntent
}

sealed interface MyEventsEffect {
    data class OpenDetail(val id: String) : MyEventsEffect
    data class OpenChat(val id: String) : MyEventsEffect
    data object OpenMap : MyEventsEffect
    data object SignIn : MyEventsEffect
    data object CreateEvent : MyEventsEffect
}
