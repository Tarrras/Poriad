package app.poruch.android.feature.home

import app.poruch.domain.ArtistHit
import app.poruch.domain.EventCategory
import app.poruch.domain.CityResult
import app.poruch.domain.FeedFilter
import app.poruch.domain.HomeRules
import app.poruch.domain.Place
import app.poruch.shared.DateFilter
import app.poruch.shared.HomeScreenState

/**
 * Стан головної: [screen] згортає спільний стор [app.poruch.shared.HomePresenter] — одна згортка на обидві
 * платформи; тут лише те, що належить цьому екрану на цьому пристрої: режим пошуку, ліміти, листи.
 */
data class HomeState(
    val screen: HomeScreenState = HomeScreenState(),
    /** Потяг вниз у дорозі. Окремо від `loading`: те піднімає й мапа, а індикатор жесту має слухати лише жест. */
    val refreshing: Boolean = false,
    /** Режим пошуку: тап у поле ховає стрічку, «Скасувати» чи «назад» повертає її без фільтрів. */
    val searchMode: Boolean = false,
    /** Скільки результатів показуємо; «Показати ще» додає [RESULTS_PAGE]. */
    val resultsLimit: Int = RESULTS_PAGE,
    /** Скільки рядків `feed` видно; «Показати ще» додає [HomeRules.FEED_PAGE]. */
    val feedLimit: Int = HomeRules.FEED_PAGE,
    /** Шторка вибору міста з шапки. */
    val citySheet: Boolean = false
)

/** Скільки результатів пошуку головна показує за раз. */
const val RESULTS_PAGE = 12

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
    /** Артист з пошуку: екран артиста. */
    data class OpenArtist(val artist: ArtistHit) : HomeIntent
    /** Прямо в чат події, минаючи деталі. */
    data class OpenChat(val id: String) : HomeIntent
    data class ToggleSaved(val id: String) : HomeIntent
    /** «Показати ще» під «У місті». */
    data object ShowMoreFeed : HomeIntent
    /** Чип над сіткою. */
    data class SelectFeedFilter(val filter: FeedFilter) : HomeIntent
    /** Плашка «Організувати подію» вгорі й підвал стрічки: новий редактор, гостя спершу до входу. [from] — `home_top` чи `home_footer`. */
    data class CreateEvent(val from: String) : HomeIntent
    data object OpenMap : HomeIntent
    /** «Усі N» біля «Від людей»: мапа лише зі зустрічами від людей з вільним місцем. */
    data object ShowPeopleOnMap : HomeIntent
    /** «Усі N» біля «У місті» і рядок «Усі події поруч»: мапа з усім містом, а не з фільтрами, що лишились з минулого візиту. */
    data object ShowEverythingOnMap : HomeIntent
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

enum class HomeDestination { DETAIL, CHAT, MAP, PROFILE, MINE, FOLLOWS, EDITOR, ARTIST }
