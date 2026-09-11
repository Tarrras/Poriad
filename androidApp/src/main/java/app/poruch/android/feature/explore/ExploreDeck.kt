package app.poruch.android.feature.explore

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ViewList
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.shared.ALL_CATEGORIES
import kotlin.math.abs

/**
 * The carousel and the map share one selection: settling on a card focuses its pin, and tapping a
 * pin scrolls the carousel back. A scroll flag breaks the feedback loop between the two directions.
 */
@Composable
internal fun MapBottomDeck(state: ExploreState, modifier: Modifier, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    val reducedMotion = Poruch.reducedMotion
    val listState = rememberLazyListState()
    var userDriven by remember { mutableStateOf(false) }
    val centered by remember {
        derivedStateOf {
            val info = listState.layoutInfo
            val middle = (info.viewportStartOffset + info.viewportEndOffset) / 2
            info.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - middle) }?.index
        }
    }
    LaunchedEffect(listState.isScrollInProgress) { if (listState.isScrollInProgress) userDriven = true }
    LaunchedEffect(centered, listState.isScrollInProgress) {
        if (listState.isScrollInProgress || !userDriven) return@LaunchedEffect
        userDriven = false
        val event = centered?.let(state.deckEvents::getOrNull) ?: return@LaunchedEffect
        if (event.id != state.selectedId) onIntent(ExploreIntent.SelectEvent(event.id))
    }
    // Індекс повний з першої відповіді, картки — ні. Коли карусель підходить до краю
    // завантаженого, просимо наступне вікно за вже відомими ідентифікаторами.
    LaunchedEffect(centered, state.events.size, state.hasMoreCards) {
        val position = centered ?: return@LaunchedEffect
        if (state.stackFocused || !state.hasMoreCards) return@LaunchedEffect
        if (position >= state.events.size - PREFETCH_AHEAD) {
            onIntent(ExploreIntent.LoadMore(state.events.size + PAGE))
        }
    }
    LaunchedEffect(state.selectedId, state.deckEvents) {
        val id = state.selectedId ?: return@LaunchedEffect
        val index = state.deckEvents.indexOfFirst { it.id == id }
        if (index >= 0 && index != centered) {
            userDriven = false
            if (reducedMotion) listState.scrollToItem(index) else listState.animateScrollToItem(index)
        }
    }
    Column(
        modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 84.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.page),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            Spacer(Modifier.weight(1f))
            Row(
                Modifier.cardSurface(Radius.pill).padding(horizontal = Spacing.lg, vertical = Spacing.sm),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                if (state.loading) CircularProgressIndicator(Modifier.size(14.dp), color = colors.brand, strokeWidth = 2.dp)
                else if (state.offline) Icon(Icons.Outlined.CloudOff, null, Modifier.size(14.dp), tint = colors.accent)
                Text(
                    when {
                        state.loading -> stringResource(R.string.searching)
                        state.stackFocused -> stringResource(R.string.events_here, state.deckEvents.size)
                        // Усе, що є в області, а не стільки, скільки встигло завантажитись: мапа
                        // вже показує саме це число пінами.
                        else -> stringResource(R.string.events_found, state.totalFound)
                    },
                    style = MaterialTheme.typography.labelMedium, color = colors.ink
                )
            }
            if (state.stackFocused) {
                IconPill(Icons.Outlined.Close, stringResource(R.string.show_all_events)) {
                    onIntent(ExploreIntent.ClearStack)
                }
            }
            IconPill(
                if (state.listMode) PoruchIcons.map else Icons.AutoMirrored.Outlined.ViewList,
                stringResource(if (state.listMode) R.string.show_map else R.string.show_list)
            ) { onIntent(ExploreIntent.ListMode(!state.listMode)) }
        }
        if (state.deckEvents.isEmpty()) {
            if (!state.loading) Column(
                Modifier.padding(horizontal = Spacing.page).fillMaxWidth().cardSurface().padding(Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                Text(stringResource(R.string.nothing_here), style = MaterialTheme.typography.titleSmall, color = colors.ink)
                Text(stringResource(R.string.nothing_here_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                GhostButton(stringResource(R.string.create), { onIntent(ExploreIntent.CreateEvent) }, Modifier.padding(top = Spacing.xs))
            }
        } else BoxWithConstraints {
            // The card stops short of the screen edges so the next one peeks in and reads as a deck.
            val cardWidth = maxWidth - 64.dp
            LazyRow(
                state = listState, flingBehavior = rememberSnapFlingBehavior(listState),
                contentPadding = PaddingValues(horizontal = Spacing.page), horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                items(state.deckEvents, key = { it.id }) { event ->
                    EventMapCard(
                        event, Modifier.width(cardWidth), focused = event.id == state.selectedId,
                        saved = event.id in state.savedIds, onSave = { onIntent(ExploreIntent.ToggleSaved(event.id)) }
                    ) { onIntent(ExploreIntent.OpenEvent(event.id)) }
                }
            }
        }
    }
}

/** The same results as the map, in a list — the accessible route through discovery. */
@Composable
internal fun ExploreList(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(Spacing.page), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.events_found, state.totalFound), style = MaterialTheme.typography.titleLarge, color = colors.ink)
                Text(
                    stringResource(R.string.explore_subtitle, state.cityName),
                    style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 1
                )
            }
            IconPill(PoruchIcons.map, stringResource(R.string.show_map)) { onIntent(ExploreIntent.ListMode(false)) }
        }
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.md),
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            categories.forEach { category ->
                CategoryTile(category, state.category == category) {
                    onIntent(ExploreIntent.PickCategory(if (state.category == category) ALL_CATEGORIES else category))
                }
            }
        }
        Spacer(Modifier.height(Spacing.md))
        if (state.events.isEmpty()) EmptyState(
            PoruchIcons.search, stringResource(R.string.nothing_here), stringResource(R.string.nothing_here_hint)
        ) else {
            val listState = rememberLazyListState()
            val lastVisible by remember {
                derivedStateOf { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }
            }
            LaunchedEffect(lastVisible, state.events.size, state.hasMoreCards) {
                if (state.hasMoreCards && lastVisible >= state.events.size - PREFETCH_AHEAD) {
                    onIntent(ExploreIntent.LoadMore(state.events.size + PAGE))
                }
            }
            LazyColumn(
                state = listState,
                contentPadding = PaddingValues(start = Spacing.page, end = Spacing.page, bottom = 120.dp),
                verticalArrangement = Arrangement.spacedBy(Spacing.lg)
            ) {
                items(state.events, key = { it.id }) { event ->
                    EventCard(
                        event, saved = event.id in state.savedIds, waitlisted = event.id in state.waitlistedIds,
                        onSave = { onIntent(ExploreIntent.ToggleSaved(event.id)) }
                    ) { onIntent(ExploreIntent.OpenEvent(event.id)) }
                }
            }
        }
    }
}

/**
 * За скільки карток до кінця завантаженого просити наступні. Вісім — приблизно екран списку й
 * кілька свайпів каруселі: людина не встигає дійти до порожнечі.
 */
private const val PREFETCH_AHEAD = 8

/** Скільки карток додає одне довантаження. */
private const val PAGE = 24
