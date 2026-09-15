package app.poruch.android.feature.explore

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import kotlinx.coroutines.launch
import kotlin.math.abs

/** Висота картки каруселі, як у [EventMapCard]. */
private val MapCardHeight = 112.dp
/** Місце під плаваючий таббар у кожному положенні шторки. */
private val TabBarInset = 84.dp
/** Скільки мапи лишаємо над повністю піднятою шторкою. Фільтри повертаються в половинному положенні. */
private val SheetTopInset = Spacing.sm
/** Частка інерції пальця, що схиляє вибір положення. */
private const val COAST_SHARE = 0.25f
/** Час інерції від швидкості відпускання, с. */
private const val COAST_SECONDS = 0.2f

/**
 * Шторка над мапою: згорнута — карусель, піднята — список тієї ж видачі. Карусель і мапа
 * ділять один вибір. Жест протягування живе лише на шапці, список гортається сам.
 */
@Composable
internal fun DiscoverySheet(
    state: ExploreState, screenHeight: Dp, modifier: Modifier, onIntent: (ExploreIntent) -> Unit
) {
    val colors = Poruch.colors
    val reducedMotion = Poruch.reducedMotion
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val navBottom = WindowInsets.navigationBars.getBottom(density)
    val statusTop = WindowInsets.statusBars.getTop(density)
    // Згорнута шторка: рядок лічильника, карусель і місце під таббар.
    val peekPx = with(density) { (44.dp + Spacing.sm + MapCardHeight + TabBarInset).toPx() } + navBottom
    val screenPx = with(density) { screenHeight.toPx() }
    val fullPx = maxOf(screenPx - statusTop - with(density) { SheetTopInset.toPx() }, peekPx)
    val halfPx = maxOf(screenPx * 0.55f, peekPx).coerceAtMost(fullPx)
    fun anchor(detent: SheetDetent) = when (detent) {
        SheetDetent.PEEK -> peekPx
        SheetDetent.HALF -> halfPx
        SheetDetent.FULL -> fullPx
    }

    // Висота йде за пальцем, а не за положенням, інакше під час жесту над вмістом порожнеча.
    val height = remember { Animatable(peekPx) }
    fun settleAt(detent: SheetDetent) {
        scope.launch {
            if (reducedMotion) height.snapTo(anchor(detent))
            else height.animateTo(anchor(detent), spring(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow))
        }
        onIntent(ExploreIntent.SetDetent(detent))
    }
    LaunchedEffect(state.detent, peekPx, fullPx) {
        if (!height.isRunning && height.value != anchor(state.detent)) settleAt(state.detent)
    }
    val drag = rememberDraggableState { delta ->
        scope.launch { height.snapTo((height.value - delta).coerceIn(peekPx, fullPx)) }
    }
    val handleModifier = Modifier.draggable(
        drag, Orientation.Vertical,
        onDragStopped = { velocity ->
            // До найближчого положення з урахуванням інерції.
            val target = height.value - velocity * COAST_SECONDS * COAST_SHARE
            settleAt(SheetDetent.entries.minBy { abs(anchor(it) - target) })
        }
    )
    // Від живої висоти, а не від положення: вміст стає списком, щойно палець відкрив місце.
    val expanded = height.value > peekPx + with(density) { Spacing.section.toPx() }
    BackHandler(state.detent != SheetDetent.PEEK) { settleAt(SheetDetent.PEEK) }

    val heightDp = with(density) { height.value.toDp() }
    // Згорнутій шторці підкладка не потрібна.
    val surface = if (expanded) {
        Modifier.shadow(Elevation.overlay, Radius.sheet, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot)
            .background(colors.canvas, Radius.sheet).clip(Radius.sheet)
    } else Modifier
    Column(
        modifier.fillMaxWidth().height(heightDp).then(surface)
            .navigationBarsPadding().padding(bottom = TabBarInset),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        SheetHeader(state, expanded, handleModifier, onIntent) { settleAt(it) }
        if (expanded) SheetList(state, onIntent) else PeekDeck(state, onIntent)
    }
}

/** Один контейнер на всі положення: жест висить на ньому, міняється лише вміст. */
@Composable
private fun SheetHeader(
    state: ExploreState, expanded: Boolean, handle: Modifier,
    onIntent: (ExploreIntent) -> Unit, open: (SheetDetent) -> Unit
) {
    val colors = Poruch.colors
    val label = countLabel(state)
    val showList = stringResource(R.string.show_list)
    Column(
        Modifier.fillMaxWidth().then(handle).padding(horizontal = Spacing.page).padding(top = if (expanded) Spacing.md else 0.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        // Ручка — складка на папері, а не пігулка Material.
        if (expanded) Box(Modifier.width(32.dp).height(4.dp).background(colors.inkTertiary, CircleShape))
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            if (expanded) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(label, style = MaterialTheme.typography.titleLarge, color = colors.ink)
                    Text(areaLabel(state), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 1)
                }
            } else {
                Spacer(Modifier.weight(1f))
                // Тягнеться і натискається: тап по лічильнику пояснює жест.
                Row(
                    Modifier.height(40.dp).cardSurface(Radius.pill)
                        .clickable(role = Role.Button, onClickLabel = showList) { open(SheetDetent.HALF) }
                        .padding(horizontal = Spacing.lg),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
                ) {
                    if (state.loading) CircularProgressIndicator(Modifier.size(14.dp), color = colors.brand, strokeWidth = 2.dp)
                    else if (state.offline) Icon(Icons.Outlined.CloudOff, null, Modifier.size(14.dp), tint = colors.accent)
                    Text(label, style = MaterialTheme.typography.labelMedium, color = colors.ink)
                    Icon(Icons.Outlined.ExpandLess, null, Modifier.size(16.dp), tint = colors.inkSecondary)
                }
            }
            // Вихід із фокуса на піні знімає і підсвітку, інакше мапа й список розходились.
            if (state.stackFocused) IconPill(Icons.Outlined.Close, stringResource(R.string.show_all_events)) {
                onIntent(ExploreIntent.ClearStack)
            }
            if (expanded) IconPill(Icons.Outlined.ExpandMore, stringResource(R.string.show_map)) { open(SheetDetent.PEEK) }
        }
    }
}

@Composable
private fun countLabel(state: ExploreState): String = when {
    state.loading -> stringResource(R.string.searching)
    state.stackFocused -> stringResource(R.string.events_here, state.listCount)
    else -> stringResource(R.string.events_found, state.listCount)
}

/** Що показує екран: пін, область рукою чи ціле місто. */
@Composable
private fun areaLabel(state: ExploreState): String = when {
    state.stackFocused -> stringResource(R.string.area_stack)
    state.customArea -> stringResource(R.string.area_custom)
    else -> stringResource(R.string.explore_subtitle, state.cityName)
}

/** Згорнута шторка: карусель або тиха картка, коли показувати нічого. */
@Composable
private fun PeekDeck(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    if (state.deckEvents.isEmpty()) {
        if (!state.loading) QuietCard(Modifier.padding(horizontal = Spacing.page), onIntent)
    } else EventCarousel(state, onIntent)
}

/** Карусель і мапа ділять один вибір в обидва боки; `userDriven` розриває петлю. */
@Composable
private fun EventCarousel(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
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
    // Біля краю завантаженого просимо наступне вікно карток.
    LaunchedEffect(centered, state.deckEvents.size, state.hasMoreCards) {
        val position = centered ?: return@LaunchedEffect
        if (!state.hasMoreCards) return@LaunchedEffect
        if (position >= state.deckEvents.size - PREFETCH_AHEAD) onIntent(ExploreIntent.LoadMore(state.deckEvents.size + PAGE))
    }
    LaunchedEffect(state.selectedId, state.deckEvents) {
        val id = state.selectedId ?: return@LaunchedEffect
        val index = state.deckEvents.indexOfFirst { it.id == id }
        if (index >= 0 && index != centered) {
            userDriven = false
            if (reducedMotion) listState.scrollToItem(index) else listState.animateScrollToItem(index)
        }
    }
    BoxWithConstraints {
        // Картка вужча за екран, щоб наступна визирала.
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

/** Піднята шторка: плитки категорій і видача списком. */
@Composable
private fun SheetList(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        categories.forEach { category ->
            CategoryTile(category, state.listCategory == category) { onIntent(ExploreIntent.PickListCategory(category)) }
        }
    }
    val rows = state.deckEvents
    if (rows.isEmpty()) {
        if (state.loading) Box(Modifier.fillMaxWidth().padding(vertical = Spacing.section), Alignment.Center) {
            CircularProgressIndicator(color = colors.brand)
        } else QuietCard(Modifier.padding(Spacing.page), onIntent)
        return
    }
    val listState = rememberLazyListState()
    val lastVisible by remember { derivedStateOf { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 } }
    // Список довантажує картки сам, а не лише карусель.
    LaunchedEffect(lastVisible, rows.size, state.hasMoreCards) {
        if (state.hasMoreCards && lastVisible >= rows.size - PREFETCH_AHEAD) onIntent(ExploreIntent.LoadMore(rows.size + PAGE))
    }
    LazyColumn(
        state = listState,
        contentPadding = PaddingValues(start = Spacing.page, end = Spacing.page, top = Spacing.xs, bottom = Spacing.section),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        items(rows, key = { it.id }) { event ->
            EventCard(
                event, saved = event.id in state.savedIds, waitlisted = event.id in state.waitlistedIds,
                onSave = { onIntent(ExploreIntent.ToggleSaved(event.id)) }
            ) { onIntent(ExploreIntent.OpenEvent(event.id)) }
        }
        if (state.hasMoreCards) item {
            Box(Modifier.fillMaxWidth().padding(vertical = Spacing.lg), Alignment.Center) {
                CircularProgressIndicator(Modifier.size(20.dp), color = colors.brand, strokeWidth = 2.dp)
            }
        }
    }
}

@Composable
private fun QuietCard(modifier: Modifier, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    Column(modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(stringResource(R.string.nothing_here), style = MaterialTheme.typography.titleSmall, color = colors.ink)
        Text(stringResource(R.string.nothing_here_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        GhostButton(stringResource(R.string.create), { onIntent(ExploreIntent.CreateEvent) }, Modifier.padding(top = Spacing.xs))
    }
}

/** За скільки карток до кінця просити наступні: приблизно екран списку. */
private const val PREFETCH_AHEAD = 8

/** Скільки карток додає одне довантаження. */
internal const val PAGE = 24
