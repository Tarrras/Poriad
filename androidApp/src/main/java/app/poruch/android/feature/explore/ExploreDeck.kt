package app.poruch.android.feature.explore

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/** Висота картки каруселі, як у [EventMapCard]. */

/** Місце під плаваючий таббар у кожному положенні шторки. На широкому вікні таббару нема: вкладки — рейкою зліва. */
private val TabBarInset = 84.dp

/** Скільки списку має бути видно в половинному положенні понад поріг: шапка з плитками й рядок. */
private val HalfListMin = 160.dp

/** Картка каруселі на широкому вікні не тягнеться на всю шторку. */
private val MapCardMaxWidth = 400.dp

/** Скільки мапи лишаємо над повністю піднятою шторкою. Фільтри повертаються в половинному положенні. */
private val SheetTopInset = Spacing.sm

/** Частка інерції пальця, що схиляє вибір положення. */
private const val COAST_SHARE = 0.25f

/** Час інерції від швидкості відпускання, с. */
private const val COAST_SECONDS = 0.2f

/**
 * Шторка над мапою: згорнута — карусель, піднята — список тієї ж видачі. Карусель і мапа
 * ділять один вибір. Шторку тягне і шапка, і прокрутка списку: пальцем угору список спершу
 * піднімає шторку до повної, пальцем униз від верху списку — опускає її.
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
    val cardHeight = mapCardHeight()
    val statusTop = WindowInsets.statusBars.getTop(density)
    val tabBarInset = if (LocalWideLayout.current) 0.dp else TabBarInset
    // Згорнута шторка: рядок лічильника, карусель і місце під таббар.
    val peekPx =
        with(density) { (48.dp + Spacing.sm + cardHeight + tabBarInset).toPx() } + navBottom
    val screenPx = with(density) { screenHeight.toPx() }
    val fullPx = maxOf(screenPx - statusTop - with(density) { SheetTopInset.toPx() }, peekPx)
    // Не нижче за поріг списку з кількома рядками: на малому екрані з великим шрифтом і в ландшафті 55 % екрана були
    // нижчими за поріг, і тап по лічильнику нічого не відкривав. Не вміщається — половина й є повна.
    val halfPx = maxOf(screenPx * 0.55f, peekPx + with(density) { (Spacing.section + HalfListMin).toPx() }).coerceAtMost(fullPx)
    fun anchor(detent: SheetDetent) = when (detent) {
        SheetDetent.PEEK -> peekPx
        SheetDetent.HALF -> halfPx
        SheetDetent.FULL -> fullPx
    }

    // Висота йде за пальцем, а не за положенням, інакше під час жесту над вмістом порожнеча.
    // Звичайний стан, а не Animatable: вкладена прокрутка питає, скільки спожито, тут і зараз,
    // а snapTo у корутині відповідав би на наступному кадрі й губив кроки.
    // Починаємо з положення стану, а не згорнутою: повернення на мапу не анімує шторку знову,
    // а застаріле положення першого кадру не перебиває нове (FocusEvent закриває шторку).
    var height by remember { mutableFloatStateOf(anchor(state.detent)) }
    var settling by remember { mutableStateOf<Job?>(null) }
    fun settleAt(detent: SheetDetent) {
        settling?.cancel()
        val target = anchor(detent)
        settling = scope.launch {
            if (reducedMotion) height = target
            else animate(height, target, animationSpec = Motion.spring()) { value, _ ->
                height = value
            }
        }
        onIntent(ExploreIntent.SetDetent(detent))
    }

    /** Зсув пальця (вниз додатний) у висоту; повертає спожиту частину в тому ж знаку. */
    fun dragBy(delta: Float): Float {
        settling?.cancel()
        val before = height
        height = (before - delta).coerceIn(peekPx, fullPx)
        return before - height
    }

    /** До найближчого положення з урахуванням інерції. */
    fun settleFrom(velocity: Float) {
        val target = height - velocity * COAST_SECONDS * COAST_SHARE
        settleAt(SheetDetent.entries.minBy { abs(anchor(it) - target) })
    }
    LaunchedEffect(state.detent, peekPx, fullPx) {
        if (settling?.isActive != true && height != anchor(state.detent)) settleAt(state.detent)
    }
    val drag = rememberDraggableState { delta -> dragBy(delta) }
    val handleModifier =
        Modifier.draggable(drag, Orientation.Vertical, onDragStopped = { settleFrom(it) })
    val expandedThreshold = peekPx + with(density) { Spacing.section.toPx() }
    // Від живої висоти, а не від положення: вміст стає списком, щойно палець відкрив місце.
    // Похідний стан: шторка перескладається на перетині порога, а не на кожен кадр жесту.
    val expanded by remember(expandedThreshold) { derivedStateOf { height > expandedThreshold } }
    BackHandler(state.detent != SheetDetent.PEEK) { settleAt(SheetDetent.PEEK) }

    // Прокрутка списку тягне шторку: угору — доки не повна, униз — коли список уже на початку.
    val listConnection = remember(peekPx, fullPx) {
        object : NestedScrollConnection {
            /** Чи зрушив список шторку в цьому жесті: тоді відпускання сідає на положення. */
            var moved = false
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source != NestedScrollSource.UserInput || available.y >= 0) return Offset.Zero
                val consumed = dragBy(available.y)
                if (consumed != 0f) moved = true
                return Offset(0f, consumed)
            }

            override fun onPostScroll(
                consumed: Offset,
                available: Offset,
                source: NestedScrollSource
            ): Offset {
                if (source != NestedScrollSource.UserInput || available.y <= 0) return Offset.Zero
                val taken = dragBy(available.y)
                if (taken != 0f) moved = true
                // Нижче порога список зникає разом із жестом, тож сідаємо на згорнуту звідси.
                if (height <= expandedThreshold) {
                    moved = false; settleAt(SheetDetent.PEEK)
                }
                return Offset(0f, taken)
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (!moved) return Velocity.Zero
                moved = false
                val atAnchor = SheetDetent.entries.any { abs(anchor(it) - height) < 0.5f }
                settleFrom(available.y)
                // Шторка між положеннями — інерція її, а не списку.
                return if (atAnchor) Velocity.Zero else available
            }
        }
    }

    // Клавіатура пошуку лягає на шторку (вікно не стискається): згорнуту піднімаємо над нею.
    // Таббар під клавіатурою ховається, тож його смугу віднімаємо.
    // Запас Spacing.md: двоповерхова картка вища за слот, і її низ інакше ховається під клавіатурою.
    val imeLift = WindowInsets.ime.getBottom(density) - navBottom - with(density) { tabBarInset.roundToPx() }
    val lift = if (expanded || imeLift <= 0) 0 else imeLift + with(density) { Spacing.md.roundToPx() }
    // Згорнутій шторці підкладка не потрібна.
    val surface = if (expanded) {
        Modifier
            .shadow(
                Elevation.overlay,
                Radius.sheet,
                clip = false,
                ambientColor = colors.shadowAmbient,
                spotColor = colors.shadowSpot
            )
            .background(colors.canvas, Radius.sheet)
            .clip(Radius.sheet)
    } else Modifier
    Column(
        modifier
            .fillMaxWidth()
            .offset { IntOffset(0, -lift) }
            // Висота читається у фазі розмітки: жест рухає шторку без перескладання її вмісту.
            .layout { measurable, constraints ->
                val px = height.roundToInt().coerceIn(constraints.minHeight, constraints.maxHeight)
                val placeable = measurable.measure(constraints.copy(minHeight = px, maxHeight = px))
                layout(placeable.width, px) { placeable.place(0, 0) }
            }
            .then(surface)
            .nestedScroll(listConnection)
            .navigationBarsPadding()
            .padding(bottom = tabBarInset),
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
    // «Стежити» лише на стосі закладу: це одне з двох місць, де людина бачить заклад як окрему річ.
    val stackPlace = state.screen.stackPlace.takeIf { state.screen.stackFocused }
    Column(
        Modifier
            .fillMaxWidth()
            .then(handle)
            .padding(horizontal = Spacing.page)
            .padding(top = if (expanded) Spacing.md else 0.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        // Ручка — складка на папері, а не пігулка Material.
        if (expanded) Box(
            Modifier
                .width(36.dp)
                .height(4.dp)
                .background(colors.inkTertiary, CircleShape)
        )
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            if (expanded) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    // Стос закладу — це заклад: назва заголовком, а не «усе, що стоїть на обраному піні». Кондензом, як
                    // заголовки решти шторок.
                    // Заголовок і для TalkBack; висоту шторки міняють і дії на ньому, як на iOS.
                    val sheetAction = if (state.detent == SheetDetent.FULL) stringResource(R.string.a11y_sheet_half)
                    else stringResource(R.string.a11y_sheet_full)
                    Text(
                        stackPlace?.name ?: label,
                        Modifier.semantics {
                            heading()
                            customActions = listOf(CustomAccessibilityAction(sheetAction) {
                                open(if (state.detent == SheetDetent.FULL) SheetDetent.HALF else SheetDetent.FULL); true
                            })
                        },
                        style = PoruchType.brandTitle2, color = colors.ink,
                        maxLines = 2, overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        if (stackPlace != null) label else areaLabel(state),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    // Під підписом, а не в ряду, як на iOS: лічильник і дві кнопки праворуч на 360 dp лишали назві ~80 dp.
                    if (stackPlace != null) FollowPill(
                        state.screen.stackFollowing, { onIntent(ExploreIntent.ToggleFollowStack) },
                        Modifier.padding(top = Spacing.sm).followSemantics(stackPlace.name, state.screen.stackFollowing) {
                            onIntent(ExploreIntent.ToggleFollowStack)
                        }
                    )
                    // Те саме гніздо в місті: порядок — властивість списку, який піднімають, щоб зіставити. У стосі чипа нема:
                    // одне місце — одна відстань.
                    if (!state.screen.stackFocused) Box(Modifier.padding(top = Spacing.sm)) {
                        PoruchChip(
                            stringResource(R.string.nearer_me), state.screen.nearMe || state.locatingNear,
                            { onIntent(ExploreIntent.ToggleNear) }, PoruchIcons.myLocation
                        )
                    }
                }
            } else {
                // Керування мапою в зоні великого пальця, над каруселлю.
                IconPill(PoruchIcons.recenter, stringResource(R.string.recenter), size = 40.dp) { onIntent(ExploreIntent.Recenter) }
                IconPill(PoruchIcons.myLocation, stringResource(R.string.nearby), size = 40.dp) { onIntent(ExploreIntent.RequestLocation) }
                // Лічильник бере лише вільне місце: без цього на 360 dp він витискав «×» до кількох dp.
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
                // Тягнеться і натискається: тап по лічильнику пояснює жест.
                Row(
                    Modifier
                        .coachTarget(CoachTip.SHEET)
                        .minimumInteractiveComponentSize()
                        .heightIn(min = 40.dp)
                        .cardSurface(Radius.pill, Elevation.raised)
                        .clickable(
                            role = Role.Button,
                            onClickLabel = showList
                        ) { open(SheetDetent.HALF) }
                        .padding(horizontal = Spacing.lg),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
                ) {
                    if (state.screen.loading) CircularProgressIndicator(
                        Modifier.size(14.dp),
                        color = colors.brand,
                        strokeWidth = 2.dp
                    )
                    else if (state.screen.offline) Icon(
                        PoruchIcons.wifiOff,
                        null,
                        Modifier.size(14.dp),
                        tint = colors.accent
                    )
                    // Не влазить «Тут подій: 12» (вузький екран, стос із дзвінком, великий шрифт) — лишається число, повний
                    // текст чує TalkBack. За шириною, як `ViewThatFits` на iOS, а не за `fontScale`.
                    val short = if (state.screen.offline) stringResource(R.string.offline_count, "${state.screen.listCount}")
                    else "${state.screen.listCount}"
                    var tight by remember(label) { mutableStateOf(false) }
                    Text(
                        if (tight && !state.screen.loading) short else label,
                        Modifier.weight(1f, fill = false).semantics { contentDescription = label },
                        style = MaterialTheme.typography.labelMedium, color = colors.ink, maxLines = 1, softWrap = false,
                        onTextLayout = { if (it.hasVisualOverflow && !tight) tight = true }
                    )
                    Icon(
                        PoruchIcons.chevronUp,
                        null,
                        Modifier.size(16.dp),
                        tint = colors.inkSecondary
                    )
                }
                }
                // Згорнута шапка тісна: тут лише дзвінок, підпис читає доступність.
                // Назва стала («Стежити: Atlas»), стан — «вибрано»: так само, як на iOS і в піднятій шапці.
                if (stackPlace != null) IconPill(
                    if (state.screen.stackFollowing) PoruchIcons.bellActive else PoruchIcons.bell,
                    stringResource(R.string.a11y_follow_name, stackPlace.name),
                    selected = state.screen.stackFollowing, size = 40.dp
                ) { onIntent(ExploreIntent.ToggleFollowStack) }
            }
            // Вихід із фокуса на піні знімає і підсвітку, інакше мапа й список розходились. У згорнутій шапці — 40, як сусіди.
            if (state.screen.stackFocused) IconPill(
                PoruchIcons.close,
                stringResource(R.string.show_all_events),
                size = if (expanded) 48.dp else 40.dp
            ) {
                onIntent(ExploreIntent.ClearStack)
            }
            if (expanded) IconPill(
                PoruchIcons.chevronDown,
                stringResource(R.string.show_map)
            ) { open(SheetDetent.PEEK) }
        }
    }
}

/** «Стежити: Atlas» з будь-яким станом, а «вибрано» — станом: назва для TalkBack і голосу не міняється від тапу. */
@Composable
private fun Modifier.followSemantics(place: String, following: Boolean, toggle: () -> Unit): Modifier {
    val name = stringResource(R.string.a11y_follow_name, place)
    return clearAndSetSemantics {
        contentDescription = name
        selected = following
        role = Role.Button
        onClick { toggle(); true }
    }
}

@Composable
private fun countLabel(state: ExploreState): String {
    if (state.screen.loading) return stringResource(R.string.searching)
    val count = if (state.screen.stackFocused) stringResource(R.string.events_here, state.screen.listCount)
    else stringResource(R.string.events_found, state.screen.listCount)
    // Офлайн словами, а не лише гліфом: видача — збережена, і це треба знати.
    return if (state.screen.offline) stringResource(R.string.offline_count, count) else count
}

/** Що показує екран: пін, область рукою чи ціле місто. */
@Composable
private fun areaLabel(state: ExploreState): String = when {
    state.screen.stackFocused -> stringResource(R.string.area_stack)
    state.screen.customArea -> stringResource(R.string.area_custom)
    // Без «сьогодні»: під фільтром «Вихідні» підпис казав неправду. Той самий рядок, що на iOS.
    else -> stringResource(R.string.area_city, state.screen.cityName)
}

/** Відстань у рядку з «Ближче до мене»: цілими км, а в межах похибки положення — «до 3 км». */
@Composable
private fun distanceLabel(km: Int, within: Int): String =
    if (km <= within) stringResource(R.string.distance_within, within) else stringResource(R.string.distance_km, km)

/** Згорнута шторка: карусель або тиха картка, коли показувати нічого. */
@Composable
private fun PeekDeck(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    if (state.screen.deckEvents.isEmpty()) {
        if (!state.screen.loading) QuietCard(Modifier.padding(horizontal = Spacing.page), state, onIntent)
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
    // Лише палець: власна прокрутка до вибору теж «scroll in progress», і обірвана посередині
    // вона обирала проміжну картку замість потрібної.
    val dragged by listState.interactionSource.collectIsDraggedAsState()
    LaunchedEffect(dragged) {
        if (dragged) userDriven = true
    }
    // Перше вирівнювання — стрибком: карусель щойно з'явилась (напр., «На мапі» з деталей).
    var aligned by remember { mutableStateOf(false) }
    LaunchedEffect(centered, listState.isScrollInProgress) {
        if (listState.isScrollInProgress || !userDriven) return@LaunchedEffect
        userDriven = false
        val event = centered?.let(state.screen.deckEvents::getOrNull) ?: return@LaunchedEffect
        if (event.id != state.screen.selectedId) onIntent(ExploreIntent.SelectEvent(event.id))
    }
    // Біля краю завантаженого просимо наступне вікно карток.
    LaunchedEffect(centered, state.screen.deckEvents.size, state.screen.hasMoreCards) {
        val position = centered ?: return@LaunchedEffect
        if (!state.screen.hasMoreCards) return@LaunchedEffect
        if (position >= state.screen.deckEvents.size - PREFETCH_AHEAD) onIntent(
            ExploreIntent.LoadMore(
                state.screen.deckEvents.size + PAGE
            )
        )
    }
    // «Повернутися до міста», перехід з головної, новий запит (фільтр, пошук, місто) і «Ближче до мене»: карусель з першої картки й лишається
    // на ній, доки людина не гортала чи не обрала подію. Картки нової видачі приїжджають пізніше й вставляються перед
    // колишньою першою, а список тримається за ключ першої видимої картки: без цього він лишався б на ній.
    var atStart by remember { mutableStateOf(false) }
    LaunchedEffect(state.recenterToken, state.screen.queries, state.screen.nearMe) { atStart = true }
    LaunchedEffect(dragged, state.screen.selectedId) { if (dragged || state.screen.selectedId != null) atStart = false }
    LaunchedEffect(atStart, state.screen.deckEvents) { if (atStart) listState.scrollToItem(0) }
    LaunchedEffect(state.screen.selectedId, state.screen.deckEvents) {
        val id = state.screen.selectedId ?: return@LaunchedEffect
        val index = state.screen.deckEvents.indexOfFirst { it.id == id }
        val from = centered
        if (index >= 0 && index != from) {
            userDriven = false
            // Анімація лише на кілька карток. Далеко — стрибок: прогін через десятки карток ішов
            // довго, а довантаження дорогою ще й відсувало ціль.
            if (reducedMotion || !aligned || from == null || abs(index - from) > NEAR_CARDS) listState.scrollToItem(index)
            else listState.animateScrollToItem(index)
        }
        if (index >= 0) aligned = true
    }
    BoxWithConstraints {
        // Картка вужча за екран, щоб наступна визирала; на широкому вікні — не ширша за телефонну.
        val cardWidth = minOf(maxWidth - 64.dp, MapCardMaxWidth)
        LazyRow(
            state = listState,
            flingBehavior = rememberSnapFlingBehavior(listState),
            contentPadding = PaddingValues(horizontal = Spacing.page),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            items(state.screen.deckEvents, key = { it.id }) { event ->
                EventMapCard(
                    event,
                    Modifier.width(cardWidth),
                    focused = event.id == state.screen.selectedId,
                    saved = event.id in state.screen.savedIds,
                    onSave = { onIntent(ExploreIntent.ToggleSaved(event.id)) }
                ) { onIntent(ExploreIntent.OpenEvent(event.id)) }
            }
        }
    }
}

/** Піднята шторка: плитки категорій і видача списком. */
@Composable
private fun SheetList(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    // І в стосі: категорія звужує події закладу, як дата й «Від людей» над мапою, а не виводить у місто.
    Row(
        Modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = Spacing.page),
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        // Число — серед міста чи закладу, як лічильник після тапу.
        categories.forEach { category ->
            CategoryTile(
                category,
                state.screen.category == category,
                counted = true,
                count = state.screen.countOf(category)
            ) { onIntent(ExploreIntent.ToggleCategory(category)) }
        }
    }
    val rows = state.screen.deckEvents
    // Заклади пошуку — над подіями: список подій довгий, під ним їх ніхто б не побачив.
    val places = if (state.screen.stackFocused) emptyList() else state.screen.places
    val artists = if (state.screen.stackFocused) emptyList() else state.screen.artists
    if (rows.isEmpty() && places.isEmpty() && artists.isEmpty()) {
        if (state.screen.loading) Box(
            Modifier
                .fillMaxWidth()
                .padding(vertical = Spacing.section),
            Alignment.Center
        ) {
            PoruchLoader()
        } else QuietCard(Modifier.padding(Spacing.page), state, onIntent)
        return
    }
    val listState = rememberLazyListState()
    val lastVisible by remember {
        derivedStateOf {
            listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
        }
    }
    // Список довантажує картки сам, а не лише карусель.
    LaunchedEffect(lastVisible, rows.size, state.screen.hasMoreCards) {
        if (state.screen.hasMoreCards && lastVisible >= rows.size - PREFETCH_AHEAD) onIntent(
            ExploreIntent.LoadMore(
                rows.size + PAGE
            )
        )
    }
    LazyColumn(
        state = listState,
        contentPadding = PaddingValues(
            start = Spacing.page,
            end = Spacing.page,
            top = Spacing.xs,
            bottom = Spacing.section
        ),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        if (places.isNotEmpty()) item(key = "places") {
            PlacesGroup(places, withCity = false, Modifier.padding(bottom = Spacing.md)) { onIntent(ExploreIntent.FocusPlace(it)) }
        }
        if (artists.isNotEmpty()) item(key = "artists") {
            ArtistsGroup(artists, Modifier.padding(bottom = Spacing.md)) { onIntent(ExploreIntent.OpenArtist(it)) }
        }
        // Рядки з малим корінцем, як у пошуку головної: список відкривають, щоб зіставити варіанти, і картка
        // з фото 180 давала півтори події на екран. Фото й «Зберегти» — на картці каруселі й у деталях.
        items(rows, key = { it.id }) { event ->
            EventResultRow(
                event, Modifier.cardSurface(),
                waitlisted = event.id in state.screen.waitlistedIds,
                distance = state.screen.kmFromMe(event)?.let { distanceLabel(it, state.screen.nearWithinKm) }
            ) { onIntent(ExploreIntent.OpenEvent(event.id)) }
        }
        if (state.screen.hasMoreCards) item {
            Box(Modifier
                .fillMaxWidth()
                .padding(vertical = Spacing.lg), Alignment.Center) {
                CircularProgressIndicator(
                    Modifier.size(20.dp),
                    color = colors.brand,
                    strokeWidth = 2.dp
                )
            }
        }
    }
}

/** Порожньо: називаємо те, що справді звужує видачу, і даємо одну дію — прибрати це або зібрати своїх. */
@Composable
private fun QuietCard(modifier: Modifier, state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    val query = state.screen.searchText.trim()
    val (action, intent) = when {
        query.isNotEmpty() -> R.string.clear_search to ExploreIntent.Search("")
        state.screen.activeFilters > 0 -> R.string.reset_filters_action to ExploreIntent.ResetFilters
        else -> R.string.create to ExploreIntent.CreateEvent
    }
    // Дія — у рядку заголовка: у згорнутій шторці картка має висоту каруселі, і під текстом дію зрізало.
    Column(
        modifier
            .fillMaxWidth()
            .cardSurface()
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(
                stringResource(R.string.nothing_here),
                style = PoruchType.brandTitle3,
                color = colors.ink,
                modifier = Modifier.weight(1f)
            )
            GhostButton(stringResource(action), { onIntent(intent) })
        }
        Text(
            when {
                query.isNotEmpty() -> stringResource(R.string.nothing_for_query, query)
                // У стосі область мапи не допоможе: тут звужують лише фільтри.
                state.screen.stackFocused -> stringResource(R.string.nothing_here_stack)
                else -> stringResource(R.string.nothing_here_hint)
            },
            style = MaterialTheme.typography.bodySmall,
            color = colors.inkSecondary
        )
    }
}

/** За скільки карток до кінця просити наступні: приблизно екран списку. */
private const val PREFETCH_AHEAD = 8

/** Скільки карток каруселі ще доїжджаємо анімацією; далі — стрибок. */
private const val NEAR_CARDS = 3

/** Скільки карток додає одне довантаження. */
internal const val PAGE = 24

