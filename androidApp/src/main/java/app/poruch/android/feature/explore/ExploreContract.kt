package app.poruch.android.feature.explore

import app.poruch.domain.CityResult
import app.poruch.domain.Event
import app.poruch.domain.EventIndexEntry
import app.poruch.domain.asIndexEntry
import app.poruch.shared.ALL_CATEGORIES
import app.poruch.shared.DateFilter

data class ExploreState(
    /** Усе, що є в області: мапа малює це, не чекаючи карток. */
    val index: List<EventIndexEntry> = emptyList(),
    /** Картки, які вже приїхали, у тому самому порядку. Їх може бути менше за [index]. */
    val events: List<Event> = emptyList(),
    /**
     * Усі завантажені картки за ідентифікатором.
     *
     * [events] — це суцільний початок стрічки, який обривається на першій незавантаженій події.
     * Стос майданчика лежить не на початку: його події розкидані по всьому індексу, тож зібрати
     * їх можна лише звідси. Без цього пін казав «32», а карусель під ним — «Тут подій: 3».
     */
    val cards: Map<String, Event> = emptyMap(),
    val totalFound: Int = 0,
    val selectedId: String? = null,
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    val cityName: String = "",
    val cityLatitude: Double = 0.0,
    val cityLongitude: Double = 0.0,
    val cities: List<CityResult> = emptyList(),
    val searchText: String = "",
    val category: String = ALL_CATEGORIES,
    val dateFilter: String = DateFilter.ANY,
    val onlyAvailable: Boolean = false,
    val loading: Boolean = false,
    val offline: Boolean = false,
    // ---- local to this screen
    val listMode: Boolean = false,
    val sheet: ExploreSheet = ExploreSheet.NONE,
    /** Set once the camera moved: the map holds results until the reader asks to search here. */
    val pendingArea: Area? = null,
    val locationDenied: Boolean = false,
    val mapFailed: Boolean = false,
    /** Bumped to ask the map to fly back to the city centre. */
    val recenterToken: Int = 0,
    /**
     * Події, що стоять на одній точці й тому на мапі невідрізненні.
     *
     * Кеш майданчиків дає всім подіям одного закладу ті самі координати: 177 київських подій
     * стоять на 34 точках, у найбільшій — 32. Без цього фокуса тап відкривав завжди ту саму з них,
     * а решта 31 була недосяжна.
     */
    val stackIds: List<String> = emptyList(),
    /**
     * Подія, на яку нас навели ззовні — з мапи в деталях. Вона могла не потрапити у поточну
     * видачу (інший фільтр, інша область), і тоді на мапі не було б ні піна, ні на що наводитись.
     */
    val focused: Event? = null
) {
    /**
     * Індекс, звужений до обраної категорії.
     *
     * Фільтр тут, а не в запиті до сервера. Доки категорія їхала в `EventQuery`, вона звужувала
     * сам індекс — і мапа, відфільтрована на «музику», звужувала й те, що бачить головна. Два
     * екрани ділили один фільтр, хоч кожен мав свій перемикач.
     */
    val visibleIndex get(): List<EventIndexEntry> =
        if (category == ALL_CATEGORIES) index else index.filter { it.category == category }

    /**
     * Що малює мапа: звужений індекс плюс подія, задля якої мапу відкрили. У звичайному випадку
     * вона вже там, і тоді це той самий список — той самий об'єкт, а не копія.
     */
    val mapEvents get(): List<EventIndexEntry> {
        val shown = visibleIndex
        return if (focused != null && shown.none { it.id == focused.id }) shown + focused.asIndexEntry() else shown
    }

    /** Скільки подій показує мапа. Під фільтром — стільки, скільки в ньому, а не скільки в місті. */
    val shownCount get() = if (category == ALL_CATEGORIES) totalFound else visibleIndex.size

    val activeFilters get() =
        listOf(dateFilter != DateFilter.ANY, category != ALL_CATEGORIES, onlyAvailable).count { it }

    /**
     * Що показує карусель: завантажені картки або лише той стос, у який щойно тицьнули.
     *
     * Подія, яку відкрили ззовні (з міні-мапи деталей), може не мати картки в цій видачі — тоді
     * вона стає першою, бо саме заради неї мапу й відкрили.
     */
    val deckEvents get(): List<Event> {
        // З мапи карток, а не з `events`: той обривається на першій незавантаженій події, а під
        // фільтром перші кілька подій категорії майже завжди лежать далі за край вікна.
        val shown = visibleIndex.mapNotNull { cards[it.id] }
        val all = if (focused != null && shown.none { it.id == focused.id }) listOf(focused) + shown else shown
        if (stackIds.isEmpty()) return all
        // Порядок стосу — з індексу, а не з набору ідентифікаторів: він має збігатися з тим, у
        // якому події стоять на мапі й у стрічці.
        val stack = index.filter { it.id in stackIds }.mapNotNull { cards[it.id] }
        // Після нової видачі від стосу могло лишитись нуль або одна подія — тоді фокус нічого не
        // додає, і карусель має повернутись до повного списку.
        return if (stack.size > 1) stack else all
    }
    val stackFocused get() = stackIds.isNotEmpty() && visibleIndex.count { it.id in stackIds } > 1

    /** Чи є що довантажувати: індекс повний, картки — ні. */
    val hasMoreCards get() = deckEvents.size < visibleIndex.size
}

data class Area(val south: Double, val west: Double, val north: Double, val east: Double)

enum class ExploreSheet { NONE, FILTERS, CITY }

sealed interface ExploreIntent {
    data class Search(val text: String) : ExploreIntent
    data class PickDate(val filter: String) : ExploreIntent
    data class PickCategory(val category: String) : ExploreIntent
    data class OnlyAvailable(val value: Boolean) : ExploreIntent
    data object ResetFilters : ExploreIntent

    data class AreaMoved(val area: Area?) : ExploreIntent
    data object SearchHere : ExploreIntent
    data object Recenter : ExploreIntent
    data class MapFailed(val failed: Boolean) : ExploreIntent

    data class SelectEvent(val id: String) : ExploreIntent
    /** Мапу відкрили заради однієї події — з міні-мапи на її деталях. */
    data class FocusEvent(val id: String) : ExploreIntent
    /** Тап у точку, де подій кілька: показуємо всі, а не найвищу в стосі. */
    data class SelectStack(val ids: List<String>) : ExploreIntent
    data object ClearStack : ExploreIntent
    data class OpenEvent(val id: String) : ExploreIntent
    /** Карусель або список дійшли до краю завантаженого. */
    data class LoadMore(val upTo: Int) : ExploreIntent
    data class ToggleSaved(val id: String) : ExploreIntent
    data object CreateEvent : ExploreIntent

    data class ShowSheet(val sheet: ExploreSheet) : ExploreIntent
    data class ListMode(val value: Boolean) : ExploreIntent

    data class SearchCity(val query: String) : ExploreIntent
    data class SelectCity(val city: CityResult) : ExploreIntent
    data object RequestLocation : ExploreIntent
    data class LocatedAt(val name: String, val latitude: Double, val longitude: Double) : ExploreIntent
    data object LocationDenied : ExploreIntent
}

sealed interface ExploreEffect {
    data class OpenDetail(val id: String) : ExploreEffect
    data object CreateEvent : ExploreEffect
    data object AskLocationPermission : ExploreEffect
}
