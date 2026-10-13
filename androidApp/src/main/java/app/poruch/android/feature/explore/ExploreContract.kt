package app.poruch.android.feature.explore

import app.poruch.domain.ArtistHit
import app.poruch.domain.EventCategory
import app.poruch.domain.CityResult
import app.poruch.domain.Place
import app.poruch.shared.DateFilter
import app.poruch.shared.ExploreScreenState

/**
 * Стан мапи: [screen] згортає спільний стор [app.poruch.shared.ExplorePresenter] — одна згортка на обидві
 * платформи; тут лише те, що належить екрану на цьому пристрої: положення шторки, листи, камера, дозволи.
 */
data class ExploreState(
    val screen: ExploreScreenState = ExploreScreenState.Empty,
    /** Положення шторки: згорнута — карусель, вище — список тієї ж видачі. */
    val detent: SheetDetent = SheetDetent.PEEK,
    val sheet: ExploreSheet = ExploreSheet.NONE,
    /** Камера посунулась: мапа тримає старі результати, поки не попросять «Шукати тут». */
    val pendingArea: Area? = null,
    val locationDenied: Boolean = false,
    val mapFailed: Boolean = false,
    /** Інкремент просить мапу повернутись до центру міста. */
    val recenterToken: Int = 0
)

data class Area(val south: Double, val west: Double, val north: Double, val east: Double)

enum class ExploreSheet { NONE, FILTERS, CITY }

/** Положення шторки: згорнута (карусель), половина, повний екран. */
enum class SheetDetent { PEEK, HALF, FULL }

sealed interface ExploreIntent {
    data class Search(val text: String) : ExploreIntent
    data class PickDate(val filter: DateFilter) : ExploreIntent
    data class PickCategory(val category: EventCategory?) : ExploreIntent
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
    /** Заклад з пошуку: мапа переходить до нього, а стос відкривається, щойно приїде видача. */
    data class FocusPlace(val place: Place) : ExploreIntent
    /** Артист з пошуку: екран артиста поверх мапи. */
    data class OpenArtist(val artist: ArtistHit) : ExploreIntent
    data object ClearStack : ExploreIntent
    /** «Стежити» / «Ви стежите» на закладі стосу. Гостя веде на вхід. */
    data object ToggleFollowStack : ExploreIntent
    data class OpenEvent(val id: String) : ExploreIntent
    /** Карусель або список дійшли до краю: наступне вікно [ExploreState.listEntries]. */
    data class LoadMore(val upTo: Int) : ExploreIntent
    data class ToggleSaved(val id: String) : ExploreIntent
    data object CreateEvent : ExploreIntent

    data class ShowSheet(val sheet: ExploreSheet) : ExploreIntent
    data class SetDetent(val detent: SheetDetent) : ExploreIntent
    /** Плитка категорії в шторці. Повторний тап знімає вибір. */
    data class PickListCategory(val category: EventCategory) : ExploreIntent

    data class SearchCity(val query: String) : ExploreIntent
    data class SelectCity(val city: CityResult) : ExploreIntent
    data object RequestLocation : ExploreIntent
    data class LocatedAt(val name: String, val latitude: Double, val longitude: Double) : ExploreIntent
    data object LocationDenied : ExploreIntent
}

sealed interface ExploreEffect {
    data class OpenDetail(val id: String) : ExploreEffect
    data class OpenArtist(val id: String) : ExploreEffect
    data object CreateEvent : ExploreEffect
    data object SignIn : ExploreEffect
    data object AskLocationPermission : ExploreEffect
}
