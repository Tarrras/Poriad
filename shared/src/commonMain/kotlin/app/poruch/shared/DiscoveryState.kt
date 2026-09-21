package app.poruch.shared

import app.poruch.domain.*
import kotlin.time.Clock
import kotlin.time.Instant

/**
 * Стрічка головної. Мапа звужує свою видачу фільтрами й пошуком, а головна завжди показує
 * область цілою: інакше фільтр, поставлений на одному екрані, мовчки порожнив інший.
 * Спільні з мапою лише область (місто) і картки [AppState.cards].
 */
data class HomeFeed(
    /** Усе в області, ранжоване за смаком. */
    val index: List<EventIndexEntry> = emptyList(),
    /** Ті з [index], що відповідають смаку: «Для вас». */
    val suggestedIndex: List<EventIndexEntry> = emptyList(),
    val totalFound: Int = 0,
    val loading: Boolean = false,
    val searchText: String = "",
    /** Знайдене пошуком головної в тій самій області, ранжоване. */
    val results: List<EventIndexEntry> = emptyList(),
    val resultsTotal: Int = 0,
    val searchLoading: Boolean = false,
    /**
     * Завантажені картки [index] у його порядку, з пропусками тих, що ще їдуть. Складає
     * [materialized], щоб платформи не з'єднували індекс з картками самі, через міст.
     */
    val events: List<Event> = emptyList(),
    /** Картки [suggestedIndex] у його порядку. */
    val suggested: List<Event> = emptyList(),
    /** Картки [results] у його порядку. */
    val found: List<Event> = emptyList()
) {
    val searching get() = searchText.isNotBlank()

    /** Id, картки яких головна показує: зміна видачі мапи їх не викидає. */
    internal fun shownIds(): Set<String> =
        buildSet { index.forEach { add(it.id) }; results.forEach { add(it.id) } }
}

/** Ранжує індекс за смаком, а не картки: порядок вирішується над усією областю. */
internal fun AppState.ranked(now: Instant = Clock.System.now()): AppState {
    val ordered = TasteRanking.rank(index, taste, now)
    val suggested = TasteRanking.matching(ordered, taste)
    // Мапа без фільтрів ділить видачу з головною: той самий список ранжуємо раз.
    val sharedWithHome = home.index === index
    val homeOrdered = if (sharedWithHome) ordered else TasteRanking.rank(home.index, taste, now)
    return copy(
        index = ordered,
        suggestedIndex = suggested,
        indexVersion = if (ordered == index) indexVersion else indexVersion + 1,
        home = home.copy(
            index = homeOrdered,
            suggestedIndex = if (sharedWithHome) suggested else TasteRanking.matching(homeOrdered, taste),
            results = TasteRanking.rank(home.results, taste, now)
        )
    ).materialized()
}

/** Перераховує порядок лише тоді, коли змінився смак: ранжування тисяч подій не безкоштовне. */
internal fun AppState.rankedIfTasteChanged(before: Taste): AppState =
    if (taste == before) this else ranked()

/**
 * Перебудовує [events] і [suggested] під поточні [cards]. Стрічка обривається на першій
 * незавантаженій картці, а не пропускає її, інакше після довантаження картки стрибали б.
 */
internal fun AppState.materialized(): AppState {
    val cards = cardsWithSessions()
    val shown = ArrayList<Event>(minOf(index.size, cards.size))
    for (entry in index) shown += cards[entry.id] ?: break
    fun List<EventIndexEntry>.loaded() = mapNotNull { cards[it.id] }
    val homeEvents = if (home.index === index) index.loaded() else home.index.loaded()
    return copy(
        cards = cards,
        events = shown,
        suggested = suggestedIndex.mapNotNull { cards[it.id] },
        home = home.copy(events = homeEvents, suggested = home.suggestedIndex.loaded(), found = home.results.loaded()),
        feedVersion = feedVersion + 1
    )
}

/**
 * Кладе сеанси прокату з індексу в картки. Саме в [AppState.cards], бо головна, стос і шторка
 * читають картки за id. Картка без змін лишається тим самим об'єктом.
 */
private fun AppState.cardsWithSessions(): Map<String, Event> {
    val runs = HashMap<String, List<EventSession>>()
    for (entry in index) if (entry.isSeries) runs[entry.id] = entry.sessions
    for (entry in home.index) if (entry.isSeries) runs.getOrPut(entry.id) { entry.sessions }
    var changed: MutableMap<String, Event>? = null
    for ((id, card) in cards) {
        val sessions = runs[id] ?: emptyList()
        if (card.sessions == sessions) continue
        val target = changed ?: cards.toMutableMap().also { changed = it }
        target[id] = card.copy(sessions = sessions)
    }
    return changed ?: cards
}

/** Значення фільтра «без фільтра». Не категорія, тому окремо. */
const val ALL_CATEGORIES = "all"

/** Фільтри дати. Рядки, бо обидві платформи їх так зберігають. */
object DateFilter {
    const val ANY = "all"
    const val TODAY = "today"
    const val WEEKEND = "weekend"
}
