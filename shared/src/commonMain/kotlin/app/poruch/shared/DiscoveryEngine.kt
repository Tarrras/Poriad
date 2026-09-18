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
import kotlin.time.Duration.Companion.milliseconds

/**
 * Тримає запит мапи: область, фільтри й один активний пошук. І стрічку головної ([HomeFeed]):
 * та сама область без фільтрів мапи і зі своїм пошуком. Винесено з [PoruchApp], бо це
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
    /** Межі обраного міста. Головна завжди дивиться сюди; «Шукати тут» рухає лише мапу. */
    private var cityArea = EventQuery(home.south, home.west, home.north, home.east)
    private var searchJob: Job? = null
    private var cardsJob: Job? = null
    private var sessionsJob: Job? = null
    private var sessionsWanted: Set<String> = emptySet()
    private var debounceJob: Job? = null
    private var cityJob: Job? = null
    private var homeJob: Job? = null
    private var homeCardsJob: Job? = null
    private var homeSearchJob: Job? = null
    private var homeDebounceJob: Job? = null
    /** Коли мапа й головна востаннє отримали відповідь мережі. Null — ще ні або офлайн. */
    private var freshAt: kotlin.time.Instant? = null
    /** Поточний [searchJob] несе й стрічку головної: мапа була без фільтрів. */
    private var sharedPending = false
    /**
     * Картки, по які вже пішли, і завдання, що їх везе. Мапа й головна просять той самий
     * початок видачі одночасно. Скасоване завдання одразу неактивне, тож його id знову вільні.
     */
    private val inFlight = HashMap<String, Job>()

    /** Викликається, коли зміна запиту має закрити відкриту картку. */
    var onQueryChanged: () -> Unit = {}

    /**
     * Перечитує мапу, а з [home] і головну. Поки мапа без фільтрів, їхні запити однакові, тож
     * головна їде тим самим запитом. Зміна фільтра мапи ([home] = false) головну не чіпає.
     */
    fun refresh(home: Boolean = true) {
        // Скасовуємо запит, що ніс і головну: тоді вона мусить поїхати сама.
        val needHome = home || (sharedPending && searchJob?.isActive == true)
        searchJob?.cancel()
        cardsJob?.cancel()
        val shared = needHome && mapUnfiltered()
        sharedPending = shared
        if (shared) homeJob?.cancel() else if (needHome) refreshHome()
        // Нова область — нові результати пошуку головної.
        if (home) searchHome()
        val snapshot = query
        searchJob = scope.launch {
            state.update { it.copy(loading = true, home = if (shared) it.home.copy(loading = true) else it.home) }
            PoruchLog.d("discovery") {
                "search ${snapshot.south},${snapshot.west}..${snapshot.north},${snapshot.east} " +
                    "category=${snapshot.category ?: ALL_CATEGORIES} from=${snapshot.from ?: "now"} " +
                    "text=${if (snapshot.text.isNullOrBlank()) "-" else "yes"} available=${snapshot.available}"
            }
            try {
                val page = events.discover(snapshot)
                PoruchLog.i("discovery") { "${page.total} events, ${page.cards.size} cards inline" }
                publish(page, offline = false, failure = null, home = shared)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Офлайн — не порожньо: остання відповідь для області все ще найкраща.
                val cached = withContext(compute) { events.cached(snapshot) }
                PoruchLog.e("discovery", e) { "search failed, showing ${cached.index.size} cached events" }
                publish(cached, offline = true, failure = e.asAppError(), home = shared)
            }
        }
    }

    /**
     * Повернення в застосунок. На старті платформа кличе його одразу після першого пошуку, і
     * безумовний [refresh] скасовував запит у дорозі та слав такий самий.
     */
    fun refreshIfStale() {
        if (searchJob?.isActive == true) return
        val fresh = freshAt
        if (fresh != null && Clock.System.now() - fresh < DiscoveryRules.RESUME_FRESH_MS.milliseconds) return
        refresh()
    }

    /**
     * Мапа показує ціле місто без фільтрів: її запит збігається з запитом головної. Категорія
     * в запит не їде взагалі.
     */
    private fun mapUnfiltered() =
        !state.value.customArea && query.text == null && !query.available && state.value.dateFilter == DateFilter.ANY

    /** Запит головної: ціле місто, без фільтрів мапи. */
    private fun areaQuery() = cityArea

    /** Стрічка головної окремим запитом, коли мапа звужена фільтрами. */
    private fun refreshHome() {
        homeJob?.cancel()
        val snapshot = areaQuery()
        homeJob = scope.launch {
            state.update { it.copy(home = it.home.copy(loading = true)) }
            val page = try {
                events.discover(snapshot)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Про збій уже скаже мапа своїм банером; головна тихо бере кеш.
                PoruchLog.w("discovery") { "home feed failed: ${e.asAppError()}" }
                withContext(compute) { events.cached(snapshot) }
            }
            val ranked = rank(page)
            state.update {
                it.copy(
                    cards = it.cards + page.cards.associateBy { card -> card.id },
                    home = it.home.copy(
                        index = ranked.index, suggestedIndex = ranked.suggested,
                        totalFound = ranked.total, loading = false
                    )
                ).settled(ranked.taste)
            }
            materializeHome()
        }
    }

    /** Пошук головної в тій самій області, без фільтрів мапи. */
    fun setHomeSearchText(text: String) {
        val trimmed = text.take(DiscoveryRules.SEARCH_TEXT_LIMIT)
        if (trimmed == state.value.home.searchText) return
        homeDebounceJob?.cancel(); homeSearchJob?.cancel()
        val blank = trimmed.isBlank()
        state.update {
            it.copy(
                home = if (blank) it.home.copy(searchText = trimmed, results = emptyList(), found = emptyList(), resultsTotal = 0, searchLoading = false)
                else it.home.copy(searchText = trimmed, searchLoading = true)
            )
        }
        if (!blank) homeDebounceJob = scope.launch { delay(DiscoveryRules.SEARCH_DEBOUNCE_MS); searchHome() }
    }

    private fun searchHome() {
        homeDebounceJob?.cancel(); homeSearchJob?.cancel()
        val text = state.value.home.searchText.trim()
        if (text.isEmpty()) return
        val snapshot = areaQuery().copy(text = text)
        homeSearchJob = scope.launch {
            state.update { it.copy(home = it.home.copy(searchLoading = true)) }
            try {
                val page = events.discover(snapshot)
                val ranked = rank(page)
                state.update {
                    it.copy(
                        cards = it.cards + page.cards.associateBy { card -> card.id },
                        home = it.home.copy(results = ranked.index, resultsTotal = ranked.total, searchLoading = false)
                    ).settled(ranked.taste)
                }
                materializeHome()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                state.update { it.copy(home = it.home.copy(searchLoading = false), notice = AppNotice.Failed(e.asAppError())) }
            }
        }
    }

    /** Картки, які головна показує першими: добірка, початок стрічки й пошуку. */
    private fun materializeHome() {
        val home = state.value.home
        val ids = (home.suggestedIndex.take(DiscoveryRules.FIRST_CARDS) + home.index.take(DiscoveryRules.FIRST_CARDS) +
            home.results.take(DiscoveryRules.FIRST_CARDS)).map { it.id }.distinct()
        load(ids)?.let { homeCardsJob?.cancel(); homeCardsJob = it }
    }

    /** Чекає, поки доїдуть поточні пошуки. Без пошуку або скасований — повертається одразу. */
    suspend fun awaitSearch() { searchJob?.join(); homeJob?.join(); homeSearchJob?.join() }

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
        val wanted = ids.filterNot { it in known || inFlight[it]?.isActive == true }
        if (wanted.isEmpty()) return null
        val job = scope.launch(start = CoroutineStart.LAZY) {
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
            } finally {
                val self = coroutineContext[Job]
                for (id in wanted) if (inFlight[id] === self) inFlight.remove(id)
            }
        }
        for (id in wanted) inFlight[id] = job
        job.start()
        return job
    }

    /** Видача після склейки й ранжування. [taste] — смак, яким рахували. */
    private class Ranked(val index: List<EventIndexEntry>, val suggested: List<EventIndexEntry>, val total: Int, val taste: Taste)

    /** Склеює й ранжує видачу поза головним потоком. */
    private suspend fun rank(page: DiscoveryPage): Ranked {
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
        return withContext(compute) {
            val ordered = TasteRanking.rank(folded, taste, Clock.System.now())
            // Склеєні дублікати не рахуємо двічі. Різниця з page.total — лише коли спрацював запобіжник.
            Ranked(ordered, TasteRanking.matching(ordered, taste), folded.size + (page.total - page.index.size), taste)
        }
    }

    /** Смак міг змінитися, поки рахували: тоді перераховуємо. */
    private fun AppState.settled(taste: Taste) = if (this.taste == taste) materialized() else ranked()

    /**
     * Кладе видачу мапи в стан, з [home] — і в головну. Рахунок поза потоком, потім одне атомарне
     * `update`. Всередині `update` читаємо лише стан, а не `state.value` до `withContext`, інакше
     * паралельна закладка чи відповіді онбордингу загубилися б.
     */
    private suspend fun publish(page: DiscoveryPage, offline: Boolean, failure: AppError?, home: Boolean) {
        val ranked = rank(page)
        state.update {
            // Картки старої області викидаємо: пам'ять і застарілі числа місць того не варті.
            // Крім тих, що показує головна: її видача від фільтрів мапи не залежить.
            val keep = it.home.shownIds()
            it.copy(
                index = ranked.index, suggestedIndex = ranked.suggested, indexVersion = it.indexVersion + 1,
                cards = it.cards.filterKeys { id -> id in keep } + page.cards.associateBy { card -> card.id },
                totalFound = ranked.total,
                loading = false, offline = offline,
                notice = when {
                    failure != null -> AppNotice.Failed(failure)
                    page.truncated -> AppNotice.Told(AppMessage.ZOOM_IN_FOR_MORE)
                    else -> it.notice
                },
                home = if (home) it.home.copy(
                    index = ranked.index, suggestedIndex = ranked.suggested, totalFound = ranked.total, loading = false
                ) else it.home
            ).settled(ranked.taste)
        }
        sharedPending = false
        // Свіжа лише повна відповідь мережі: після офлайну повернення в застосунок має перепитати.
        freshAt = if (offline) null else if (home) Clock.System.now() else freshAt
        // Смак міг переставити порядок так, що перші картки з відповіді вже не перші.
        materialize(DiscoveryRules.FIRST_CARDS)
        if (home) materializeHome()
    }

    /** «Шукати тут»: область лише для мапи. Головна лишається на цілому місті й не перепитує. */
    fun searchArea(south: Double, west: Double, north: Double, east: Double) {
        if (!moveTo(south, west, north, east)) return
        state.update { it.copy(customArea = true) }
        onQueryChanged(); refresh(home = false)
    }

    /** Ставить область запиту мапи. False — межі непридатні, нічого не змінено. */
    private fun moveTo(south: Double, west: Double, north: Double, east: Double): Boolean {
        if (listOf(south, west, north, east).any { !it.isFinite() } || south > north) return false
        // SDK мап віддають незагорнуті довготи після переходу через лінію зміни дат.
        fun longitude(value: Double) = ((value + 180.0) % 360.0 + 360.0) % 360.0 - 180.0
        val wholeWorld = abs(east - west) >= 360.0
        query = query.copy(
            south = south.coerceIn(-90.0, 90.0), west = if (wholeWorld) -180.0 else longitude(west),
            north = north.coerceIn(-90.0, 90.0), east = if (wholeWorld) 180.0 else longitude(east)
        )
        return true
    }

    fun setSearchText(text: String) {
        val trimmed = text.take(DiscoveryRules.SEARCH_TEXT_LIMIT)
        if (trimmed == state.value.searchText) return
        state.update { it.copy(searchText = trimmed, loading = true) }
        query = query.copy(text = trimmed.trim().takeIf { it.isNotEmpty() })
        debounceJob?.cancel(); searchJob?.cancel(); onQueryChanged()
        debounceJob = scope.launch { delay(DiscoveryRules.SEARCH_DEBOUNCE_MS); refresh(home = false) }
    }

    fun setOnlyAvailable(available: Boolean) {
        state.update { it.copy(onlyAvailable = available) }
        query = query.copy(available = available); onQueryChanged(); refresh(home = false)
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
        refresh(home = false)
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
        if (!moveTo(view.south, view.west, view.north, view.east)) return
        cityArea = EventQuery(query.south, query.west, query.north, query.east)
        state.update { it.copy(customArea = false) }
        // Нове місто — і для мапи, і для головної.
        onQueryChanged(); refresh()
    }
}
