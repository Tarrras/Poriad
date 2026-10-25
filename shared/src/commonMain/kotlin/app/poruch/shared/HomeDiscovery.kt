package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.*
import kotlin.coroutines.CoroutineContext

/**
 * Головна ([HomeFeed]): стрічка цілого міста без фільтрів мапи і свій пошук. Поки мапа без фільтрів, стрічку везе
 * запит мапи — це вирішує [DiscoveryEngine], а сюди потрапляє лише власний запит, коли мапа звужена.
 */
internal class HomeDiscovery(
    private val events: EventDiscovery,
    private val store: AppStore,
    scope: CoroutineScope,
    private val compute: CoroutineContext,
    home: HomeLocation,
    /** Довантаження карток, спільне з мапою: обидві просять той самий початок видачі одночасно. */
    private val load: (List<String>) -> Job?
) {
    /** Межі обраного міста — запит головної: ціле місто, без фільтрів мапи. «Шукати тут» рухає лише мапу. */
    var area = EventQuery(home.south, home.west, home.north, home.east)

    /** «Усюди» для пошуку головної: сервер приймає весь світ, ліміт видачі той самий. */
    private val WORLD = EventQuery(-90.0, -180.0, 90.0, 180.0)

    private val feedJob = LatestJob(scope)
    private val cardsJob = LatestJob(scope)
    private val searchJob = LatestJob(scope)
    private val debounceJob = LatestJob(scope)
    private val placesJob = LatestJob(scope)

    /** Стрічка головної окремим запитом, коли мапа звужена фільтрами. */
    fun refresh() {
        val snapshot = area
        feedJob.launch {
            store.update { it.copy(home = it.home.copy(loading = true)) }
            var offline = false
            val page = try {
                events.discover(snapshot)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Про збій сервера скаже мапа своїм банером; без мережі головна каже сама. Обидва раз беремо кеш.
                PoruchLog.w("discovery") { "home feed failed: ${e.asAppError()}" }
                offline = e.asAppError() is AppError.Network
                withContext(compute) { events.cached(snapshot) }
            }
            val ranked = rank(page, store.value.taste, compute)
            store.update {
                it.copy(
                    cards = it.cards + page.cards.associateBy { card -> card.id },
                    home = it.home.copy(
                        index = ranked.index, suggestedIndex = ranked.suggested,
                        totalFound = ranked.total, loading = false, offline = offline
                    )
                ).settled(ranked.taste)
            }
            materialize()
        }
    }

    /** Стрічку повезе запит мапи: власний уже зайвий. */
    fun cancelRefresh() = feedJob.cancel()

    /** Пошук головної в тій самій області, без фільтрів мапи. */
    fun setSearchText(text: String) {
        val trimmed = text.take(DiscoveryRules.SEARCH_TEXT_LIMIT)
        if (trimmed == store.value.home.searchText) return
        debounceJob.cancel(); searchJob.cancel()
        val blank = trimmed.isBlank()
        if (blank) placesJob.cancel()
        store.update {
            it.copy(
                home = if (blank) it.home.copy(
                    searchText = trimmed,
                    results = emptyList(),
                    found = emptyList(),
                    resultsTotal = 0,
                    places = emptyList(),
                    artists = emptyList(),
                    searchLoading = false
                )
                else it.home.copy(searchText = trimmed, searchLoading = true)
            )
        }
        if (!blank) debounceJob.launch { delay(DiscoveryRules.SEARCH_DEBOUNCE_MS); search() }
    }

    /** Вихід з режиму пошуку головної: текст і фільтри назад до типових, стрічка як була. */
    fun cancelSearch() {
        debounceJob.cancel(); searchJob.cancel(); placesJob.cancel()
        store.update {
            it.copy(
                home = it.home.copy(
                    searchText = "",
                    results = emptyList(),
                    found = emptyList(),
                    resultsTotal = 0,
                    places = emptyList(),
                    artists = emptyList(),
                    searchLoading = false,
                    searchEverywhere = false,
                    searchCategory = null,
                    searchDate = DateFilter.ANY
                )
            )
        }
    }

    /** Пошук головної по всіх містах чи лише в обраному. */
    fun setSearchEverywhere(everywhere: Boolean) =
        updateSearch { it.copy(searchEverywhere = everywhere) }

    fun setSearchCategory(category: EventCategory?) =
        updateSearch { it.copy(searchCategory = category) }

    fun setSearchDate(filter: DateFilter) =
        updateSearch { it.copy(searchDate = filter) }

    private fun updateSearch(change: (HomeFeed) -> HomeFeed) {
        val before = store.value.home
        val after = change(before)
        if (after == before) return
        store.update { it.copy(home = change(it.home)) }
        if (after.searching) search()
    }

    /** Перепитує пошук головної з поточним текстом і фільтрами. Без тексту — нічого. */
    fun search() {
        debounceJob.cancel(); searchJob.cancel()
        val home = store.value.home
        val text = home.searchText.trim()
        if (text.isEmpty()) return
        val (from, to) = dateRange(home.searchDate)
        // Заклади не залежать від категорії й дати: ті звужують лише події.
        val placesArea = if (home.searchEverywhere) null else area
        val artistsCity = if (home.searchEverywhere) null else store.value.city.takeIf { !it.custom }?.name
        placesJob.launch {
            launch {
                val found = events.placesOrEmpty(text, placesArea)
                store.update { it.copy(home = it.home.copy(places = found)) }
            }
            launch {
                val found = events.artistsOrEmpty(text, artistsCity)
                store.update { it.copy(home = it.home.copy(artists = found)) }
            }
        }
        val snapshot = (if (home.searchEverywhere) WORLD else area).copy(
            text = text,
            category = home.searchCategory,
            from = from?.toString(), to = to?.toString()
        )
        searchJob.launch {
            store.update { it.copy(home = it.home.copy(searchLoading = true)) }
            try {
                val page = events.discover(snapshot)
                val ranked = rank(page, store.value.taste, compute)
                store.update {
                    it.copy(
                        cards = it.cards + page.cards.associateBy { card -> card.id },
                        home = it.home.copy(
                            results = ranked.index,
                            resultsTotal = ranked.total,
                            searchLoading = false
                        )
                    ).settled(ranked.taste)
                }
                materialize()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                store.update { it.copy(home = it.home.copy(searchLoading = false)) }
                store.failed(e.asAppError())
            }
        }
    }

    /**
     * Картки, які головна показує першими: добірка, початок стрічки й пошуку, а ще кілька відкритих кімнат із будь-якого
     * місця індексу ([DiscoveryRules.HOME_ROOM_CARDS]): вони йдуть у «Від людей» і перші великі картки, хоч би коли починались.
     */
    fun materialize() {
        val home = store.value.home
        val rooms = home.index.filter { it.isCommunity && it.roomHasSeats }
            .take(DiscoveryRules.HOME_ROOM_CARDS)
        val ids =
            (home.suggestedIndex.take(DiscoveryRules.FIRST_CARDS) + home.index.take(DiscoveryRules.FIRST_CARDS) + rooms +
                    home.results.take(DiscoveryRules.FIRST_CARDS)).map { it.id }.distinct()
        load(ids)?.let(cardsJob::set)
    }

    /** Зміна акаунта: картки в дорозі несуть членство попереднього. */
    fun reset() = cardsJob.cancel()

    /** Чекає стрічку й пошук головної. */
    suspend fun await() {
        feedJob.join(); searchJob.join()
    }
}
