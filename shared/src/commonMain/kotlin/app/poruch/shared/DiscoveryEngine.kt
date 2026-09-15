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
 * Тримає запит мапи: область, фільтри й один активний пошук. Винесено з [PoruchApp], бо це
 * єдиний стан, що змінюється на кожен рух мапи, і правило «стара відповідь не перекриває
 * свіжу» перевіряється в одному місці.
 */
internal class DiscoveryEngine(
    private val events: EventDiscovery,
    private val geo: GeoSearchRepository,
    private val state: MutableStateFlow<AppState>,
    private val scope: CoroutineScope,
    home: HomeLocation,
    /**
     * Де рахувати ранжування й розбір кеша. Порожній контекст лишає виклик на місці, тож тести
     * під `runTest` нічого не знають; [AppGraph] підставляє `Dispatchers.Default`.
     */
    private val compute: CoroutineContext = EmptyCoroutineContext
) {
    private var query = EventQuery(home.south, home.west, home.north, home.east)
    private var searchJob: Job? = null
    private var cardsJob: Job? = null
    private var sessionsJob: Job? = null
    private var sessionsWanted: Set<String> = emptySet()
    private var debounceJob: Job? = null
    private var cityJob: Job? = null

    /** Викликається, коли зміна запиту має закрити відкриту картку. */
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
                // Офлайн — не порожньо: остання відповідь для області все ще найкраща.
                val cached = withContext(compute) { events.cached(snapshot) }
                PoruchLog.e("discovery", e) { "search failed, showing ${cached.index.size} cached events" }
                publish(cached, offline = true, failure = e.asAppError())
            }
        }
    }

    /** Довантажити картки до [count] перших у порядку показу. Не пагінація: індекс повний, id відомі. */
    fun materialize(count: Int) {
        if (cardsJob?.isActive == true) return
        load(state.value.index.take(count).map { it.id })?.let { cardsJob = it }
    }

    /**
     * Картки для стосу майданчика, в який тицьнули. Окремо від [materialize], бо стос — не
     * початок списку. Скасовує поточне довантаження вікна: людина дивиться сюди.
     */
    fun loadCards(ids: List<String>) {
        cardsJob?.cancel()
        load(ids)?.let { cardsJob = it }
    }

    /**
     * Картки решти сеансів прокату, відкритого на деталях, щоб перемикання дати не показувало
     * порожній екран. Окреме завдання, щоб не збивати довантаження стрічки. Запит за тими самими
     * id не скасовується: безумовний `cancel()` губив повільну відповідь саме при перемиканні дати.
     */
    fun prefetch(ids: List<String>) {
        if (sessionsJob?.isActive == true && sessionsWanted.containsAll(ids)) return
        load(ids)?.let {
            sessionsJob = it
            sessionsWanted = ids.toSet()
        }
    }

    /** Довантажує картки, яких ще немає. Null, якщо питати нема чого. */
    private fun load(ids: List<String>): Job? {
        val known = state.value.cards
        val wanted = ids.filterNot { it in known }
        if (wanted.isEmpty()) return null
        return scope.launch {
            try {
                val loaded = events.cards(wanted)
                state.update { current ->
                    current.copy(cards = current.cards + loaded.associateBy { card -> card.id }).materialized()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Вікно не приїхало — коротша стрічка, а не банер: мапа вже показує все.
                PoruchLog.w("discovery") { "cards for ${wanted.size} ids failed: ${e.asAppError()}" }
            }
        }
    }

    /**
     * Кладе видачу в стан: рахунок поза потоком, потім одне атомарне `update`. Всередині
     * `update` читаємо лише стан, а не `state.value` до `withContext`, інакше паралельна закладка
     * чи відповіді онбордингу загубилися б. Після `withContext` ми знову на головному потоці.
     */
    private suspend fun publish(page: DiscoveryPage, offline: Boolean, failure: AppError?) {
        val taste = state.value.taste
        // Склеюємо до ранжування, щоб дубль не отримав бали двічі. Порядок обов'язковий:
        // спершу дублі між продавцями, потім прокат, інакше один вечір став би двома сеансами.
        val folded = withContext(compute) { EventSeries.fold(DuplicateEvents.fold(page.index)) }
        if (folded.size != page.index.size) {
            val series = folded.count { it.isSeries }
            PoruchLog.i("discovery") {
                "${page.index.size - folded.size} rows folded away, $series runs"
            }
        }
        val ranking = withContext(compute) {
            val ordered = TasteRanking.rank(folded, taste, Clock.System.now())
            ordered to TasteRanking.matching(ordered, taste)
        }
        state.update {
            // Картки старої області викидаємо: пам'ять і застарілі числа місць того не варті.
            val base = it.copy(
                index = folded,
                cards = page.cards.associateBy { card -> card.id },
                // Склеєні дублікати не рахуємо двічі. Різниця з page.total — лише коли спрацював запобіжник.
                totalFound = folded.size + (page.total - page.index.size),
                loading = false, offline = offline,
                notice = when {
                    failure != null -> AppNotice.Failed(failure)
                    page.truncated -> AppNotice.Told(AppMessage.ZOOM_IN_FOR_MORE)
                    else -> it.notice
                }
            )
            // Смак міг змінитися, поки рахували: тоді перераховуємо.
            if (it.taste == taste) base.copy(index = ranking.first, suggestedIndex = ranking.second).materialized()
            else base.ranked()
        }
        // Смак міг переставити порядок так, що перші картки з відповіді вже не перші.
        materialize(DiscoveryRules.FIRST_CARDS)
    }

    fun searchArea(south: Double, west: Double, north: Double, east: Double) {
        if (listOf(south, west, north, east).any { !it.isFinite() } || south > north) return
        // SDK мап віддають незагорнуті довготи після переходу через лінію зміни дат.
        fun longitude(value: Double) = ((value + 180.0) % 360.0 + 360.0) % 360.0 - 180.0
        val wholeWorld = abs(east - west) >= 360.0
        query = query.copy(
            south = south.coerceIn(-90.0, 90.0), west = if (wholeWorld) -180.0 else longitude(west),
            north = north.coerceIn(-90.0, 90.0), east = if (wholeWorld) 180.0 else longitude(east)
        )
        // Область поставили рукою. [selectCity] одразу після цього скине прапорець.
        state.update { it.copy(customArea = true) }
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

    /**
     * Категорія мапи, без запиту до сервера: індекс один на всі екрани, тож фільтр на сервері
     * звужував би й головну. Сервер віддає місто цілим, категорію відбирає екран.
     */
    fun setCategory(category: String) {
        state.update { it.copy(category = category) }
        onQueryChanged()
    }

    fun setDateFilter(filter: String) {
        val zone = TimeZone.currentSystemDefault()
        val now = Clock.System.now()
        val today = now.toLocalDateTime(zone).date
        // Вихідні — з суботи 00:00 до понеділка 00:00, найближчі.
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
        // Область міста — не «рукою», хоч її й поставив searchArea.
        state.update { it.copy(customArea = false) }
    }
}
