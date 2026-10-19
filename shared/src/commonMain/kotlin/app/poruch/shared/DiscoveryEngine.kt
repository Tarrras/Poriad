package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.*
import kotlinx.datetime.*
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.math.abs
import kotlin.time.Clock
import kotlin.time.Duration.Companion.milliseconds

/**
 * Тримає запит мапи: область, фільтри й один активний пошук, а ще місто й довантаження карток. Головну ([HomeFeed])
 * веде [homeFeed]: та сама область без фільтрів мапи і зі своїм пошуком. Винесено з [PoruchApp], бо це єдиний стан,
 * що змінюється на кожен рух мапи, і правило «стара відповідь не перекриває свіжу» тримає [LatestJob].
 */
internal class DiscoveryEngine(
    private val events: EventDiscovery,
    private val geo: GeoSearchRepository,
    private val store: AppStore,
    private val scope: CoroutineScope,
    home: HomeLocation,
    /**
     * Де рахувати ранжування й розбір кеша. Порожній контекст лишає виклик на місці, тож тести
     * під `runTest` нічого не знають; [AppGraph] підставляє `Dispatchers.Default`.
     */
    private val compute: CoroutineContext = EmptyCoroutineContext,
    /** Куди запам'ятати обране місто для наступного запуску. */
    private val cityStore: CityStore? = null
) {
    private var query = EventQuery(home.south, home.west, home.north, home.east)

    /** Стрічка й пошук головної. Межі обраного міста ([HomeDiscovery.area]) теж там: головна завжди дивиться туди. */
    val homeFeed = HomeDiscovery(events, store, scope, compute, home, ::load)

    private val searchJob = LatestJob(scope)
    private val cardsJob = LatestJob(scope)
    private val debounceJob = LatestJob(scope)
    private val cityJob = LatestJob(scope)

    /** Пошук закладів мапи. Кожен новий скасовує попередній: останній запит виграє. */
    private val placesJob = LatestJob(scope)

    /** Не [LatestJob]: сеанси для інших id не скасовують попередні, див. [prefetch]. */
    private var sessionsJob: Job? = null
    private var sessionsWanted: Set<String> = emptySet()

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

    /** Кожна зміна запиту мапи йде сюди, щоб жоден шлях не забув зняти вибір. Див. [MapFeed.queries]. */
    private fun queryChanged() {
        onQueryChanged()
        store.update { it.copy(map = it.map.copy(queries = it.map.queries + 1)) }
    }

    /**
     * Перечитує мапу, а з [home] і головну. Поки мапа без фільтрів, їхні запити однакові, тож
     * головна їде тим самим запитом. Зміна фільтра мапи ([home] = false) головну не чіпає.
     */
    fun refresh(home: Boolean = true) {
        // Скасовуємо запит, що ніс і головну: тоді вона мусить поїхати сама.
        val needHome = home || (sharedPending && searchJob.active)
        searchJob.cancel()
        cardsJob.cancel()
        val shared = needHome && mapUnfiltered()
        sharedPending = shared
        if (shared) homeFeed.cancelRefresh() else if (needHome) homeFeed.refresh()
        // Нова область — нові результати пошуку головної.
        if (home) homeFeed.search()
        val snapshot = query
        searchPlaces(snapshot)
        searchJob.launch {
            store.update {
                it.copy(
                    map = it.map.copy(loading = true),
                    home = if (shared) it.home.copy(loading = true) else it.home
                )
            }
            PoruchLog.d("discovery") {
                "search ${snapshot.south},${snapshot.west}..${snapshot.north},${snapshot.east} " +
                        "category=${snapshot.category?.key ?: "all"} from=${snapshot.from ?: "now"} " +
                        "text=${if (snapshot.text.isNullOrBlank()) "-" else "yes"} available=${snapshot.available}"
            }
            try {
                val page = events.discover(snapshot)
                PoruchLog.i("discovery") { "${page.total} events, ${page.cards.size} cards inline" }
                reportEmptyCity(page.total)
                publish(page, offline = false, failure = null, home = shared)
                answer(snapshot)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Офлайн — не порожньо: остання відповідь для області все ще найкраща.
                val cached = withContext(compute) { events.cached(snapshot) }
                PoruchLog.e(
                    "discovery",
                    e
                ) { "search failed, showing ${cached.index.size} cached events" }
                publish(cached, offline = true, failure = e.asAppError(), home = shared)
                answer(snapshot)
            }
        }
    }

    /**
     * Видача приїхала. Якщо вона на поточний запит сервера, то відповідає на всі [MapFeed.queries]: категорію екран
     * відбирає сам. Запізніла відповідь на старий запит (пошук, що вже змінився) — ні.
     */
    private fun answer(snapshot: EventQuery) {
        if (snapshot == query) store.update { it.copy(map = it.map.copy(answered = it.map.queries)) }
    }

    /**
     * Заклади за текстом мапи в її області, паралельно з [EventDiscovery.discover]. Без тексту —
     * порожньо. Збій — теж порожньо: місця доповнюють видачу, банер за них був би зайвим.
     */
    private fun searchPlaces(snapshot: EventQuery) {
        placesJob.cancel()
        val text = snapshot.text
        if (text == null) {
            if (store.value.map.places.isNotEmpty() || store.value.map.artists.isNotEmpty()) {
                store.update { it.copy(map = it.map.copy(places = emptyList(), artists = emptyList())) }
            }
            return
        }
        // Артисти не залежать від області: лише від міста, якщо воно обране, а не накреслене рукою.
        val city = store.value.city.takeIf { !it.custom }?.name
        placesJob.launch {
            launch {
                val found = events.placesOrEmpty(text, snapshot)
                store.update { it.copy(map = it.map.copy(places = found)) }
            }
            launch {
                val found = events.artistsOrEmpty(text, city)
                store.update { it.copy(map = it.map.copy(artists = found)) }
            }
        }
    }

    /**
     * Тап по закладу в пошуку мапи чи головної: мапа без тексту пошуку переходить до закладу,
     * а коли приїде видача, [PlaceFocus.eventIds] скаже платформі, який стос відкрити. Текст
     * знімаємо, бо інакше в стосі лишились би лише події, що збіглися зі словом.
     */
    fun focusPlace(place: Place) {
        debounceJob.cancel(); placesJob.cancel()
        val version = (store.value.map.placeFocus?.version ?: 0) + 1
        PoruchLog.i("discovery") { "focus place ${place.id.shortId()}" }
        store.update {
            it.copy(
                map = it.map.copy(
                    searchText = "",
                    places = emptyList(),
                    artists = emptyList(),
                    placeFocus = PlaceFocus(place, version)
                )
            )
        }
        query = query.copy(text = null)
        if (!query.covers(place)) {
            // Заклад з пошуку «усюди» в іншому місті: екран переходить у те місто, але це перегляд,
            // а не вибір — збережене місто (і чи обрано воно руками) лишається як було.
            if (place.city.isNotBlank() && place.city != store.value.city.name) {
                showCity(CityResult(place.city, place.latitude, place.longitude))
                return
            }
            val view = HomeLocation(place.city, place.latitude, place.longitude)
            if (moveTo(
                    view.south,
                    view.west,
                    view.north,
                    view.east
                )
            ) store.update { it.copy(city = it.city.copy(custom = true)) }
        }
        queryChanged(); refresh(home = false)
    }

    /** Платформа відкрила стос закладу: фокус виконано, повторне відкриття мапи його не повторить. */
    fun placeFocusShown() {
        if (store.value.map.placeFocus != null) store.update { it.copy(map = it.map.copy(placeFocus = null)) }
    }

    private fun EventQuery.covers(place: Place) =
        place.latitude in south..north && (if (west <= east) place.longitude in west..east else place.longitude >= west || place.longitude <= east)

    /**
     * Повернення в застосунок. На старті платформа кличе його одразу після першого пошуку, і
     * безумовний [refresh] скасовував запит у дорозі та слав такий самий.
     */
    fun refreshIfStale() {
        if (searchJob.active) return
        val fresh = freshAt
        if (fresh != null && Clock.System.now() - fresh < DiscoveryRules.RESUME_FRESH_MS.milliseconds) return
        refresh()
    }

    /**
     * Мапа показує ціле місто без фільтрів: її запит збігається з запитом головної. Категорія
     * в запит не їде взагалі.
     */
    private fun mapUnfiltered() =
        !store.value.city.custom && query.text == null && !query.available && store.value.map.dateFilter == DateFilter.ANY

    /** Міста, чию порожнечу вже звітували в цьому запуску: панорама мапи не має множити подію. */
    private val emptyCities = mutableSetOf<String>()

    /** Ризик №1 — людина відкрила місто без фільтрів і не побачила жодної події. */
    private fun reportEmptyCity(total: Int) {
        if (total > 0 || !mapUnfiltered() || query.category != null) return
        val city = store.value.city.name
        if (emptyCities.add(city)) PoruchAnalytics.track("empty_map", "city" to city)
    }

    /**
     * Зміна акаунта: картки в дорозі несуть членство попереднього, тож їх скасовуємо разом із
     * записами [inFlight]. Пошуки скасує наступний [refresh].
     */
    fun reset() {
        cardsJob.cancel(); homeFeed.reset(); sessionsJob?.cancel()
        inFlight.values.forEach { it.cancel() }
        inFlight.clear(); sessionsWanted = emptySet()
    }

    /**
     * Дія змінила одну подію (участь, черга, оцінка, фото): перечитуємо лише її картку, а не
     * індекс міста. Подія зникла з видачі — картку викидаємо; збій — теж, щоб не показувати
     * старе членство: наступне довантаження спитає знову.
     */
    fun reloadCard(id: String) {
        scope.launch {
            val fresh = try {
                events.cards(listOf(id)).firstOrNull { it.id == id }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("discovery") { "card ${id.shortId()} not reloaded: ${e.asAppError()}" }
                null
            }
            store.update {
                if (fresh == null && id !in it.cards) it
                else it.copy(cards = if (fresh != null) it.cards + (id to fresh) else it.cards - id)
                    .materialized()
            }
        }
    }

    /** Чекає, поки доїдуть поточні пошуки. Без пошуку або скасований — повертається одразу. */
    suspend fun awaitSearch() {
        searchJob.join(); homeFeed.await()
    }

    /** Довантажити картки до [count] перших у порядку показу. Не пагінація: індекс повний, id відомі. */
    fun materialize(count: Int) {
        if (cardsJob.active) return
        load(store.value.map.index.take(count).map { it.id })?.let(cardsJob::set)
    }

    /**
     * Картки для стосу майданчика, в який тицьнули. Окремо від [materialize], бо стос — не
     * початок списку. Скасовує поточне довантаження вікна: людина дивиться сюди.
     */
    fun loadCards(ids: List<String>) {
        cardsJob.cancel()
        load(ids)?.let(cardsJob::set)
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
        val known = store.value.cards
        val wanted = ids.filterNot { it in known || inFlight[it]?.isActive == true }
        if (wanted.isEmpty()) return null
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                val loaded = events.cards(wanted)
                store.update { current ->
                    current.copy(cards = current.cards + loaded.associateBy { card -> card.id })
                        .materialized()
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

    /**
     * Кладе видачу мапи в стан, з [home] — і в головну. Рахунок поза потоком, потім одне атомарне
     * `update`. Всередині `update` читаємо лише стан, а не `store.value` до `withContext`, інакше
     * паралельна закладка чи відповіді онбордингу загубилися б.
     */
    private suspend fun publish(
        page: DiscoveryPage,
        offline: Boolean,
        failure: AppError?,
        home: Boolean
    ) {
        val ranked = rank(page, store.value.taste, compute)
        store.update {
            // Картки старої області викидаємо: пам'ять і застарілі числа місць того не варті.
            // Крім тих, що показує головна: її видача від фільтрів мапи не залежить.
            val keep = it.home.shownIds()
            it.copy(
                map = it.map.copy(
                    index = ranked.index,
                    suggestedIndex = ranked.suggested,
                    indexVersion = it.map.indexVersion + 1,
                    totalFound = ranked.total,
                    loading = false,
                    offline = offline,
                    // Перша видача після тапу по закладу каже, які події на його піні.
                    placeFocus = it.map.placeFocus?.let { focus ->
                        if (focus.eventIds == null) focus.resolved(
                            ranked.index
                        ) else focus
                    }
                ),
                cards = it.cards.filterKeys { id -> id in keep } + page.cards.associateBy { card -> card.id },
                notice = when {
                    failure != null -> AppNotice.Failed(failure)
                    page.truncated -> AppNotice.Told(AppMessage.ZOOM_IN_FOR_MORE)
                    else -> it.notice
                },
                home = if (home) it.home.copy(
                    index = ranked.index,
                    suggestedIndex = ranked.suggested,
                    totalFound = ranked.total,
                    loading = false
                ) else it.home
            ).settled(ranked.taste)
        }
        sharedPending = false
        // Свіжа лише повна відповідь мережі: після офлайну повернення в застосунок має перепитати.
        freshAt = if (offline) null else if (home) Clock.System.now() else freshAt
        // Смак міг переставити порядок так, що перші картки з відповіді вже не перші.
        materialize(DiscoveryRules.FIRST_CARDS)
        if (home) homeFeed.materialize()
    }

    /** «Шукати тут»: область лише для мапи. Головна лишається на цілому місті й не перепитує. */
    fun searchArea(south: Double, west: Double, north: Double, east: Double) {
        if (!moveTo(south, west, north, east)) return
        store.update { it.copy(city = it.city.copy(custom = true)) }
        queryChanged(); refresh(home = false)
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
        if (trimmed == store.value.map.searchText) return
        val blank = trimmed.isBlank()
        store.update {
            it.copy(
                map = it.map.copy(
                    searchText = trimmed,
                    loading = true,
                    places = if (blank) emptyList() else it.map.places,
                    artists = if (blank) emptyList() else it.map.artists
                )
            )
        }
        query = query.copy(text = trimmed.trim().takeIf { it.isNotEmpty() })
        debounceJob.cancel(); searchJob.cancel(); placesJob.cancel(); queryChanged()
        debounceJob.launch { delay(DiscoveryRules.SEARCH_DEBOUNCE_MS); refresh(home = false) }
    }

    /**
     * Мапа з готовим набором фільтрів однією зміною запиту: перехід із головної («Усі N» біля «Від людей» чи «У місті»).
     * Скидає все, що людина лишила на мапі раніше (текст, дату, категорію, власну область), бо «Усі 378» з чужим
     * фільтром показали б менше, ніж написано. [available] — лише зустрічі від людей з вільним місцем: сервер віддає
     * рівно їх, афіша місткості не має. Запит один, а не по одному на фільтр; коли мапа вже такою була — мережі нема,
     * але [MapFeed.arrivals] росте однаково: камеру й шторки платформа повертає за цим лічильником.
     */
    fun showOnMap(available: Boolean) {
        debounceJob.cancel(); placesJob.cancel()
        val target = homeFeed.area.copy(available = available)
        val current = store.value
        val same =
            query == target && current.map.onlyAvailable == available && current.map.category == null &&
                    current.map.dateFilter == DateFilter.ANY && current.map.searchText.isEmpty() && !current.city.custom
        store.update {
            it.copy(
                map = it.map.copy(
                    searchText = "",
                    places = emptyList(),
                    artists = emptyList(),
                    onlyAvailable = available,
                    category = null,
                    dateFilter = DateFilter.ANY,
                    arrivals = it.map.arrivals + 1
                ),
                city = it.city.copy(custom = false)
            )
        }
        query = target
        queryChanged()
        if (!same) refresh(home = false)
    }

    // Фільтри: спершу [queryChanged], потім сам фільтр. Хто стежить за фільтром, може прокинутись ще всередині
    // `store.update` (Main.immediate на Android) і має вже бачити новий номер запиту, щоб чекати відповіді саме на нього.

    fun setOnlyAvailable(available: Boolean) {
        queryChanged()
        store.update { it.copy(map = it.map.copy(onlyAvailable = available)) }
        query = query.copy(available = available); refresh(home = false)
    }

    /**
     * Категорія мапи, без запиту до сервера: індекс один на всі екрани, тож фільтр на сервері
     * звужував би й головну. Сервер віддає місто цілим, категорію відбирає екран.
     */
    fun setCategory(category: EventCategory?) {
        queryChanged()
        store.update { it.copy(map = it.map.copy(category = category)) }
        // Категорію екран відбирає з того, що є: відповідь уже тут, якщо не їде видача під інший фільтр.
        if (!searchJob.active) answer(query)
    }

    fun setDateFilter(filter: DateFilter) {
        val (start, end) = dateRange(filter)
        // Як і решта фільтрів: без цього обрана подія 22.10 лишалась обраною під «Сьогодні».
        queryChanged()
        store.update { it.copy(map = it.map.copy(dateFilter = filter)) }
        query = query.copy(from = start?.toString(), to = end?.toString())
        refresh(home = false)
    }

    fun searchCity(text: String) {
        cityJob.cancel()
        if (text.trim().length < DiscoveryRules.MIN_CITY_QUERY) {
            store.update { it.copy(city = it.city.copy(suggestions = emptyList())) }
            return
        }
        cityJob.launch {
            delay(DiscoveryRules.CITY_DEBOUNCE_MS)
            try {
                val result = geo.search(text)
                PoruchLog.d("geo") { "city suggestions: ${result.size}" }
                store.update { it.copy(city = it.city.copy(suggestions = result)) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                store.failed(e.asAppError())
            }
        }
    }

    /** Геолокація на старті: місто, обране руками, не перебиває. */
    fun locatedCity(city: CityResult) {
        if (cityStore?.manual() == true) return PoruchLog.d("discovery") { "located ${city.name}, keeping manual city" }
        selectCity(city, manual = false)
    }

    /** [manual] — обрано руками; `false` — за геолокацією, і наступний старт знову піде за нею. */
    fun selectCity(city: CityResult, manual: Boolean) {
        // Те саме місто, що вже на екрані: геолокація на старті збігається з запам'ятаним, і
        // перечитувати видачу нема чого. Після «Шукати тут» повернення до міста — вже зміна.
        val current = store.value
        if (city.name == current.city.name && !current.city.custom) {
            // Видача та сама, але хто обрав — могло змінитись.
            cityStore?.write(
                CityResult(
                    current.city.name,
                    current.city.latitude,
                    current.city.longitude
                ), manual
            )
            store.update { it.copy(city = it.city.copy(suggestions = emptyList())) }
            return
        }
        PoruchLog.i("discovery") { "city → ${city.name}${if (manual) " (manual)" else ""}" }
        cityStore?.write(city, manual)
        showCity(city)
    }

    /** Місто на екрані без запису: перегляд, наступний старт його не пам'ятає. */
    private fun showCity(city: CityResult) {
        store.update {
            it.copy(
                city = it.city.copy(
                    name = city.name,
                    latitude = city.latitude,
                    longitude = city.longitude,
                    suggestions = emptyList()
                )
            )
        }
        val view = HomeLocation(city.name, city.latitude, city.longitude)
        if (!moveTo(view.south, view.west, view.north, view.east)) return
        homeFeed.area = EventQuery(query.south, query.west, query.north, query.east)
        store.update { it.copy(city = it.city.copy(custom = false)) }
        // Нове місто — і для мапи, і для головної.
        queryChanged(); refresh()
    }
}

/**
 * Одне завдання на місце: нове скасовує попереднє, тож стара відповідь не перекриє свіжу. Скасоване чи завершене
 * завдання неактивне, тож [cancel] і [join] безпечні будь-коли.
 */
internal class LatestJob(private val scope: CoroutineScope) {
    private var job: Job? = null
    val active get() = job?.isActive == true
    fun cancel() { job?.cancel() }
    suspend fun join() { job?.join() }
    fun launch(block: suspend CoroutineScope.() -> Unit) { job?.cancel(); job = scope.launch(block = block) }
    /** Тримає вже запущене [next] замість попереднього. */
    fun set(next: Job) { job?.cancel(); job = next }
}

/** Видача після склейки й ранжування. [taste] — смак, яким рахували. */
internal class Ranked(
    val index: List<EventIndexEntry>,
    val suggested: List<EventIndexEntry>,
    val total: Int,
    val taste: Taste
)

/** Склеює й ранжує видачу за смаком [taste] поза головним потоком, у [compute]. */
internal suspend fun rank(page: DiscoveryPage, taste: Taste, compute: CoroutineContext): Ranked {
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
        Ranked(
            ordered,
            TasteRanking.matching(ordered, taste),
            folded.size + (page.total - page.index.size),
            taste
        )
    }
}

/** Смак міг змінитися, поки рахували: тоді перераховуємо. */
internal fun AppState.settled(taste: Taste) =
    if (this.taste == taste) materialized() else ranked()

/**
 * Артисти за текстом або порожньо: до [DiscoveryRules.MIN_ARTIST_QUERY] символів не питаємо (одна літера дала б
 * довільних п'ятьох). Збій теж порожньо, як у [placesOrEmpty].
 */
internal suspend fun EventDiscovery.artistsOrEmpty(text: String, city: String?): List<ArtistHit> {
    if (text.trim().length < DiscoveryRules.MIN_ARTIST_QUERY) return emptyList()
    return try {
        searchArtists(text, city).also { PoruchLog.d("discovery") { "${it.size} artists" } }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        PoruchLog.w("discovery") { "artists failed: ${e.asAppError()}" }
        emptyList()
    }
}

/** Заклади або порожньо. [bounds] null — усюди. */
internal suspend fun EventDiscovery.placesOrEmpty(text: String, bounds: EventQuery?): List<Place> = try {
    searchPlaces(text, bounds = bounds)
        .also { PoruchLog.d("discovery") { "${it.size} places" } }
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    PoruchLog.w("discovery") { "places failed: ${e.asAppError()}" }
    emptyList()
}

/** Межі [DateFilter] від сьогодні в поясі пристрою; для «Усі» — без меж. */
internal fun dateRange(filter: DateFilter): Pair<kotlin.time.Instant?, kotlin.time.Instant?> {
    val zone = TimeZone.currentSystemDefault()
    val now = Clock.System.now()
    val today = now.toLocalDateTime(zone).date
    // Вихідні — з суботи 00:00 до понеділка 00:00, найближчі.
    val daysToSaturday = (6 - today.dayOfWeek.isoDayNumber).coerceAtLeast(0)
    // «Усі» — без меж: сервер сам бере «від зараз» разом із тим, що вже триває. Застиглий
    // `now` ховав виставки й фестивалі і щоразу давав новий ключ кешу.
    val start = when (filter) {
        DateFilter.TODAY -> today.atStartOfDayIn(zone)
        DateFilter.TOMORROW -> today.plus(1, DateTimeUnit.DAY).atStartOfDayIn(zone)
        DateFilter.WEEKEND -> today.plus(daysToSaturday, DateTimeUnit.DAY).atStartOfDayIn(zone)
        DateFilter.ANY -> null
    }
    val end = when (filter) {
        DateFilter.TODAY -> today.plus(1, DateTimeUnit.DAY).atStartOfDayIn(zone)
        DateFilter.TOMORROW -> today.plus(2, DateTimeUnit.DAY).atStartOfDayIn(zone)
        DateFilter.WEEKEND -> today.plus(8 - today.dayOfWeek.isoDayNumber, DateTimeUnit.DAY)
            .atStartOfDayIn(zone)

        DateFilter.ANY -> null
    }
    return start to end
}
