package app.poruch.android.feature.home

import app.poruch.domain.EventCategory
import app.poruch.domain.ChatUnread
import app.poruch.domain.CityResult
import app.poruch.domain.Event
import app.poruch.domain.FeedEntry
import app.poruch.domain.FeedFilter
import app.poruch.domain.HomeLocation
import app.poruch.domain.HomeRules
import app.poruch.domain.Place
import app.poruch.shared.DateFilter

/** Стан головної: усе вже відфільтроване й посортоване для рендеру. */
data class HomeState(
    val signedIn: Boolean = false,
    val cityName: String = "",
    val loading: Boolean = false,
    /** Потяг вниз у дорозі. Окремо від [loading]: те піднімає й мапа, а індикатор жесту має слухати лише жест. */
    val refreshing: Boolean = false,
    /** «Ваше»: до [HomeRules.PERSONAL_LIMIT] своїх подій, спершу ті, де хтось чекає відповіді. */
    val personal: List<PersonalRow> = emptyList(),
    /** Майбутні події закладів і організаторів, за якими стежу, найближчі першими. Порожньо — рядка «Підписки» нема. */
    val followed: List<Event> = emptyList(),
    /** Скільки подій, що чекають відповіді (чат, запит), у [personal] не влізло: рядок «Чекають відповіді: ще N». */
    val moreWaiting: Int = 0,
    /** «У місті»: [HERO_COUNT] великих карток, далі сітка, вже звужена [feedFilter]. */
    val feed: List<FeedEntry> = emptyList(),
    /** Чипи над сіткою: що з неї можна відфільтрувати. Порожньо — рядка нема. */
    val chips: List<FeedFilter> = emptyList(),
    /** Обраний чип; якщо його вже нема в [chips] (дані оновились), стрічка лишається цілою. */
    val feedFilter: FeedFilter = FeedFilter(),
    /** Скільки рядків [feed] видно; «Показати ще» додає [HomeRules.FEED_PAGE]. */
    val feedLimit: Int = HomeRules.FEED_PAGE,
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
    val searchCategory: EventCategory? = null,
    val searchDate: DateFilter = DateFilter.ANY,
    /** Місто з подіями, назване в пошуку, крім поточного: текстовий пошук іде лише в межах міста. */
    val cityMatch: HomeLocation? = null,
    /** Шторка вибору міста з шапки і підказки геопошуку для неї. */
    val citySheet: Boolean = false,
    val cities: List<CityResult> = emptyList()
) {
    val searching get() = searchText.isNotBlank()
    val isEmpty get() = if (searching) results.isEmpty() && places.isEmpty() else personal.isEmpty() && feed.isEmpty()
    val busy get() = if (searching) searchLoading else loading
}

/** Скільки результатів пошуку головна показує за раз. */
const val RESULTS_PAGE = 12

/** Кількість великих карток над сіткою «У місті». */
const val HERO_COUNT = 3

/** Рядок «Ваше»: своя подія, її непрочитаний чат і скільки людей просяться. */
data class PersonalRow(val event: Event, val chat: ChatUnread?, val requests: Int, val organizing: Boolean)

sealed interface HomeIntent {
    /** Тап у поле пошуку. */
    data object EnterSearch : HomeIntent
    /** «Скасувати» або «назад» у режимі пошуку: текст і фільтри скидаються. */
    data object CancelSearch : HomeIntent
    data class Search(val text: String) : HomeIntent
    /** Фільтри під полем пошуку: область, категорія, дата. */
    data class SearchEverywhere(val everywhere: Boolean) : HomeIntent
    data class SearchCategory(val category: EventCategory?) : HomeIntent
    data class SearchDate(val filter: DateFilter) : HomeIntent
    /** Підказка «Показати події в місті …» під пошуком або місто зі шторки шапки. */
    data class SwitchCity(val city: CityResult) : HomeIntent
    /** Тап по місту в шапці відкриває шторку, закриття — ховає. */
    data class ShowCitySheet(val show: Boolean) : HomeIntent
    data class SearchCity(val query: String) : HomeIntent
    /** «Показати ще» під результатами: видача росте на місці, нова видача починає знову з [RESULTS_PAGE]. */
    data object ShowMoreResults : HomeIntent
    /** «На мапі» біля заголовка результатів у місті: мапа відкривається з тим самим пошуком. Єдиний міст між пошуками. */
    data object ShowResultsOnMap : HomeIntent
    /** [from] — звідки відкрито (`home_hero`, `home_poster`, `home_your`, `home_search`): піде в `event_view`. */
    data class OpenEvent(val id: String, val from: String) : HomeIntent
    /** Заклад з пошуку: мапа переходить до нього й відкриває його стос. */
    data class OpenPlace(val place: Place) : HomeIntent
    /** Прямо в чат події, минаючи деталі. */
    data class OpenChat(val id: String) : HomeIntent
    data class ToggleSaved(val id: String) : HomeIntent
    /** «Показати ще» під «У місті». */
    data object ShowMoreFeed : HomeIntent
    /** Чип над сіткою. */
    data class SelectFeedFilter(val filter: FeedFilter) : HomeIntent
    /** Рядок «Планів поки нема» і підвал стрічки: новий редактор, гостя спершу до входу. */
    data object CreateEvent : HomeIntent
    data object OpenMap : HomeIntent
    data object OpenProfile : HomeIntent
    /** «Мої події» біля блоку «Ваше». */
    data object OpenMyEvents : HomeIntent
    /** Рядок «Підписки» в «Ваше»: сам список підписок. */
    data object OpenFollows : HomeIntent
    /** Потяг вниз: перечитати все, як при поверненні в застосунок. */
    data object Refresh : HomeIntent
}

/** Куди переходити: те, чого стан не виразить. */
sealed interface HomeEffect {
    data class Navigate(val destination: HomeDestination, val id: String = "") : HomeEffect
}

enum class HomeDestination { DETAIL, CHAT, MAP, PROFILE, MINE, FOLLOWS, EDITOR }
