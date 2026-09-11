package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.datetime.*
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.math.abs
import kotlin.time.Clock

/**
 * Owns the map query: where we are looking, what we are filtering by, and the one in-flight search.
 * Split out of [PoruchApp] because these are the only pieces of state that change on every pan of
 * the map, and keeping them together is what makes "a stale answer must not replace a fresh one"
 * checkable in one place.
 */
internal class DiscoveryEngine(
    private val events: EventDiscovery,
    private val geo: GeoSearchRepository,
    private val state: MutableStateFlow<AppState>,
    private val scope: CoroutineScope,
    home: HomeLocation,
    /**
     * Де рахувати те, що не має рахуватись на UI-потоці: ранжування всієї видачі й розбір кеша.
     *
     * Порожній контекст за замовчуванням — це не «нікуди»: `withContext(EmptyCoroutineContext)`
     * лишає виклик там, де він був, і йде швидким шляхом без перемикання. Завдяки цьому тест під
     * `runTest` лишається на своєму планувальнику й нічого про цей параметр не знає, а збірка
     * підставляє [kotlinx.coroutines.Dispatchers.Default] у [AppGraph].
     */
    private val compute: CoroutineContext = EmptyCoroutineContext
) {
    private var query = EventQuery(home.south, home.west, home.north, home.east)
    private var searchJob: Job? = null
    private var cardsJob: Job? = null
    private var debounceJob: Job? = null
    private var cityJob: Job? = null

    /** Called whenever a query change should also drop the open event card. */
    var onQueryChanged: () -> Unit = {}

    fun refresh() {
        searchJob?.cancel()
        cardsJob?.cancel()
        val snapshot = query
        searchJob = scope.launch {
            state.update { it.copy(loading = true) }
            PoruchLog.d("discovery") {
                "search ${snapshot.south},${snapshot.west}..${snapshot.north},${snapshot.east} " +
                    "category=${snapshot.category ?: ALL_CATEGORIES} from=${snapshot.from ?: "now"} " +
                    "text=${if (snapshot.text.isNullOrBlank()) "-" else "yes"} available=${snapshot.available}"
            }
            try {
                val page = events.discover(snapshot)
                PoruchLog.i("discovery") { "${page.total} events, ${page.cards.size} cards inline" }
                publish(page, offline = false, failure = null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Offline is not empty: the last answer for this area is still the best one we have.
                val cached = withContext(compute) { events.cached(snapshot) }
                PoruchLog.e("discovery", e) { "search failed, showing ${cached.index.size} cached events" }
                publish(cached, offline = true, failure = e.asAppError())
            }
        }
    }

    /**
     * Домалювати картки до [count] перших у порядку показу.
     *
     * Стрічка кличе це, коли прокрутила до краю того, що вже є. Індекс повний з першої відповіді,
     * тож «далі» — це не наступна сторінка з сервера, а просто ще кілька карток за вже відомими
     * ідентифікаторами: серверу не треба знати ні порядку, ні того, скільки ми вже показали.
     */
    fun materialize(count: Int) {
        if (cardsJob?.isActive == true) return
        load(state.value.index.take(count).map { it.id })
    }

    /**
     * Картки для названих подій — стос майданчика, у який щойно тицьнули.
     *
     * Окремо від [materialize], бо стос не є початком списку: у Києві є майданчик із 32 подіями,
     * і жодна з них, крім перших двох, у вікно не потрапляє. Без цього пін казав «32», а карусель
     * під ним — «Тут подій: 2», і решта стосу була недосяжна — рівно та вада, заради якої пін
     * узагалі віддає всі ідентифікатори під пальцем.
     *
     * Скасовує поточне довантаження вікна: людина дивиться сюди, а не на кінець стрічки.
     */
    fun loadCards(ids: List<String>) {
        cardsJob?.cancel()
        load(ids)
    }

    private fun load(ids: List<String>) {
        val known = state.value.cards
        val wanted = ids.filterNot { it in known }
        if (wanted.isEmpty()) return
        cardsJob = scope.launch {
            try {
                val loaded = events.cards(wanted)
                state.update { current ->
                    current.copy(cards = current.cards + loaded.associateBy { card -> card.id }).materialized()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Вікно, яке не приїхало, — це коротша стрічка, а не зламаний екран. Мапа вже
                // показує все, що є, тож банер тут був би про чужу проблему.
                PoruchLog.w("discovery") { "cards for ${wanted.size} ids failed: ${e.asAppError()}" }
            }
        }
    }

    /**
     * Кладе видачу в стан: знімок входів на місці, рахунок поза потоком, одне атомарне оновлення.
     *
     * Форма тут важливіша за вміст. Спокусливо було б прочитати `state.value` всередині
     * [withContext] і записати результат після — але це перетворює атомарний `update` на
     * «прочитав, подумав, записав», і паралельна закладка чи щойно збережені відповіді
     * онбордингу загубились би між першим і третім. Тому назовні їде лише те, що порахували, а
     * все інше береться зі стану всередині `update`, у тій самій точці, де його й пишуть.
     *
     * Після [withContext] виконання повертається на диспетчер scope — тобто на головний потік.
     * Публікація лишається там за побудовою, а не тому, що хтось про це памʼятав.
     */
    private suspend fun publish(page: DiscoveryPage, offline: Boolean, failure: AppError?) {
        val taste = state.value.taste
        // Склеювання перед ранжуванням, а не після: інакше той самий концерт двічі отримав би бали
        // й двічі змагався б за місце нагорі. І поза `update`, щоб обидві гілки нижче бачили вже
        // склеєний список — інакше рідкісна гілка «смак змінився поки рахували» показала б дублі.
        val folded = withContext(compute) { DuplicateEvents.fold(page.index) }
        if (folded.size != page.index.size) {
            PoruchLog.i("discovery") { "${page.index.size - folded.size} duplicates folded away" }
        }
        val ranking = withContext(compute) {
            val ordered = TasteRanking.rank(folded, taste, Clock.System.now())
            ordered to TasteRanking.matching(ordered, taste)
        }
        state.update {
            // Картки старої області викидаємо разом з нею: тримати їх означало б платити памʼяттю
            // за подію, яку вже не показують, і ризикувати застарілим числом місць у кімнаті.
            val base = it.copy(
                index = folded,
                cards = page.cards.associateBy { card -> card.id },
                // Склеєні дублікати не рахуємо двічі: людина бачить стільки карток, скільки тут
                // написано. Різницю додаємо лише тоді, коли спрацював запобіжник — тоді частину
                // подій ми справді не забрали й порахувати їх самі не можемо.
                totalFound = folded.size + (page.total - page.index.size),
                loading = false, offline = offline,
                notice = when {
                    failure != null -> AppNotice.Failed(failure)
                    page.truncated -> AppNotice.Told(AppMessage.ZOOM_IN_FOR_MORE)
                    else -> it.notice
                }
            )
            // Відповіді могли змінитися, поки ми рахували. Тоді порахований порядок уже не про
            // цю людину, і дешевше перерахувати, ніж показати чужий.
            if (it.taste == taste) base.copy(index = ranking.first, suggestedIndex = ranking.second).materialized()
            else base.ranked()
        }
        // Смак міг переставити порядок так, що перші картки з відповіді вже не перші. Одна
        // подорож наздоганяє — і то лише для того, хто проходив онбординг.
        materialize(DiscoveryRules.FIRST_CARDS)
    }

    fun searchArea(south: Double, west: Double, north: Double, east: Double) {
        if (listOf(south, west, north, east).any { !it.isFinite() } || south > north) return
        // Map SDKs can return unwrapped longitudes after panning across the dateline.
        fun longitude(value: Double) = ((value + 180.0) % 360.0 + 360.0) % 360.0 - 180.0
        val wholeWorld = abs(east - west) >= 360.0
        query = query.copy(
            south = south.coerceIn(-90.0, 90.0), west = if (wholeWorld) -180.0 else longitude(west),
            north = north.coerceIn(-90.0, 90.0), east = if (wholeWorld) 180.0 else longitude(east)
        )
        onQueryChanged(); refresh()
    }

    fun setSearchText(text: String) {
        val trimmed = text.take(DiscoveryRules.SEARCH_TEXT_LIMIT)
        if (trimmed == state.value.searchText) return
        state.update { it.copy(searchText = trimmed, loading = true) }
        query = query.copy(text = trimmed.trim().takeIf { it.isNotEmpty() })
        debounceJob?.cancel(); searchJob?.cancel(); onQueryChanged()
        debounceJob = scope.launch { delay(DiscoveryRules.SEARCH_DEBOUNCE_MS); refresh() }
    }

    fun setOnlyAvailable(available: Boolean) {
        state.update { it.copy(onlyAvailable = available) }
        query = query.copy(available = available); onQueryChanged(); refresh()
    }

    fun setCategory(category: String) {
        state.update { it.copy(category = category) }
        query = query.copy(category = category.takeUnless { it == ALL_CATEGORIES })
        onQueryChanged(); refresh()
    }

    fun setDateFilter(filter: String) {
        val zone = TimeZone.currentSystemDefault()
        val now = Clock.System.now()
        val today = now.toLocalDateTime(zone).date
        // The weekend runs from Saturday 00:00 to Monday 00:00, however far away it currently is.
        val daysToSaturday = (6 - today.dayOfWeek.isoDayNumber).coerceAtLeast(0)
        val start = when (filter) {
            DateFilter.TODAY -> today.atStartOfDayIn(zone)
            DateFilter.WEEKEND -> today.plus(daysToSaturday, DateTimeUnit.DAY).atStartOfDayIn(zone)
            else -> now
        }
        val end = when (filter) {
            DateFilter.TODAY -> today.plus(1, DateTimeUnit.DAY).atStartOfDayIn(zone)
            DateFilter.WEEKEND -> today.plus(8 - today.dayOfWeek.isoDayNumber, DateTimeUnit.DAY).atStartOfDayIn(zone)
            else -> null
        }
        state.update { it.copy(dateFilter = filter) }
        query = query.copy(from = start.toString(), to = end?.toString())
        refresh()
    }

    fun searchCity(text: String) {
        cityJob?.cancel()
        if (text.trim().length < DiscoveryRules.MIN_CITY_QUERY) {
            state.update { it.copy(cities = emptyList()) }
            return
        }
        cityJob = scope.launch {
            delay(DiscoveryRules.CITY_DEBOUNCE_MS)
            try {
                val result = geo.search(text)
                PoruchLog.d("geo") { "city suggestions: ${result.size}" }
                state.update { it.copy(cities = result) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                state.update { it.copy(notice = AppNotice.Failed(e.asAppError())) }
            }
        }
    }

    fun selectCity(city: CityResult) {
        PoruchLog.i("discovery") { "city → ${city.name}" }
        state.update {
            it.copy(cityName = city.name, cityLatitude = city.latitude, cityLongitude = city.longitude, cities = emptyList())
        }
        val view = HomeLocation(city.name, city.latitude, city.longitude)
        searchArea(view.south, view.west, view.north, view.east)
    }
}
