package app.poruch.shared

import app.poruch.domain.ArtistHit
import app.poruch.domain.CityResult
import app.poruch.domain.DiscoveryRules
import app.poruch.domain.Event
import app.poruch.domain.EventCategory
import app.poruch.domain.EventIndexEntry
import app.poruch.domain.FollowKind
import app.poruch.domain.Place
import app.poruch.domain.PoruchAnalytics
import app.poruch.domain.PoruchLog
import app.poruch.domain.asIndexEntry
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.roundToInt

/** Що тримає екран мапи локально і що веде згортку: стос обраного піна. */
private data class ExploreLocal(
    /** Події, з якими стос відкрили: за ними — назва закладу для «Стежити», навіть коли фільтр лишив тут нуль. */
    val stackIds: List<String> = emptyList(),
    /**
     * Точки стосу. Стос — це місце, а не список: фільтр звужує його події, а знятий фільтр повертає всі події цих точок,
     * яких на момент тапу у видачі не було.
     */
    val stackPoints: Set<Pair<Double, Double>> = emptySet(),
    /** Росте, коли презентер сам відкрив стос (заклад з пошуку): платформа опускає шторку. */
    val focusToken: Int = 0,
    /** «Ближче до мене»: де людина, коли шторку впорядкували від неї. Null — порядок «для вас», з індексу. */
    val near: Pair<Double, Double>? = null
)

/** Стан екрана мапи: індекс для пінів, вміст шторки, фільтри й місто — усе вже пораховане. Платформа додає положення шторки, листи й камеру. */
data class ExploreScreenState(
    /** Що малює мапа: індекс, звужений категорією, плюс [focused], якщо її там ще нема. */
    val mapEvents: List<EventIndexEntry> = emptyList(),
    /** Вміст шторки: стос обраного піна або вся видача. Порядок — з індексу, а з [nearMe] — від найближчої. */
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
    /** Події стосу під поточними фільтрами (всі події закладу): без стосу тап відкривав завжди ту саму. */
    val stackIds: List<String> = emptyList(),
    /** Шторка показує заклад, а не місто. Фільтри звужують його події, і нуль під фільтром — теж стос, а не вихід із нього. */
    val stackFocused: Boolean = false,
    /** Заклад за стосом: для кнопки «Стежити». Null — стосу нема, це спільнотні події або картки ще їдуть. */
    val stackPlace: PlaceRef? = null,
    val stackFollowing: Boolean = false,
    /** Лічильник змін складу індексу: платформа за ним перебудовує піни й скидає область. */
    val indexVersion: Int = 0,
    /** Скільки разів на мапу переходили з головної з готовими фільтрами: платформа повертає камеру до міста. */
    val arrivals: Int = 0,
    /** Скільки разів змінився запит мапи: платформа ставить карусель на першу картку. Див. [MapFeed.queries]. */
    val queries: Int = 0,
    /** Росте, коли презентер сам відкрив стос: платформа опускає шторку. */
    val focusToken: Int = 0,
    /**
     * Скільки подій дасть кожна плитка категорії: у місті чи в стосі, під датою, «Від людей» і пошуком. Після вибору
     * категорії збігається з [listCount]. Null — видача під новий запит ще їде, і старі числа брехали б.
     */
    val categoryCounts: Map<EventCategory, Int>? = null,
    /** Список і карусель — від найближчої до людини («Ближче до мене»). Піни на мапі не міняються. */
    val nearMe: Boolean = false,
    val nearLatitude: Double = 0.0,
    val nearLongitude: Double = 0.0
) {
    val activeFilters: Int get() = listOf(dateFilter != DateFilter.ANY, category != null, onlyAvailable).count { it }
    /** Чи є що довантажувати: індекс повний, картки — ні. */
    val hasMoreCards: Boolean get() = deckEvents.size < listEntries.size
    /** Лічильник шторки: з індексу, а не з завантажених карток. */
    val listCount: Int get() = if (category == null && !stackFocused) totalFound else listEntries.size

    /** Число плитки [category]: категорії без подій у [categoryCounts] нема, це нуль. Null — видача ще їде. */
    fun countOf(category: EventCategory): Int? = categoryCounts?.let { it[category] ?: 0 }

    /**
     * Відстань від людини цілими кілометрами для рядка списку; 0 — ближче за кілометр («до 1 км»). Null — «Ближче до
     * мене» вимкнено. Не метри: геолокація приблизна (кілометр на iOS, COARSE на Android), «350 м» було б неправдою.
     */
    fun kmFromMe(event: Event): Int? =
        if (!nearMe) null else (metersBetween(nearLatitude, nearLongitude, event.latitude, event.longitude) / 1000).let {
            if (it < 1) 0 else it.roundToInt()
        }

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
    /** Що видно на мапі зараз: південь, захід, північ, схід. Повідомляє платформа, коли камера зупинилась. */
    private var viewport: DoubleArray? = null

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
        // Фільтри в стосі звужують події закладу, а не виводять у місто: дата, «Від людей» і категорія діють і тут, як
        // на будь-якій шторці. Поточне значення пропускаємо. Поза стосом: коли видача під фільтр приїде, а на екрані
        // з неї нічого, — до найближчої події, див. [revealNearest]. У стосі заклад і так на екрані: нуль під фільтром
        // показує його порожній стан.
        scope.launch {
            var before: Pair<Triple<DateFilter, EventCategory?, Boolean>, Int>? = null
            app.state.map { Triple(it.map.dateFilter, it.map.category, it.map.onlyAvailable) to it.map.arrivals }
                .distinctUntilChanged().collectLatest { now ->
                    val previous = before
                    before = now
                    if (previous == null || previous.first == now.first) return@collectLatest
                    // «Усі N» з головної ставить фільтри разом із камерою на місто: там і лишаємось.
                    if (previous.second != now.second) return@collectLatest
                    app.state.first { it.map.answered == it.map.queries }
                    if (local.value.stackPoints.isEmpty()) revealNearest()
                }
        }
        // «Ближче до мене» міняє порядок шторки: картки її нового початку просимо самі, інакше список показував би вже
        // завантажені картки з пропусками там, де найближчі ще їдуть.
        scope.launch {
            state.map { it.nearMe }.distinctUntilChanged().drop(1).collect { loadHead(DiscoveryRules.FIRST_CARDS) }
        }
    }

    /** Тап у точку з кількома подіями. Одна — звичайний вибір; кілька — стос. Вибір наводить мапу на пін. */
    fun showStack(ids: List<String>) {
        if (ids.size <= 1) {
            resetStack()
            ids.firstOrNull()?.let { app.selectEvent(it) }
        } else {
            val wanted = ids.toSet()
            val points = app.state.value.map.index.filter { it.id in wanted }.mapTo(HashSet()) { it.latitude to it.longitude }
            local.update { it.copy(stackIds = ids, stackPoints = points) }
            // Стос — не початок стрічки, вікно його не покриває.
            app.loadCards(ids)
            app.selectEvent(ids.first())
        }
    }

    /** Що видно на мапі. Платформа кличе, коли камера зупинилась, хоч від жесту, хоч від вибору. */
    fun viewport(south: Double, west: Double, north: Double, east: Double) {
        viewport = doubleArrayOf(south, west, north, east)
    }

    /**
     * Фільтр лишив екран порожнім: видача є, а жодного її піна там, куди людина дивиться (часто — на місці колишнього
     * вибору). Обираємо найближчу до центру екрана подію: мапа й карусель наводяться на неї, як після тапу. Піни на
     * екрані є — нічого не чіпаємо, карусель лишається з першої картки.
     */
    private fun revealNearest() {
        // ponytail: межі всього вікна, разом зі смугою під каруселлю; відступи врахувати, якщо пін під нею лишатиме екран «порожнім».
        val (south, west, north, east) = viewport ?: return
        val shared = app.state.value
        val shown = visibleOf(shared.map.index, shared.map.category)
        val onScreen = shown.count { it.latitude in south..north && it.longitude in west..east }
        PoruchLog.d("map") { "filter settled: ${shown.size} shown, $onScreen on screen" }
        if (shown.isEmpty() || onScreen > 0) return
        val latitude = (south + north) / 2
        val longitude = (west + east) / 2
        val nearest = shown.minBy { metersBetween(latitude, longitude, it.latitude, it.longitude) }
        app.selectEvent(nearest.id)
    }

    /**
     * «Ближче до мене»: список і карусель — від найближчої до людини, піни на мапі як були. Тримається до кінця сесії:
     * фільтри, місто й «Усі N» порядок не скидають. Повторний виклик лише посуває точку.
     */
    fun nearMe(latitude: Double, longitude: Double) {
        if (local.value.near == null) PoruchAnalytics.track("map_nearest", "on" to true, "located" to true)
        local.update { it.copy(near = latitude to longitude) }
    }

    /** «Ближче до мене» натиснули, а положення нема: дозвіл не дали чи система змовчала. Порядок лишається «для вас». */
    fun nearMeUnavailable() = PoruchAnalytics.track("map_nearest", "on" to true, "located" to false)

    /** Назад до порядку «для вас». */
    fun clearNearMe() {
        if (local.value.near == null) return
        PoruchAnalytics.track("map_nearest", "on" to false)
        local.update { it.copy(near = null) }
    }

    /** Вихід із закладу в місто: пошук, інше місто чи область, «до міста», «Усі N». Фільтри стос не скидають — звужують. */
    fun resetStack() = local.update { it.copy(stackIds = emptyList(), stackPoints = emptySet()) }

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
    fun toggleCategory(category: EventCategory) {
        val picking = app.state.value.map.category != category
        val shown = state.value
        // Нуль у місті, а не в закладі чи під пошуком: якого жанру людям бракує, тобто куди шукати нові джерела афіші.
        if (picking && shown.countOf(category) == 0 && !shown.stackFocused && shown.searchText.isBlank()) {
            PoruchAnalytics.track(
                "empty_category", "category" to category.key, "date" to shown.dateFilter.name.lowercase(),
                "people" to shown.onlyAvailable
            )
        }
        app.setCategory(if (picking) category else null)
    }

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

    private fun visibleOf(index: List<EventIndexEntry>, category: EventCategory?) =
        if (category == null) index else index.filter { it.category == category }

    private fun sameInputs(old: AppState, new: AppState): Boolean =
        old.map === new.map && old.cards === new.cards && old.detail === new.detail &&
            old.library === new.library && old.city === new.city && old.session === new.session

    private fun derive(shared: AppState, local: ExploreLocal): ExploreScreenState {
        val index = shared.map.index
        val category = shared.map.category
        // Індекс, звужений категорією: той самий екземпляр, поки не змінились індекс чи категорія, — мапа не переписує GeoJSON.
        val from = visibleFrom
        if (from == null || from.first !== index || from.second != category) {
            visible = visibleOf(index, category)
            visibleFrom = index to category
        }
        val focused = shared.detail.event
        // Сеанс прокату «вже там» через представника, інакше пін майданчика рахував би прокат двічі.
        val present = focused == null || visible.any { entry -> entry.id == focused.id || entry.sessions.any { it.id == focused.id } }
        val mapEvents = if (present) visible else visible + focused!!.asIndexEntry()
        val stackFocused = local.stackPoints.isNotEmpty()
        // Під тими самими фільтрами, що й мапа: категорія, дата й «Від людей» діють і в закладі.
        val stack = if (stackFocused) visible.filter { (it.latitude to it.longitude) in local.stackPoints } else emptyList()
        val near = local.near
        val shown = if (stackFocused) stack else mapEvents
        val listEntries = if (near == null) shown else shown.sortedBy { metersBetween(near.first, near.second, it.latitude, it.longitude) }
        // Числа плиток — з того, що звужує категорія: усе місто чи точки стосу. Дату, «Від людей» і пошук уже відібрав сервер.
        val settled = !shared.map.loading && shared.map.answered == shared.map.queries
        val counted = if (stackFocused) index.filter { (it.latitude to it.longitude) in local.stackPoints } else index
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
            stackIds = stack.map { it.id },
            stackFocused = stackFocused,
            stackPlace = stackPlace,
            stackFollowing = stackPlace != null && shared.isFollowing(FollowKind.PLACE, stackPlace.id),
            indexVersion = shared.map.indexVersion,
            arrivals = shared.map.arrivals,
            queries = shared.map.queries,
            focusToken = local.focusToken,
            categoryCounts = if (settled) counted.groupingBy { it.category }.eachCount() else null,
            nearMe = near != null,
            nearLatitude = near?.first ?: 0.0,
            nearLongitude = near?.second ?: 0.0
        )
    }
}

/**
 * Відстань у метрах на масштабі міста: плоска проєкція з поправкою на широту. Градус довготи коротший за градус широти,
 * і без поправки «найближча» тягнулась би на схід чи захід. Ділять «найближча до центру екрана» й «Ближче до мене».
 */
internal fun metersBetween(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double): Double {
    val squeeze = cos((fromLatitude + toLatitude) / 2 * PI / 180)
    return hypot(toLatitude - fromLatitude, (toLongitude - fromLongitude) * squeeze) * METERS_PER_DEGREE
}

/** Метрів в одному градусі широти: π/180 радіуса Землі. */
private const val METERS_PER_DEGREE = 111_195.0
