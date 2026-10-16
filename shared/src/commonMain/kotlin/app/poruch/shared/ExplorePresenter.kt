package app.poruch.shared

import app.poruch.domain.ArtistHit
import app.poruch.domain.CityResult
import app.poruch.domain.Event
import app.poruch.domain.EventCategory
import app.poruch.domain.EventIndexEntry
import app.poruch.domain.FollowKind
import app.poruch.domain.Place
import app.poruch.domain.asIndexEntry
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Що тримає екран мапи локально і що веде згортку: стос обраного піна. */
private data class ExploreLocal(
    val stackIds: List<String> = emptyList(),
    /** Росте, коли презентер сам відкрив стос (заклад з пошуку): платформа опускає шторку. */
    val focusToken: Int = 0
)

/** Стан екрана мапи: індекс для пінів, вміст шторки, фільтри й місто — усе вже пораховане. Платформа додає положення шторки, листи й камеру. */
data class ExploreScreenState(
    /** Що малює мапа: індекс, звужений категорією, плюс [focused], якщо її там ще нема. */
    val mapEvents: List<EventIndexEntry> = emptyList(),
    /** Вміст шторки: стос обраного піна або вся видача. Порядок — з індексу. */
    val listEntries: List<EventIndexEntry> = emptyList(),
    /** Завантажені картки шторки для каруселі й списку, у порядку [listEntries]. */
    val deckEvents: List<Event> = emptyList(),
    val totalFound: Int = 0,
    val selectedId: String? = null,
    /** Подія, на яку навели з деталей. Може не бути в поточній видачі, тоді піна для неї нема. */
    val focused: Event? = null,
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    val cityName: String = "",
    val cityLatitude: Double = 0.0,
    val cityLongitude: Double = 0.0,
    val cities: List<CityResult> = emptyList(),
    val searchText: String = "",
    /** Заклади за [searchText]: секція «Місця» у списку шторки. Порожньо у стосі піна: там уже одне місце. */
    val places: List<Place> = emptyList(),
    /** Артисти за [searchText]: секція «Артисти» під «Місцями». */
    val artists: List<ArtistHit> = emptyList(),
    val category: EventCategory? = null,
    val dateFilter: DateFilter = DateFilter.ANY,
    val onlyAvailable: Boolean = false,
    val loading: Boolean = false,
    val offline: Boolean = false,
    /** Область поставили рукою через «Шукати тут». */
    val customArea: Boolean = false,
    val signedIn: Boolean = false,
    /** Події на одній точці (всі події закладу): без стосу тап відкривав завжди ту саму. */
    val stackIds: List<String> = emptyList(),
    /** Стос обраного піна не порожній. Порожньо, якщо після нової видачі стосу не лишилось. */
    val stackFocused: Boolean = false,
    /** Заклад за стосом: для кнопки «Стежити». Null — стосу нема, це спільнотні події або картки ще їдуть. */
    val stackPlace: PlaceRef? = null,
    val stackFollowing: Boolean = false,
    /** Лічильник змін складу індексу: платформа за ним перебудовує піни й скидає область. */
    val indexVersion: Int = 0,
    /** Скільки разів на мапу переходили з головної з готовими фільтрами: платформа повертає камеру до міста. */
    val arrivals: Int = 0,
    /** Росте, коли презентер сам відкрив стос: платформа опускає шторку. */
    val focusToken: Int = 0
) {
    val activeFilters: Int get() = listOf(dateFilter != DateFilter.ANY, category != null, onlyAvailable).count { it }
    /** Чи є що довантажувати: індекс повний, картки — ні. */
    val hasMoreCards: Boolean get() = deckEvents.size < listEntries.size
    /** Лічильник шторки: з індексу, а не з завантажених карток. */
    val listCount: Int get() = if (category == null && !stackFocused) totalFound else listEntries.size

    companion object {
        val Empty = ExploreScreenState()
    }
}

/**
 * Згортає [PoruchApp.state] у [ExploreScreenState] — та сама логіка на Android та iOS. Тримає стос піна, бо від
 * нього залежить вміст шторки; сам відкриває стос закладу з пошуку і скидає його, коли змінились фільтри чи
 * мапа приходить з головної. Платформа лишає собі положення шторки, камеру, листи й дозволи.
 */
class ExplorePresenter(
    private val app: PoruchApp,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
    compute: CoroutineDispatcher = Dispatchers.Default
) {
    /** Для iOS: без диспетчерів. */
    constructor(app: PoruchApp) : this(app, CoroutineScope(SupervisorJob() + Dispatchers.Main))

    private val local = MutableStateFlow(ExploreLocal())
    private var visibleFrom: Pair<List<EventIndexEntry>, EventCategory?>? = null
    private var visible: List<EventIndexEntry> = emptyList()

    val state: StateFlow<ExploreScreenState> = combine(
        app.state.distinctUntilChanged { old, new -> sameInputs(old, new) }, local
    ) { shared, local -> derive(shared, local) }
        .flowOn(compute)
        .stateIn(scope, SharingStarted.Eagerly, ExploreScreenState.Empty)

    init {
        // Тап по закладу в пошуку (тут чи на головній): стос відкриваємо, коли видача сказала, що на піні.
        // Поточне значення приходить першим: презентер міг зʼявитись уже після тапу.
        scope.launch {
            app.state.map { it.map.placeFocus }.distinctUntilChanged().collect { focus ->
                val ids = focus?.eventIds ?: return@collect
                showStack(ids)
                local.update { it.copy(focusToken = it.focusToken + 1) }
                app.placeFocusShown()
            }
        }
        // «Усі N» з головної: стос — з чистого аркуша. Решту (шторки, камера) скидає платформа за `arrivals`.
        scope.launch {
            app.state.map { it.map.arrivals }.distinctUntilChanged().collect { arrivals ->
                if (arrivals > 0) resetStack()
            }
        }
        // Новий фільтр — нова видача, стос скидається тут, а не на кожній платформі: інакше iOS лишав стос, де
        // вціліли дві події, і чипи над ним наче не діяли. Поточне значення пропускаємо: стос закладу з пошуку
        // міг відкритись раніше за цю підписку. Текст пошуку не слухаємо: заклад з пошуку сам його стирає.
        scope.launch {
            app.state.map { Triple(it.map.dateFilter, it.map.category, it.map.onlyAvailable) }
                .distinctUntilChanged().drop(1).collect { resetStack() }
        }
    }

    /** Тап у точку з кількома подіями. Одна — звичайний вибір; кілька — стос. Вибір наводить мапу на пін. */
    fun showStack(ids: List<String>) {
        if (ids.size <= 1) {
            local.update { it.copy(stackIds = emptyList()) }
            ids.firstOrNull()?.let { app.selectEvent(it) }
        } else {
            local.update { it.copy(stackIds = ids) }
            // Стос — не початок стрічки, вікно його не покриває.
            app.loadCards(ids)
            app.selectEvent(ids.first())
        }
    }

    /** Зміна видачі (пошук, фільтр, місто, область) скидає стос: у ньому лишились би id подій, яких уже нема. */
    fun resetStack() = local.update { it.copy(stackIds = emptyList()) }

    /** Вихід із фокуса на піні знімає і підсвітку, інакше мапа й список розходились. */
    fun clearStack() {
        resetStack()
        app.dismissEvent()
    }

    /** Мапу відкрили заради однієї події (міні-мапа деталей): стос геть. Картка й під фільтром у каруселі — див. [derive]. */
    fun focusEvent(id: String) {
        resetStack()
        app.selectEvent(id)
    }

    /** Заклад з пошуку: стос відкриє `placeFocus`, щойно приїде видача. */
    fun focusPlace(place: Place) {
        resetStack()
        app.focusPlace(place)
    }

    /**
     * Плитка категорії в шторці — та сама категорія, що у «Фільтрах»: звужує мапу, список і карусель, рахується
     * в лічильнику. Окрема категорія списку перетиналась із нею, і пін із десятьма подіями показував нуль.
     * Повторний тап знімає вибір. Картки нового списку платформа просить сама, коли категорія змінилась.
     */
    fun toggleCategory(category: EventCategory) =
        app.setCategory(if (app.state.value.map.category == category) null else category)

    /** Картки початку того списку, який шторка зараз показує. */
    fun loadHead(count: Int) {
        val ids = state.value.listEntries.take(count).map { it.id }
        if (ids.isNotEmpty()) app.loadCards(ids)
    }

    /** «Стежити» за закладом стосу. Повертає false для гостя: пуш привʼязаний до акаунта, його ведуть на вхід. */
    fun toggleFollowStack(): Boolean {
        val current = state.value
        val place = current.stackPlace ?: return true
        if (!current.signedIn) return false
        app.setFollowing(FollowKind.PLACE, place.id, place.name, !current.stackFollowing)
        return true
    }

    /** Для iOS: колбек на кожну зміну стану екрана, на головному потоці. */
    fun observe(onChange: (ExploreScreenState) -> Unit): Subscription {
        val job = scope.launch { state.collect { onChange(it) } }
        return Subscription { job.cancel() }
    }

    fun close() = scope.cancel()

    private fun sameInputs(old: AppState, new: AppState): Boolean =
        old.map === new.map && old.cards === new.cards && old.detail === new.detail &&
            old.library === new.library && old.city === new.city && old.session === new.session

    private fun derive(shared: AppState, local: ExploreLocal): ExploreScreenState {
        val index = shared.map.index
        val category = shared.map.category
        // Індекс, звужений категорією: той самий екземпляр, поки не змінились індекс чи категорія, — мапа не переписує GeoJSON.
        val from = visibleFrom
        if (from == null || from.first !== index || from.second != category) {
            visible = if (category == null) index else index.filter { it.category == category }
            visibleFrom = index to category
        }
        val focused = shared.detail.event
        // Сеанс прокату «вже там» через представника, інакше пін майданчика рахував би прокат двічі.
        val present = focused == null || visible.any { entry -> entry.id == focused.id || entry.sessions.any { it.id == focused.id } }
        val mapEvents = if (present) visible else visible + focused!!.asIndexEntry()
        val stackSet = local.stackIds.toSet()
        val stackFocused = stackSet.isNotEmpty() && visible.count { it.id in stackSet } > 1
        val listEntries = if (stackFocused) index.filter { it.id in stackSet } else mapEvents
        val cards = shared.cards
        // [focused] без картки у видачі додається окремо.
        val deckEvents = listEntries.mapNotNull { entry -> cards[entry.id] ?: focused?.takeIf { it.id == entry.id } }
        val stackPlace = if (stackFocused) shared.placeOfStack(local.stackIds) else null
        return ExploreScreenState(
            mapEvents = mapEvents,
            listEntries = listEntries,
            deckEvents = deckEvents,
            totalFound = shared.map.totalFound,
            selectedId = focused?.id,
            focused = focused,
            savedIds = shared.library.savedIds,
            waitlistedIds = shared.library.waitlistedIds,
            cityName = shared.city.name,
            cityLatitude = shared.city.latitude,
            cityLongitude = shared.city.longitude,
            cities = shared.city.suggestions,
            searchText = shared.map.searchText,
            // У стосі піна заклади й артисти зайві: там уже одне місце.
            places = if (stackFocused) emptyList() else shared.map.places.map { it.countedIn(shared.home.index) },
            artists = if (stackFocused) emptyList() else shared.map.artists,
            category = category,
            dateFilter = shared.map.dateFilter,
            onlyAvailable = shared.map.onlyAvailable,
            loading = shared.map.loading,
            offline = shared.map.offline,
            customArea = shared.city.custom,
            signedIn = shared.signedIn,
            stackIds = local.stackIds,
            stackFocused = stackFocused,
            stackPlace = stackPlace,
            stackFollowing = stackPlace != null && shared.isFollowing(FollowKind.PLACE, stackPlace.id),
            indexVersion = shared.map.indexVersion,
            arrivals = shared.map.arrivals,
            focusToken = local.focusToken
        )
    }
}
