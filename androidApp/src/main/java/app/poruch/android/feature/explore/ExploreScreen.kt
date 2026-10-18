package app.poruch.android.feature.explore

import androidx.compose.animation.*
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.LocalSharedMapView
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.shared.DateFilter

/** Висота градієнта під верхніми контролами і відступ мапи під ними. */
internal val TopControlsInset = 152.dp
/** Смуга шторки, з каруселлю чи порожньою карткою. */
internal val CarouselInset = 268.dp

@Composable
fun ExploreScreen(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    BoxWithConstraints(Modifier.fillMaxSize().background(colors.canvas)) {
        EventMap(
            events = state.screen.mapEvents, latitude = state.screen.cityLatitude, longitude = state.screen.cityLongitude,
            selectedId = state.screen.selectedId, topInset = TopControlsInset, bottomInset = CarouselInset,
            centerToken = state.recenterToken,
            onSelect = { onIntent(ExploreIntent.SelectEvent(it)) },
            onSelectStack = { onIntent(ExploreIntent.SelectStack(it)) },
            onAreaChanged = { onIntent(ExploreIntent.AreaMoved(it?.let { b -> Area(b.south, b.west, b.north, b.east) })) },
            onViewportChanged = { onIntent(ExploreIntent.Viewport(Area(it.south, it.west, it.north, it.east))) },
            onLoadFailed = { onIntent(ExploreIntent.MapFailed(it)) },
            shared = LocalSharedMapView.current
        )
        Box(
            Modifier.fillMaxWidth().height(TopControlsInset)
                .background(Brush.verticalGradient(listOf(colors.canvas.copy(alpha = 0.94f), colors.canvas.copy(alpha = 0f))))
        )
        TopControls(state, onIntent)
        DiscoverySheet(state, maxHeight, Modifier.align(Alignment.BottomCenter), onIntent)
    }

    when (state.sheet) {
        ExploreSheet.CITY -> CitySearchSheet(
            state.screen.cityName, state.screen.cities, { onIntent(ExploreIntent.SearchCity(it)) },
            { onIntent(ExploreIntent.SelectCity(it)) }, { onIntent(ExploreIntent.ShowSheet(ExploreSheet.NONE)) }
        )
        ExploreSheet.FILTERS -> PoruchSheet({ onIntent(ExploreIntent.ShowSheet(ExploreSheet.NONE)) }) { sheet ->
            FilterSheet(state, onIntent) { sheet.close() }
        }
        ExploreSheet.NONE -> Unit
    }
    // Підказка першого знайомства: де список і що таке пін із числом. Лише над згорнутою шторкою з картками,
    // коли поверх мапи нічого не відкрито.
    CoachMarks(
        listOf(CoachTip.SHEET),
        enabled = state.detent == SheetDetent.PEEK && state.sheet == ExploreSheet.NONE && state.screen.deckEvents.isNotEmpty()
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TopControls(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    // Дата, обрана у «Фільтрах», лягала за край ряду, і видно було лише цифру на кнопці.
    val pickedDate = remember { BringIntoViewRequester() }
    LaunchedEffect(state.screen.dateFilter) { if (state.screen.dateFilter != DateFilter.ANY) pickedDate.bringIntoView() }
    Column(Modifier.statusBarsPadding().padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        PoruchSearchField(
            state.screen.searchText, { onIntent(ExploreIntent.Search(it)) }, stringResource(R.string.search_placeholder),
            activeFilters = state.screen.activeFilters, onFilters = { onIntent(ExploreIntent.ShowSheet(ExploreSheet.FILTERS)) }
        )
        // Один ряд замість двох: місто веде стрічку фільтрів. Керування мапою — над каруселлю, під пальцем.
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
        ) {
            PoruchChip(state.screen.cityName, false, { onIntent(ExploreIntent.ShowSheet(ExploreSheet.CITY)) }, PoruchIcons.pin, trailingIcon = PoruchIcons.chevronDown)
            // Одразу після міста, а не за датами: з «Усі N» головної мапа приходить із цим фільтром, і його має бути видно.
            PoruchChip(
                stringResource(R.string.from_people), state.screen.onlyAvailable,
                { onIntent(ExploreIntent.OnlyAvailable(!state.screen.onlyAvailable)) }, PoruchIcons.social
            )
            // Категорію з «Фільтрів» чи плиток видно тут, а не лише цифрою на кнопці фільтрів. Тап знімає її. Поруч із датами:
            // коли ряд доїжджає до обраної дати, категорія лишається видно.
            state.screen.category?.let { category ->
                val label = stringResource(categoryLabel(category))
                val description = stringResource(R.string.a11y_clear_category, label)
                val clear = { onIntent(ExploreIntent.PickCategory(null)) }
                Box(Modifier.clearAndSetSemantics { contentDescription = description; role = Role.Button; onClick { clear(); true } }) {
                    PoruchChip(label, true, clear, dot = category, trailingIcon = PoruchIcons.close)
                }
            }
            // «Будь-коли» лише у «Фільтрах»: тут повторний тап і так знімає дату, а зайвий чип виштовхував обрану за край.
            dateFilters.filter { it.first != DateFilter.ANY }.forEach { (key, label) ->
                val selected = state.screen.dateFilter == key
                Box(if (selected) Modifier.bringIntoViewRequester(pickedDate) else Modifier) {
                    PoruchChip(stringResource(label), selected, {
                        onIntent(ExploreIntent.PickDate(if (selected) DateFilter.ANY else key))
                    })
                }
            }
        }
        if (state.locationDenied) Text(
            stringResource(R.string.location_fallback), style = MaterialTheme.typography.bodySmall, color = colors.ink,
            modifier = Modifier.cardSurface(Radius.sm).padding(Spacing.md)
        )
        AreaPrompts(state, Modifier.align(Alignment.CenterHorizontally), onIntent)
    }
}

/** «Шукати тут» і повтор після збою мапи. У тій самій колонці, що й контроли: окремий шар зі зсувом перекривав чипи дат. */
@Composable
private fun AreaPrompts(state: ExploreState, modifier: Modifier, onIntent: (ExploreIntent) -> Unit) {
    Column(
        modifier,
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        // Скидання з порожньої картки прибирає одразу кілька фільтрів: повернути їх — тим самим жестом, без пошуку.
        AnimatedVisibility(state.undoFilters != null, enter = fadeIn(), exit = fadeOut()) {
            Row(
                Modifier.heightIn(min = 44.dp).cardSurface(Radius.pill)
                    .clickable(role = Role.Button) { onIntent(ExploreIntent.UndoReset) }
                    .padding(horizontal = Spacing.lg),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
            ) {
                Text(stringResource(R.string.filters_reset), style = MaterialTheme.typography.labelMedium, color = Poruch.colors.inkSecondary)
                Text(stringResource(R.string.undo), style = MaterialTheme.typography.labelLarge, color = Poruch.colors.ink)
            }
        }
        AnimatedVisibility(
            state.pendingArea != null,
            enter = if (Poruch.reducedMotion) fadeIn() else fadeIn() + scaleIn(initialScale = 0.9f),
            exit = if (Poruch.reducedMotion) fadeOut() else fadeOut() + scaleOut(targetScale = 0.9f)
        ) {
            PrimaryButton(stringResource(R.string.search_here), { onIntent(ExploreIntent.SearchHere) }, icon = PoruchIcons.refresh)
        }
        if (state.mapFailed) SecondaryButton(
            stringResource(R.string.map_error_short), { onIntent(ExploreIntent.Recenter) }, icon = PoruchIcons.wifiOff
        )
    }
}

internal val dateFilters = listOf(
    DateFilter.ANY to R.string.any_date,
    DateFilter.TODAY to R.string.today,
    DateFilter.TOMORROW to R.string.tomorrow,
    DateFilter.WEEKEND to R.string.weekend
)
