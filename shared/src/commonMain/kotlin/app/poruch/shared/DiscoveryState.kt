package app.poruch.shared

import app.poruch.domain.*
import kotlin.time.Clock
import kotlin.time.Instant

/** Видача мапи з її фільтрами й пошуком, у порядку показу. */
data class MapFeed(
    /** Повний список, не вікно: мапа малює його, ранжування йде по ньому. */
    val index: List<EventIndexEntry> = emptyList(),
    /** Ті з [index], що відповідають смаку. Картки можуть ще не приїхати. */
    val suggestedIndex: List<EventIndexEntry> = emptyList(),
    /** Скільки подій в області насправді. Дорівнює `index.size`, поки не спрацював запобіжник. */
    val totalFound: Int = 0,
    /** Те з [index], для чого вже є картка, у тому ж порядку. Це показують стрічка, карусель і головна. */
    val events: List<Event> = emptyList(),
    /**
     * Картки [suggestedIndex]: лише вони йдуть у «Для вас». Зберігається, а не рахується при
     * читанні: як `get()` це коштувало 34 мс на складання головної на iOS.
     */
    val suggested: List<Event> = emptyList(),
    /**
     * Лічильник змін складу чи порядку [index]. Платформи порівнюють число, а не обходять
     * тисячі записів через міст на кожну емісію: так iOS знає, коли перебудувати піни.
     */
    val indexVersion: Int = 0,
    /** Пошук мапи. У головної свій: [HomeFeed.searchText]. */
    val searchText: String = "",
    /** Заклади за [searchText] у тій самій області. Порожньо без пошуку. */
    val places: List<Place> = emptyList(),
    /** Заклад, обраний у пошуку: мапа наводиться на нього й відкриває його стос. */
    val placeFocus: PlaceFocus? = null,
    val onlyAvailable: Boolean = false,
    val category: String = ALL_CATEGORIES,
    val dateFilter: String = DateFilter.ANY,
    val loading: Boolean = false,
    /** Показано кеш: мережа не відповіла. */
    val offline: Boolean = false
)

/**
 * Заклад, на який тицьнули в пошуку. [eventIds] — події на його піні з видачі, що приїхала
 * після тапу; null — видача ще їде. [version] росте з кожним тапом, тож повторний тап по тому
 * самому закладу платформа теж побачить.
 */
data class PlaceFocus(val place: Place, val version: Int, val eventIds: List<String>? = null) {
    /** Події закладу з [index] за часом: той самий стос, що дає тап по піну. */
    internal fun resolved(index: List<EventIndexEntry>) =
        copy(eventIds = index.filter { place.isAt(it.latitude, it.longitude) }.sortedBy { it.startsAt }.map { it.id })
}

/** Область, у якій шукають мапа й головна. */
data class CityState(
    val name: String = HomeLocation.Kyiv.city,
    val latitude: Double = HomeLocation.Kyiv.latitude,
    val longitude: Double = HomeLocation.Kyiv.longitude,
    /** Область поставлена рукою («Шукати тут»), а не обрана зі списку міст. Головна каже це вголос. */
    val custom: Boolean = false,
    /** Підказки пошуку міста. */
    val suggestions: List<CityResult> = emptyList()
)

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
    /** Заклади за [searchText] у тій самій області, що й [results]. */
    val places: List<Place> = emptyList(),
    val searchLoading: Boolean = false,
    /** Пошук головної по всіх містах, а не лише в обраному. */
    val searchEverywhere: Boolean = false,
    /** Фільтри пошуку головної. Стрічку не звужують — лише знайдене. */
    val searchCategory: String = ALL_CATEGORIES,
    val searchDate: String = DateFilter.ANY,
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
    val ordered = TasteRanking.rank(map.index, taste, now)
    val suggested = TasteRanking.matching(ordered, taste)
    // Мапа без фільтрів ділить видачу з головною: той самий список ранжуємо раз.
    val sharedWithHome = home.index === map.index
    val homeOrdered = if (sharedWithHome) ordered else TasteRanking.rank(home.index, taste, now)
    return copy(
        map = map.copy(
            index = ordered,
            suggestedIndex = suggested,
            indexVersion = if (ordered == map.index) map.indexVersion else map.indexVersion + 1
        ),
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
 * Перебудовує [MapFeed.events] і [MapFeed.suggested] під поточні [AppState.cards]. Стрічка обривається на першій
 * незавантаженій картці, а не пропускає її, інакше після довантаження картки стрибали б.
 */
internal fun AppState.materialized(): AppState {
    val cards = cardsWithSessions()
    val shown = ArrayList<Event>(minOf(map.index.size, cards.size))
    for (entry in map.index) shown += cards[entry.id] ?: break
    fun List<EventIndexEntry>.loaded() = mapNotNull { cards[it.id] }
    val homeEvents = if (home.index === map.index) map.index.loaded() else home.index.loaded()
    return copy(
        cards = cards,
        map = map.copy(events = shown, suggested = map.suggestedIndex.loaded()),
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
    for (entry in map.index) if (entry.isSeries) runs[entry.id] = entry.sessions
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
