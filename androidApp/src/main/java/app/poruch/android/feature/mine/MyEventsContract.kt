package app.poruch.android.feature.mine

import app.poruch.domain.Event

/** «Мої події» — один список у чотирьох розрізах. */
enum class MyEventsTab { ATTENDING, ORGANIZING, SAVED, ENDED }

data class MyEventsState(
    val tab: MyEventsTab = MyEventsTab.ATTENDING,
    val visible: List<Event> = emptyList(),
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    val signedIn: Boolean = false,
    val loading: Boolean = false,
    /** Потяг вниз або кнопка «Оновити» в дорозі. */
    val refreshing: Boolean = false,
    /** Непрочитані повідомлення за id події: бейдж на рядку. */
    val unread: Map<String, Int> = emptyMap(),
    /** Скільки чатів з непрочитаним у кожному розрізі: бейдж на чипі, щоб було видно, куди йти. */
    val unreadByTab: Map<MyEventsTab, Int> = emptyMap()
)

sealed interface MyEventsIntent {
    data class PickTab(val tab: MyEventsTab) : MyEventsIntent
    /** Потяг вниз або кнопка «Оновити»: перечитати «мої». */
    data object Refresh : MyEventsIntent
    data class OpenEvent(val id: String) : MyEventsIntent
    data object SignIn : MyEventsIntent
    data object CreateEvent : MyEventsIntent
}

sealed interface MyEventsEffect {
    data class OpenDetail(val id: String) : MyEventsEffect
    data object SignIn : MyEventsEffect
    data object CreateEvent : MyEventsEffect
}
