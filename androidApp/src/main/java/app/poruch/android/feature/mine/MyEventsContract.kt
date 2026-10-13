package app.poruch.android.feature.mine

import app.poruch.domain.Event
import app.poruch.domain.MyEventsTab
import app.poruch.domain.RatingTag
import app.poruch.shared.MyEventsScreenState

/** «Мої події» — три розрізи з секціями за часом (docs/my-events.md). Розклад рахує `MyEventsRules`. */
/**
 * «Мої події»: [screen] згортає спільний стор [app.poruch.shared.MyEventsPresenter] — одна згортка на обидві
 * платформи; тут лише розріз, «Минулі» й шторка оцінки цього екрана.
 */
data class MyEventsState(
    val screen: MyEventsScreenState = MyEventsScreenState.Empty,
    val tab: MyEventsTab = MyEventsTab.GOING,
    /** Потяг униз у дорозі. */
    val refreshing: Boolean = false,
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
    /** [follow] — що показував перемикач «Стежити за організатором»; null — перемикача не було. */
    data class Rate(val id: String, val score: Int, val comment: String, val tags: List<RatingTag>, val follow: Boolean?) : MyEventsIntent
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
