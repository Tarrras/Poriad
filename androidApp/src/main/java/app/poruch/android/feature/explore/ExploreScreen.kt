package app.poruch.android.feature.explore

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
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
            events = state.mapEvents, latitude = state.cityLatitude, longitude = state.cityLongitude,
            selectedId = state.selectedId, topInset = TopControlsInset, bottomInset = CarouselInset,
            centerToken = state.recenterToken,
            onSelect = { onIntent(ExploreIntent.SelectEvent(it)) },
            onSelectStack = { onIntent(ExploreIntent.SelectStack(it)) },
            onAreaChanged = { onIntent(ExploreIntent.AreaMoved(it?.let { b -> Area(b.south, b.west, b.north, b.east) })) },
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
        ExploreSheet.CITY -> CitySearchSheet(state, onIntent)
        ExploreSheet.FILTERS -> PoruchSheet({ onIntent(ExploreIntent.ShowSheet(ExploreSheet.NONE)) }) { sheet ->
            FilterSheet(state, onIntent) { sheet.close() }
        }
        ExploreSheet.NONE -> Unit
    }
}

@Composable
private fun TopControls(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.statusBarsPadding().padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        PoruchSearchField(
            state.searchText, { onIntent(ExploreIntent.Search(it)) }, stringResource(R.string.search_placeholder),
            activeFilters = state.activeFilters, onFilters = { onIntent(ExploreIntent.ShowSheet(ExploreSheet.FILTERS)) }
        )
        // Один ряд замість двох: місто веде стрічку фільтрів. Керування мапою — над каруселлю, під пальцем.
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
        ) {
            PoruchChip(state.cityName, false, { onIntent(ExploreIntent.ShowSheet(ExploreSheet.CITY)) }, PoruchIcons.pin, trailingIcon = Icons.Outlined.ExpandMore)
            dateFilters.forEach { (key, label) ->
                // Повторний тап знімає вибір, щоб не шукати «Будь-коли» за краєм рядка.
                PoruchChip(stringResource(label), state.dateFilter == key, {
                    onIntent(ExploreIntent.PickDate(if (state.dateFilter == key) DateFilter.ANY else key))
                })
            }
            PoruchChip(
                stringResource(R.string.available), state.onlyAvailable,
                { onIntent(ExploreIntent.OnlyAvailable(!state.onlyAvailable)) }, PoruchIcons.checkCircle
            )
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
        AnimatedVisibility(
            state.pendingArea != null,
            enter = if (Poruch.reducedMotion) fadeIn() else fadeIn() + scaleIn(initialScale = 0.9f),
            exit = if (Poruch.reducedMotion) fadeOut() else fadeOut() + scaleOut(targetScale = 0.9f)
        ) {
            PrimaryButton(stringResource(R.string.search_here), { onIntent(ExploreIntent.SearchHere) }, icon = Icons.Outlined.Refresh)
        }
        if (state.mapFailed) SecondaryButton(
            stringResource(R.string.map_error_short), { onIntent(ExploreIntent.Recenter) }, icon = Icons.Outlined.WifiOff
        )
    }
}

internal val dateFilters = listOf(
    DateFilter.ANY to R.string.any_date,
    DateFilter.TODAY to R.string.today,
    DateFilter.WEEKEND to R.string.weekend
)
