package app.poruch.android.feature.home

import app.poruch.domain.ChatUnread
import app.poruch.domain.CityResult
import app.poruch.domain.Event
import app.poruch.domain.HomeLocation
import app.poruch.domain.Place
import app.poruch.shared.ALL_CATEGORIES
import app.poruch.shared.DateFilter

/** Стан головної: усе вже відфільтроване й посортоване для рендеру. */
data class HomeState(
    val signedIn: Boolean = false,
    val cityName: String = "",
    val loading: Boolean = false,
    /** Потяг вниз у дорозі. Окремо від [loading]: те піднімає й мапа, а індикатор жесту має слухати лише жест. */
    val refreshing: Boolean = false,
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
    /** Скільки подій в області, без фільтрів мапи. */
    val totalFound: Int = 0,
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    /** Пошук головної, окремий від мапи: фільтр одного екрана не порожнить інший. */
    val searchText: String = "",
    /** Режим пошуку: тап у поле ховає стрічку, «Скасувати» чи «назад» повертає її без фільтрів. */
    val searchMode: Boolean = false,
    /** Результати пошуку одним списком, без дайджесту. Лише ті, чиї картки вже приїхали. */
    val results: List<Event> = emptyList(),
    /** Скільки результатів показуємо; «Показати ще» додає [RESULTS_PAGE]. */
    val resultsLimit: Int = RESULTS_PAGE,
    /** Скільки результатів прийшло в індексі: більше за [resultsLimit] — є що показати ще. */
    val resultsIndexed: Int = 0,
    /** Скільки знайдено насправді. */
    val resultsTotal: Int = 0,
    /** Заклади за тим самим запитом: секція «Місця» під подіями. */
    val places: List<Place> = emptyList(),
    val searchLoading: Boolean = false,
    /** Пошук по всіх містах, а не лише в [cityName]. Фільтри пошуку звужують лише знайдене, не стрічку. */
    val searchEverywhere: Boolean = false,
    val searchCategory: String = ALL_CATEGORIES,
    val searchDate: String = DateFilter.ANY,
    /** Місто з подіями, назване в пошуку, крім поточного: текстовий пошук іде лише в межах міста. */
    val cityMatch: HomeLocation? = null,
    /** Шторка вибору міста з шапки і підказки геопошуку для неї. */
    val citySheet: Boolean = false,
    val cities: List<CityResult> = emptyList()
) {
    val searching get() = searchText.isNotBlank()
    val isEmpty get() = if (searching) results.isEmpty() && places.isEmpty() else suggested.isEmpty() && today.isEmpty() && rest.isEmpty()
    val busy get() = if (searching) searchLoading else loading
}

/** Скільки результатів пошуку головна показує за раз. */
const val RESULTS_PAGE = 12

/** Подія й скільки людей просяться до неї. */
data class PendingRequests(val event: Event, val count: Int)

sealed interface HomeIntent {
    /** Тап у поле пошуку. */
    data object EnterSearch : HomeIntent
    /** «Скасувати» або «назад» у режимі пошуку: текст і фільтри скидаються. */
    data object CancelSearch : HomeIntent
    data class Search(val text: String) : HomeIntent
    /** Фільтри під полем пошуку: область, категорія, дата. */
    data class SearchEverywhere(val everywhere: Boolean) : HomeIntent
    data class SearchCategory(val category: String) : HomeIntent
    data class SearchDate(val filter: String) : HomeIntent
    /** Підказка «Показати події в місті …» під пошуком або місто зі шторки шапки. */
    data class SwitchCity(val city: CityResult) : HomeIntent
    /** Тап по місту в шапці відкриває шторку, закриття — ховає. */
    data class ShowCitySheet(val show: Boolean) : HomeIntent
    data class SearchCity(val query: String) : HomeIntent
    /** «Показати ще» під результатами: видача росте на місці, нова видача починає знову з [RESULTS_PAGE]. */
    data object ShowMoreResults : HomeIntent
    /** «На мапі» біля заголовка результатів у місті: мапа відкривається з тим самим пошуком. Єдиний міст між пошуками. */
    data object ShowResultsOnMap : HomeIntent
    data class OpenEvent(val id: String) : HomeIntent
    /** Заклад з пошуку: мапа переходить до нього й відкриває його стос. */
    data class OpenPlace(val place: Place) : HomeIntent
    /** Прямо в чат події, минаючи деталі. */
    data class OpenChat(val id: String) : HomeIntent
    data class ToggleSaved(val id: String) : HomeIntent
    data object CreateEvent : HomeIntent
    data object OpenMap : HomeIntent
    /** Плитка категорії на головній: мапа відкривається вже з цим фільтром. */
    data class OpenCategory(val category: String) : HomeIntent
    data object OpenProfile : HomeIntent
    /** Потяг вниз: перечитати все, як при поверненні в застосунок. */
    data object Refresh : HomeIntent
}

/** Куди переходити: те, чого стан не виразить. */
sealed interface HomeEffect {
    data class Navigate(val destination: HomeDestination, val id: String = "") : HomeEffect
}

enum class HomeDestination { DETAIL, CHAT, MAP, PROFILE, EDITOR }
