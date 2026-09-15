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
    /** Картки, які вже приїхали, у тому ж порядку. Може бути менше за [index]. */
    val events: List<Event> = emptyList(),
    /** Усі завантажені картки за id. [events] — лише суцільний початок стрічки, а стос майданчика розкиданий по індексу. */
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
    /** Область поставили рукою через «Шукати тут». */
    val customArea: Boolean = false,
    // ---- Локальне для екрана
    /** Положення шторки: згорнута — карусель, вище — список тієї ж видачі. */
    val detent: SheetDetent = SheetDetent.PEEK,
    /** Категорія плиток у шторці. Звужує список і карусель, а не мапу: у мапи власна категорія у фільтрах. */
    val listCategory: String = ALL_CATEGORIES,
    val sheet: ExploreSheet = ExploreSheet.NONE,
    /** Камера посунулась: мапа тримає старі результати, поки не попросять «Шукати тут». */
    val pendingArea: Area? = null,
    val locationDenied: Boolean = false,
    val mapFailed: Boolean = false,
    /** Інкремент просить мапу повернутись до центру міста. */
    val recenterToken: Int = 0,
    /** Події на одній точці (всі події закладу): без стосу тап відкривав завжди ту саму. */
    val stackIds: List<String> = emptyList(),
    /** Подія, на яку навели з деталей. Може не бути в поточній видачі, тоді піна для неї нема. */
    val focused: Event? = null
) {
    /** Індекс, звужений до категорії. Фільтр тут, а не в запиті, щоб мапа й головна не ділили один фільтр. */
    val visibleIndex get(): List<EventIndexEntry> =
        if (category == ALL_CATEGORIES) index else index.filter { it.category == category }

    /**
     * Що малює мапа: звужений індекс плюс [focused], якщо її там ще нема. Сеанс прокату «вже
     * там» через представника, інакше пін майданчика рахував би прокат двічі.
     */
    val mapEvents get(): List<EventIndexEntry> {
        val shown = visibleIndex
        val present = focused == null || shown.any { entry ->
            entry.id == focused.id || entry.sessions.any { it.id == focused.id }
        }
        return if (present) shown else shown + focused!!.asIndexEntry()
    }

    /** Скільки подій показує мапа, з урахуванням фільтра. */
    val shownCount get() = if (category == ALL_CATEGORIES) totalFound else visibleIndex.size

    val activeFilters get() =
        listOf(dateFilter != DateFilter.ANY, category != ALL_CATEGORIES, onlyAvailable).count { it }

    val stackFocused get() = stackIds.isNotEmpty() && visibleIndex.count { it.id in stackIds } > 1

    /** Вміст шторки: стос обраного піна або вся видача, звужені категорією плиток. Порядок стосу — з індексу. */
    val listEntries get(): List<EventIndexEntry> {
        val base = if (stackFocused) index.filter { it.id in stackIds } else mapEvents
        return if (listCategory == ALL_CATEGORIES) base else base.filter { it.category == listCategory }
    }

    /**
     * Завантажені картки шторки для каруселі й списку. З [cards], а не з [events]: під фільтром
     * перші події категорії лежать за краєм вікна. [focused] без картки у видачі додається окремо.
     */
    val deckEvents get(): List<Event> =
        listEntries.mapNotNull { entry -> cards[entry.id] ?: focused?.takeIf { it.id == entry.id } }

    /** Чи є що довантажувати: індекс повний, картки — ні. */
    val hasMoreCards get() = deckEvents.size < listEntries.size

    /** Лічильник шторки: з індексу, а не з завантажених карток. */
    val listCount get(): Int =
        if (category == ALL_CATEGORIES && listCategory == ALL_CATEGORIES && !stackFocused) totalFound else listEntries.size
}

data class Area(val south: Double, val west: Double, val north: Double, val east: Double)

enum class ExploreSheet { NONE, FILTERS, CITY }

/** Положення шторки: згорнута (карусель), половина, повний екран. */
enum class SheetDetent { PEEK, HALF, FULL }

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
    /** Мапу відкрили заради однієї події з міні-мапи деталей. */
    data class FocusEvent(val id: String) : ExploreIntent
    /** Тап у точку з кількома подіями: показуємо всі. */
    data class SelectStack(val ids: List<String>) : ExploreIntent
    data object ClearStack : ExploreIntent
    data class OpenEvent(val id: String) : ExploreIntent
    /** Карусель або список дійшли до краю: наступне вікно [ExploreState.listEntries]. */
    data class LoadMore(val upTo: Int) : ExploreIntent
    data class ToggleSaved(val id: String) : ExploreIntent
    data object CreateEvent : ExploreIntent

    data class ShowSheet(val sheet: ExploreSheet) : ExploreIntent
    data class SetDetent(val detent: SheetDetent) : ExploreIntent
    /** Плитка категорії в шторці. Повторний тап знімає вибір. */
    data class PickListCategory(val category: String) : ExploreIntent

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
