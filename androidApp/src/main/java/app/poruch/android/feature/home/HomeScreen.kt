package app.poruch.android.feature.home

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.feature.explore.CitySearchSheet
import app.poruch.android.feature.explore.dateFilters
import app.poruch.android.feature.mine.countdownOverline
import app.poruch.android.platform.openInMaps
import app.poruch.android.ui.*
import app.poruch.domain.CityResult
import app.poruch.domain.Event
import app.poruch.domain.FeedEntry
import app.poruch.domain.FeedFilter
import app.poruch.domain.FeedFilterKind
import app.poruch.domain.FeedSource
import app.poruch.domain.HomeRules
import java.time.LocalDate
import java.time.ZoneId
import app.poruch.shared.DateFilter

/** Головна з двох зон: «Ваше» (плани, чати, підписки) і «У місті» (одна стрічка з даних, які вже завантажила мапа). Малює [HomeState], шле [HomeIntent]. */
@Composable
fun HomeScreen(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    PullToRefresh(state.refreshing, { onIntent(HomeIntent.Refresh) }, Modifier.fillMaxSize().background(colors.canvas), underStatusBar = true) {
        // Сяйво позаду прокрутки: картки їдуть по ньому, а воно стоїть.
        if (!state.searchMode) Box(
            Modifier.fillMaxWidth().height(460.dp).background(Brush.verticalGradient(listOf(colors.glow, colors.canvas)))
        )
        // Лінивий список: «Показати ще» росте без меж, а постерів у композиції має бути стільки, скільки видно.
        // Проміжки між блоками — відступами самих блоків: вони різні всередині «У місті» й між зонами.
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = tabBarClearancePadding(top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding())
        ) {
            item(key = "header") { Header(state, onIntent) }
            // Стрічка й фільтри пошуку ніколи разом: у режимі пошуку — видача або підказка.
            if (state.searchMode) item(key = "search") {
                Column(Modifier.padding(top = Spacing.xxl), verticalArrangement = Arrangement.spacedBy(Spacing.xxl)) {
                    if (state.searching) SearchResults(state, onIntent)
                    else EmptyState(
                        PoruchIcons.search, stringResource(R.string.search_hint_title),
                        if (state.searchEverywhere || state.cityName.isBlank()) stringResource(R.string.search_hint_everywhere)
                        else stringResource(R.string.search_hint_in_city, state.cityName)
                    )
                }
            } else {
                item(key = "yours") {
                    Box(Modifier.padding(top = Spacing.xxl)) {
                        if (state.signedIn) PersonalSection(state, onIntent) else BannerCard(
                            stringResource(R.string.guest_home_slim), null,
                            { onIntent(HomeIntent.OpenProfile) }, Modifier.padding(horizontal = Spacing.page), PoruchIcons.lock
                        )
                    }
                }
                cityFeed(state, onIntent)
                // Кінець стрічки не глухий кут: далі мапа чи власна подія.
                if (state.feed.isNotEmpty()) item(key = "next") { MoreRows(state, onIntent) }
            }
        }
    }
    if (state.citySheet) CitySearchSheet(
        state.cityName, state.cities, { onIntent(HomeIntent.SearchCity(it)) },
        { onIntent(HomeIntent.SwitchCity(it)) }, { onIntent(HomeIntent.ShowCitySheet(false)) }
    )
}

@Composable
private fun Header(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.fillMaxWidth().padding(horizontal = Spacing.page).padding(top = Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        if (!state.searchMode) Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(stringResource(R.string.home_title), style = PoruchType.serifDisplay, color = colors.ink)
                // Що означає «поруч»: завжди ціле місто. «Шукати тут» на мапі головну не звужує.
                // Тап міняє місто тут же, без переходу на мапу.
                Row(
                    Modifier.clickable(onClickLabel = stringResource(R.string.city_search), role = Role.Button) {
                        onIntent(HomeIntent.ShowCitySheet(true))
                    },
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        stringResource(R.string.home_subtitle, state.cityName),
                        // Темніший за `inkSecondary`: на сяйві той дає лише ≈4:1.
                        style = MaterialTheme.typography.bodyMedium, color = colors.ink.copy(alpha = 0.7f),
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Icon(Icons.Outlined.ExpandMore, null, Modifier.size(18.dp), tint = colors.ink.copy(alpha = 0.7f))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                IconPill(PoruchIcons.search, stringResource(R.string.home_search_action)) { onIntent(HomeIntent.EnterSearch) }
                IconPill(PoruchIcons.person, stringResource(R.string.profile)) { onIntent(HomeIntent.OpenProfile) }
            }
        } else {
            val focus = LocalFocusManager.current
            val cancel = { focus.clearFocus(); onIntent(HomeIntent.CancelSearch) }
            BackHandler(true, cancel)
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                // Плейсхолдер каже, де шукаємо: інакше пошук лише в місті ніхто не помічав.
                PoruchSearchField(
                    state.searchText, { onIntent(HomeIntent.Search(it)) },
                    when {
                        state.searchEverywhere -> stringResource(R.string.home_search_everywhere)
                        state.cityName.isBlank() -> stringResource(R.string.search_placeholder)
                        else -> stringResource(R.string.home_search_in_city, state.cityName)
                    },
                    Modifier.weight(1f), autoFocus = true
                )
                GhostButton(stringResource(R.string.cancel), cancel)
            }
            SearchFilters(state, onIntent)
        }
    }
}

/** Фільтри пошуку тими ж чипами, що на мапі: область і дата в одному ряду, категорії — у другому. */
@Composable
private fun SearchFilters(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
        ) {
            if (state.cityName.isNotBlank()) PoruchChip(
                state.cityName, !state.searchEverywhere, { onIntent(HomeIntent.SearchEverywhere(false)) }, PoruchIcons.pin
            )
            PoruchChip(
                stringResource(R.string.everywhere), state.searchEverywhere,
                { onIntent(HomeIntent.SearchEverywhere(!state.searchEverywhere)) }, Icons.Outlined.Public
            )
            dateFilters.forEach { (key, label) ->
                // Повторний тап знімає вибір, як на мапі.
                PoruchChip(stringResource(label), state.searchDate == key, {
                    onIntent(HomeIntent.SearchDate(if (state.searchDate == key) DateFilter.ANY else key))
                })
            }
        }
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
        ) {
            PoruchChip(stringResource(R.string.all), state.searchCategory == null, { onIntent(HomeIntent.SearchCategory(null)) })
            categories.forEach { key ->
                PoruchChip(stringResource(categoryLabel(key)), state.searchCategory == key, {
                    onIntent(HomeIntent.SearchCategory(if (state.searchCategory == key) null else key))
                }, dot = key)
            }
        }
    }
}

/** Обкладинка-плитка блоку «Ваше». */
private val YourTile = 52.dp

/**
 * «Ваше»: найближчий план карткою з діями, решта планів і підписки — рядками під нею. Гостю блоку нема.
 * Блок є завжди, поки людина увійшла: без планів він кличе створити подію, а не зникає.
 */
@Composable
private fun PersonalSection(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val now = kotlin.time.Clock.System.now()
    val zoneId = ZoneId.systemDefault().id
    // Велика картка — першому плану, що скоро чи чекає на людину; минула чи далека подія лишається рядком.
    val lead = state.personal.firstOrNull { HomeRules.isLead(it.event, it.chat != null || it.requests > 0, now, zoneId) }
    val inset = Modifier.padding(start = Spacing.lg + YourTile + Spacing.md)
    val rows = buildList<@Composable () -> Unit> {
        if (state.personal.isEmpty()) add { EmptyPlansRow(onIntent) }
        state.personal.filter { it !== lead }.forEach { row -> add { PlanRow(row, onIntent) } }
        if (state.moreWaiting > 0) add { WaitingRow(state.moreWaiting, onIntent) }
        if (state.followed.isNotEmpty()) add { FollowsRow(state.followed) { onIntent(HomeIntent.OpenFollows) } }
    }
    Column(Modifier.padding(horizontal = Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(
            stringResource(R.string.home_yours),
            actionLabel = if (state.personal.isEmpty()) null else stringResource(R.string.my_events),
            onAction = { onIntent(HomeIntent.OpenMyEvents) }, serif = true
        )
        lead?.let { NextPlanCard(it, onIntent) }
        if (rows.isNotEmpty()) GroupedRows {
            rows.forEachIndexed { position, row ->
                if (position > 0) HairLine(inset)
                row()
            }
        }
    }
}

/** Гліф у плитці рядка «Ваше» (підписки, порожній стан, «чекають відповіді»). */
@Composable
private fun YourTileIcon(icon: ImageVector) {
    val colors = Poruch.colors
    Box(Modifier.size(YourTile).background(colors.surfaceMuted, Radius.sm), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(20.dp), tint = colors.ink)
    }
}

/** Планів нема: рядок кличе створити, а вибрати з афіші можна нижче. */
@Composable
private fun EmptyPlansRow(onIntent: (HomeIntent) -> Unit) {
    YourRow(
        overline = null, title = stringResource(R.string.home_plans_empty), subtitle = stringResource(R.string.home_plans_empty_hint),
        onClick = { onIntent(HomeIntent.CreateEvent) }, tile = { YourTileIcon(Icons.Outlined.Add) }
    ) { Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp), tint = Poruch.colors.inkTertiary) }
}

/** Ті, що чекають відповіді, але в «Ваше» не влізли: їх видно лише в «Моїх подіях». */
@Composable
private fun WaitingRow(count: Int, onIntent: (HomeIntent) -> Unit) {
    YourRow(
        overline = null, title = stringResource(R.string.home_waiting_more, count), subtitle = stringResource(R.string.home_waiting_more_hint),
        onClick = { onIntent(HomeIntent.OpenMyEvents) }, tile = { YourTileIcon(Icons.Outlined.ChatBubbleOutline) }
    ) { Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp), tint = Poruch.colors.inkTertiary) }
}

/**
 * Рядок блоку «Ваше»: плитка, надрядок, назва, підпис. [trailing] лежить у тапі рядка, а лічильник чату
 * ([chat]: скільки й куди) — окремою кнопкою праворуч.
 */
@Composable
private fun YourRow(
    overline: String?, title: String, subtitle: String?, onClick: () -> Unit,
    tile: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    chat: Pair<Int, () -> Unit>? = null,
    /** Назва події (а не службового рядка) — засічками, як у постері. */
    serifTitle: Boolean = false,
    trailing: @Composable () -> Unit = {}
) {
    val colors = Poruch.colors
    Row(
        modifier.fillMaxWidth().padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier.weight(1f).semantics(mergeDescendants = true) {}.pressable(pressedScale = 1f, onClick = onClick),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
        ) {
            tile()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                overline?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(
                    title, style = if (serifTitle) PoruchType.serifTitle3 else MaterialTheme.typography.titleSmall,
                    color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis
                )
                subtitle?.takeIf { it.isNotBlank() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            if (chat == null) trailing()
        }
        chat?.let { (count, open) ->
            val label = stringResource(R.string.home_chat_a11y, count)
            Box(
                Modifier.minimumInteractiveComponentSize().clip(CircleShape).pressable(onClick = open)
                    .semantics { contentDescription = label },
                contentAlignment = Alignment.Center
            ) { CountBadge(count) }
        }
    }
}

/** Своя подія: категорія плиткою, час, назва. Праворуч — про що просять: нове в чаті, запити, або просто «Ви йдете». */
@Composable
private fun PlanRow(row: PersonalRow, onIntent: (HomeIntent) -> Unit) {
    val event = row.event
    // Моя роль в події; після кінця вона нічого не каже.
    val role: Pair<String, BadgeTone>? = when {
        event.isCancelled -> stringResource(R.string.cancelled) to BadgeTone.Danger
        event.hasEnded(kotlin.time.Clock.System.now()) -> null
        row.organizing -> stringResource(R.string.home_role_organizer) to BadgeTone.Brand
        else -> stringResource(R.string.going) to BadgeTone.Success
    }
    // Праворуч зайнято лічильником чи запитами: роль переїжджає до дати.
    val overline = cardOverline(event, dateWords()).let { date ->
        if ((row.chat != null || row.requests > 0) && role != null) "$date · ${role.first.uppercase()}" else date
    }
    val subtitle = row.chat?.let { chat ->
        val body = chat.lastBody.replace('\n', ' ')
        if (body.isBlank()) pluralStringResource(R.plurals.chat_unread_count, chat.unread, chat.unread)
        else stringResource(R.string.home_chat_preview, chat.lastAuthorName.ifBlank { stringResource(R.string.chat_member) }, body)
    } ?: event.placeLabel
    YourRow(
        overline, event.displayTitle, subtitle, onClick = { onIntent(HomeIntent.OpenEvent(event.id, "home_your")) },
        tile = { EventImage(event, Modifier.size(YourTile).clip(Radius.sm), glyphSize = 24.dp) },
        modifier = Modifier.alpha(if (event.isCancelled) 0.6f else 1f),
        // Лічильник — кнопка в чат, поки праворуч не зайняли запити: на них теж чекає людина, і вони важливіші.
        chat = row.chat?.takeIf { row.requests == 0 }?.let { it.unread to { onIntent(HomeIntent.OpenChat(event.id)) } },
        serifTitle = true
    ) {
        when {
            row.requests > 0 -> StatusBadge(
                pluralStringResource(R.plurals.requests_count, row.requests, row.requests), BadgeTone.Accent, Icons.Outlined.PersonAdd
            )
            role != null -> StatusBadge(role.first, role.second)
        }
    }
}

/** Кнопка-пігулка картки плану. Підсвічена (чорнилом), коли за нею є що робити: нове в чаті, запити. */
@Composable
private fun PlanButton(text: String, icon: ImageVector, modifier: Modifier = Modifier, highlight: Boolean = false, onClick: () -> Unit) {
    val colors = Poruch.colors
    val content = if (highlight) colors.onBrand else colors.ink
    Row(
        modifier.height(44.dp).background(if (highlight) colors.brand else colors.brandContainer, Radius.pill).clip(Radius.pill)
            .pressable(onClick = onClick).padding(horizontal = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, Modifier.size(16.dp), tint = content)
        Text(text, style = MaterialTheme.typography.labelMedium, color = content, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Найближчий план великою карткою, як посадковий талон: відлік, назва, місце й дії — маршрут, чат, запити. */
@Composable
private fun NextPlanCard(row: PersonalRow, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    val context = LocalContext.current
    val event = row.event
    // Відлік лише для сьогоднішнього: «через 25 год» про завтрашнє нічого не каже.
    val today = runCatching {
        java.time.Instant.parse(event.startsAt).atZone(ZoneId.systemDefault()).toLocalDate() == LocalDate.now()
    }.getOrDefault(false)
    val overline = if (today) countdownOverline(event) else cardOverline(event, dateWords())
    // Остання репліка чату, коли є нове; інакше моя роль і місце в один рядок: повна адреса живе в «Маршруті».
    val chat = row.chat
    val preview = chat?.takeIf { it.lastBody.isNotBlank() }?.let {
        stringResource(R.string.home_chat_preview, it.lastAuthorName.ifBlank { stringResource(R.string.chat_member) }, it.lastBody.replace('\n', ' '))
    }
    val role = stringResource(if (row.organizing) R.string.home_role_organizer else R.string.going)
    val subtitle = preview ?: listOf(role, event.placeLabel).filter { it.isNotBlank() }.joinToString(" · ")
    Column(
        Modifier.fillMaxWidth().cardSurface(Radius.xl).padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        Row(
            Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}
                .pressable(pressedScale = 1f) { onIntent(HomeIntent.OpenEvent(event.id, "home_your")) },
            horizontalArrangement = Arrangement.spacedBy(Spacing.lg), verticalAlignment = Alignment.Top
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(overline, style = MaterialTheme.typography.labelSmall, color = colors.accentText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(event.displayTitle, style = PoruchType.serifTitle2, color = colors.ink, maxLines = 3, overflow = TextOverflow.Ellipsis)
                Text(
                    subtitle, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary,
                    maxLines = if (preview == null) 1 else 2, overflow = TextOverflow.Ellipsis
                )
            }
            EventImage(event, Modifier.size(88.dp).clip(Radius.md), glyphSize = 30.dp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            // Маршрут — головна дія, поки подія сьогодні й ще не почалась; далі — звичайна.
            PlanButton(
                stringResource(R.string.open_in_maps), Icons.Outlined.Directions, Modifier.weight(1f),
                highlight = today && !event.hasStarted(kotlin.time.Clock.System.now())
            ) { context.openInMaps(event) }
            PlanButton(
                if (chat != null) stringResource(R.string.chat_short_unread, chat.unread) else stringResource(R.string.chat_short),
                Icons.Outlined.ChatBubbleOutline, Modifier.weight(1f), highlight = chat != null
            ) { onIntent(HomeIntent.OpenChat(event.id)) }
            if (row.requests > 0) PlanButton(
                stringResource(R.string.home_requests_short, row.requests), Icons.Outlined.PersonAdd, Modifier.weight(1f), highlight = true
            ) { onIntent(HomeIntent.OpenEvent(event.id, "home_your")) }
        }
    }
}

/** «Підписки: 3 події» і, що саме, — першою назвою. Тап веде на екран підписок. */
@Composable
private fun FollowsRow(events: List<Event>, onClick: () -> Unit) {
    val colors = Poruch.colors
    val more = events.size - 1
    val first = events.first().displayTitle
    YourRow(
        overline = null, title = pluralStringResource(R.plurals.home_follows_events, events.size, events.size),
        subtitle = if (more > 0) stringResource(R.string.home_follows_more, first, more) else first,
        onClick = onClick,
        tile = { YourTileIcon(Icons.Outlined.NotificationsActive) }
    ) { Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary) }
}

/** Підпис джерела в стрічці: «Для вас», «Підписки». Афіша міста без підпису. */
@Composable
private fun lane(source: FeedSource): String? = when (source) {
    FeedSource.FOR_YOU -> stringResource(R.string.picked_for_you)
    FeedSource.FOLLOWING -> stringResource(R.string.follows_title)
    FeedSource.CITY -> null
}

/** «У місті»: великі картки, що гортаються (сусідня визирає), чипи, далі сітка постерів у дві колонки. */
private fun LazyListScope.cityFeed(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    when {
        state.feed.isNotEmpty() -> {
            val picks = state.feed.take(HERO_COUNT)
            val rest = state.feed.drop(HERO_COUNT)
            item(key = "city") {
                Column(Modifier.padding(top = Spacing.xxl), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    SectionHeader(
                        stringResource(R.string.home_in_city), Modifier.padding(horizontal = Spacing.page),
                        actionLabel = state.totalFound.takeIf { it > 0 }?.let { stringResource(R.string.home_all_count, it) },
                        onAction = { onIntent(HomeIntent.OpenMap) }, serif = true
                    )
                    HeroPager(picks, state, onIntent)
                    if (state.chips.isNotEmpty()) FeedChips(state, onIntent)
                }
            }
            val rows = rest.take(state.feedLimit).chunked(2)
            itemsIndexed(rows, key = { _, pair -> pair.first().event.id }) { index, pair ->
                Row(
                    Modifier.padding(horizontal = Spacing.page).padding(top = if (index == 0) Spacing.xxl else Spacing.xl),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                ) {
                    pair.forEach { entry ->
                        PosterCard(
                            entry, entry.event.id in state.savedIds, entry.event.id in state.waitlistedIds,
                            { onIntent(HomeIntent.ToggleSaved(entry.event.id)) }, Modifier.weight(1f)
                        ) { onIntent(HomeIntent.OpenEvent(entry.event.id, "home_poster")) }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
            if (rest.size > state.feedLimit) item(key = "more-feed") {
                SecondaryButton(
                    stringResource(R.string.show_more), { onIntent(HomeIntent.ShowMoreFeed) },
                    Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.xl).fillMaxWidth()
                )
            }
        }
        state.isEmpty && state.loading -> item(key = "loading") {
            Box(Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center) { PoruchLoader() }
        }
        state.isEmpty -> item(key = "empty") {
            Box(Modifier.padding(top = Spacing.xxl)) {
                EmptyState(
                    Icons.Outlined.Explore, stringResource(R.string.nothing_here), stringResource(R.string.nothing_here_hint),
                    actionLabel = stringResource(R.string.find_on_map), onAction = { onIntent(HomeIntent.OpenMap) }
                )
            }
        }
    }
}

/** Ряд чипів над сіткою: час, безкоштовне й найбільші категорії. Звужує лише сітку, великі картки стоять. */
@Composable
private fun FeedChips(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    Row(
        Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
    ) {
        state.chips.forEach { chip ->
            PoruchChip(feedChipLabel(chip), chip == state.feedFilter, { onIntent(HomeIntent.SelectFeedFilter(chip)) }, dot = chip.category)
        }
    }
}

@Composable
private fun feedChipLabel(chip: FeedFilter): String = when (chip.kind) {
    FeedFilterKind.TODAY -> stringResource(R.string.today)
    FeedFilterKind.TOMORROW -> stringResource(R.string.tomorrow)
    FeedFilterKind.WEEKEND -> stringResource(R.string.weekend)
    FeedFilterKind.FREE -> stringResource(R.string.listing_free)
    FeedFilterKind.CATEGORY -> chip.category?.let { stringResource(categoryLabel(it)) } ?: stringResource(R.string.feed_all)
    FeedFilterKind.ALL -> stringResource(R.string.feed_all)
}

/** Гортана стрічка великих карток: наступна визирає з-за краю, як у Moonly. */
@Composable
private fun HeroPager(picks: List<FeedEntry>, state: HomeState, onIntent: (HomeIntent) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val pageWidth = if (picks.size > 1) maxWidth * 0.86f else maxWidth - Spacing.page * 2
        HorizontalPager(
            rememberPagerState { picks.size }, contentPadding = PaddingValues(horizontal = Spacing.page),
            pageSpacing = Spacing.md, pageSize = PageSize.Fixed(pageWidth)
        ) { index ->
            val entry = picks[index]
            EventHeroCard(
                entry.event, eyebrow = lane(entry.source), saved = entry.event.id in state.savedIds,
                onSave = { onIntent(HomeIntent.ToggleSaved(entry.event.id)) }
            ) { onIntent(HomeIntent.OpenEvent(entry.event.id, "home_hero")) }
        }
    }
}

/**
 * Постер у сітці «У місті»: обкладинка 4:5 без коробки, підпис просто на полотні. Ціна чи «3 з 8» — плашкою на фото,
 * стан кімнати («Ви йдете», «Лишилось 2») — плашкою нагорі замість підпису «Для вас».
 */
@Composable
private fun PosterCard(
    entry: FeedEntry, saved: Boolean, waitlisted: Boolean, onSave: () -> Unit, modifier: Modifier = Modifier, onClick: () -> Unit
) {
    val colors = Poruch.colors
    val event = entry.event
    // Скасоване й знята афіша вже сказані підписом внизу, двічі не пишемо.
    val state = if (event.gathering == null || event.isCancelled) null else eventState(event, waitlisted)
    val badge = state ?: lane(entry.source)?.let { it to BadgeTone.Neutral }
    // «Від 390 ₴» лише коли джерело сказало ціну; для кімнати — «3 з 8».
    val chip = event.gathering?.let { stringResource(R.string.attendees_short, it.attendeeCount, it.capacity) }
        ?: event.listing?.takeIf { it.isFree == true || it.priceMin != null }?.let { listingPrice(it) }
    // Афіша завжди підписана джерелом (docs/event-ingestion.md §8); скасоване — теж словами.
    val note: Pair<String, Color>? = when {
        event.isCancelled -> stringResource(R.string.cancelled) to colors.danger
        else -> event.listing?.let {
            (if (it.isWithdrawn) stringResource(R.string.listing_withdrawn) else stringResource(R.string.listing_badge, it.sourceName)) to colors.inkTertiary
        }
    }
    Column(
        modifier.semantics(mergeDescendants = true) {}.pressable(onClick = onClick).alpha(if (event.isCancelled) 0.6f else 1f),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(4f / 5f).clip(Radius.lg)) {
            EventArt(event, Modifier.fillMaxSize(), glyph = 130.dp)
            badge?.let { (text, tone) -> Box(Modifier.align(Alignment.TopStart).padding(Spacing.sm)) { StatusBadge(text, tone) } }
            SaveButton(saved, onSave, Modifier.align(Alignment.TopEnd).padding(Spacing.xs))
            chip?.let { Box(Modifier.align(Alignment.BottomStart).padding(Spacing.sm)) { StatusBadge(it) } }
        }
        Column(Modifier.padding(horizontal = Spacing.xs), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            // Коли — найважливіше в афіші, тож і найтемніше в підписі, а не найблідіше.
            Text(
                cardOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(
                event.displayTitle, style = PoruchType.serifTitle3, color = colors.ink,
                minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            EventDescriptor(event, placeFirst = true)
            note?.let { (text, color) ->
                Text(text, style = MaterialTheme.typography.labelSmall, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Куди далі, коли стрічку переглянуто: мапа з усім, що є, і створення власної події. */
@Composable
private fun MoreRows(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    Column(Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.xxl), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.home_next), serif = true)
        GroupedRows {
            LinkRow(
                PoruchIcons.map, stringResource(R.string.all_events_section), stringResource(R.string.all_events_hint),
                { onIntent(HomeIntent.OpenMap) }, value = state.totalFound.takeIf { it > 0 }?.toString()
            )
            HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
            LinkRow(
                PoruchIcons.sparkle, stringResource(R.string.create_banner_title), stringResource(R.string.create_banner_subtitle),
                { onIntent(HomeIntent.CreateEvent) }
            )
        }
    }
}

/** Результати пошуку одним списком. */
@Composable
private fun SearchResults(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    state.cityMatch?.let { city ->
        BannerCard(
            stringResource(R.string.home_switch_city, city.city),
            stringResource(R.string.home_switch_city_hint, state.cityName),
            onClick = { onIntent(HomeIntent.SwitchCity(CityResult(city.city, city.latitude, city.longitude))) },
            modifier = Modifier.padding(horizontal = Spacing.page), icon = PoruchIcons.pin
        )
    }
    when {
        state.isEmpty && state.busy -> Box(
            Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center
        ) { PoruchLoader() }
        // У місті порожньо — найближчий крок розширити область, а не йти на мапу.
        state.isEmpty && !state.searchEverywhere -> EmptyState(
            PoruchIcons.search, stringResource(R.string.nothing_found), stringResource(R.string.nothing_found_city_hint, state.cityName),
            actionLabel = stringResource(R.string.search_everywhere), onAction = { onIntent(HomeIntent.SearchEverywhere(true)) }
        )
        // Усюди без кнопки: мапа шукає лише в місті, тож розширювати вже нікуди.
        state.isEmpty -> EmptyState(PoruchIcons.search, stringResource(R.string.nothing_found), stringResource(R.string.nothing_found_hint))
        else -> Column(
            Modifier.padding(horizontal = Spacing.page).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.xl)
        ) {
            // Події, під ними — заклади з тим самим словом. Групові списки: видача пошуку — перелік, а не стрічка.
            if (state.results.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                GroupLabel(
                    stringResource(R.string.search_events_group, maxOf(state.resultsTotal, state.results.size)),
                    // Мапа шукає в межах міста, тож для «усюди» вона показала б інше.
                    actionLabel = if (state.searchEverywhere) null else stringResource(R.string.on_map),
                    onAction = { onIntent(HomeIntent.ShowResultsOnMap) }
                )
                GroupedRows {
                    state.results.take(state.resultsLimit).forEachIndexed { position, event ->
                        if (position > 0) HairLine(Modifier.padding(start = ResultRowInset))
                        EventResultRow(
                            event, waitlisted = event.id in state.waitlistedIds, withCity = state.searchEverywhere
                        ) { onIntent(HomeIntent.OpenEvent(event.id, "home_search")) }
                    }
                }
                if (state.resultsIndexed > state.resultsLimit) SecondaryButton(
                    stringResource(R.string.show_more), { onIntent(HomeIntent.ShowMoreResults) }, Modifier.fillMaxWidth()
                )
            }
            if (state.places.isNotEmpty()) PlacesGroup(state.places, state.searchEverywhere) { onIntent(HomeIntent.OpenPlace(it)) }
        }
    }
}
