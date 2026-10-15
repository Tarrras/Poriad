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
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
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
import app.poruch.shared.PersonalRow

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
                    if (state.screen.searching) SearchResults(state, onIntent)
                    else EmptyState(
                        PoruchIcons.search, stringResource(R.string.search_hint_title),
                        if (state.screen.searchEverywhere || state.screen.cityName.isBlank()) stringResource(R.string.search_hint_everywhere)
                        else stringResource(R.string.search_hint_in_city, state.screen.cityName)
                    )
                }
            } else {
                // Головна одиниця застосунку — зустріч від людини: заклик створити її стоїть першим, як колись «Організувати».
                // Гостю під плашкою лише тихий рядок входу (без картки): дві картки поспіль товпились би.
                item(key = "create") {
                    Column(Modifier.padding(top = Spacing.xxl), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        CreateEventCard(
                            stringResource(R.string.home_create_title), stringResource(R.string.home_create_subtitle),
                            { onIntent(HomeIntent.CreateEvent("home_top")) }, Modifier.padding(horizontal = Spacing.page)
                        )
                        if (!state.screen.signedIn) GuestLoginRow(onIntent)
                    }
                }
                // Людині без планів і підписок «Ваше» не потрібне: створити подію їй пропонує плашка вгорі.
                if (state.screen.signedIn && (state.screen.personal.isNotEmpty() || state.screen.followed.isNotEmpty())) item(key = "yours") {
                    Box(Modifier.padding(top = Spacing.xxl)) { PersonalSection(state, onIntent) }
                }
                if (state.screen.people.isNotEmpty()) item(key = "people") { PeopleSection(state, onIntent) }
                cityFeed(state, onIntent)
                // Кінець стрічки не глухий кут: далі мапа чи власна подія.
                if (state.screen.feed.isNotEmpty()) item(key = "next") { MoreRows(state, onIntent) }
            }
        }
    }
    if (state.citySheet) CitySearchSheet(
        state.screen.cityName, state.screen.cities, { onIntent(HomeIntent.SearchCity(it)) },
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
                        stringResource(R.string.home_subtitle, state.screen.cityName),
                        // Темніший за `inkSecondary`: на сяйві той дає лише ≈4:1.
                        style = MaterialTheme.typography.bodyMedium, color = colors.ink.copy(alpha = 0.7f),
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Icon(PoruchIcons.chevronDown, null, Modifier.size(18.dp), tint = colors.ink.copy(alpha = 0.7f))
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
                    state.screen.searchText, { onIntent(HomeIntent.Search(it)) },
                    when {
                        state.screen.searchEverywhere -> stringResource(R.string.home_search_everywhere)
                        state.screen.cityName.isBlank() -> stringResource(R.string.search_placeholder)
                        else -> stringResource(R.string.home_search_in_city, state.screen.cityName)
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
            if (state.screen.cityName.isNotBlank()) PoruchChip(
                state.screen.cityName, !state.screen.searchEverywhere, { onIntent(HomeIntent.SearchEverywhere(false)) }, PoruchIcons.pin
            )
            PoruchChip(
                stringResource(R.string.everywhere), state.screen.searchEverywhere,
                { onIntent(HomeIntent.SearchEverywhere(!state.screen.searchEverywhere)) }, PoruchIcons.globe
            )
            dateFilters.forEach { (key, label) ->
                // Повторний тап знімає вибір, як на мапі.
                PoruchChip(stringResource(label), state.screen.searchDate == key, {
                    onIntent(HomeIntent.SearchDate(if (state.screen.searchDate == key) DateFilter.ANY else key))
                })
            }
        }
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
        ) {
            PoruchChip(stringResource(R.string.all), state.screen.searchCategory == null, { onIntent(HomeIntent.SearchCategory(null)) })
            categories.forEach { key ->
                PoruchChip(stringResource(categoryLabel(key)), state.screen.searchCategory == key, {
                    onIntent(HomeIntent.SearchCategory(if (state.screen.searchCategory == key) null else key))
                }, dot = key)
            }
        }
    }
}

/** Рядок входу для гостя: плашка вгорі — єдина головна дія, а вхід — для тих, хто вже має профіль, тож без картки й заливки. */
@Composable
private fun GuestLoginRow(onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Spacing.page).minimumInteractiveComponentSize()
            .pressable(pressedScale = 1f) { onIntent(HomeIntent.OpenProfile) }.padding(horizontal = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        Icon(PoruchIcons.lock, null, Modifier.size(14.dp), tint = colors.inkSecondary)
        Text(
            stringResource(R.string.guest_home_slim), style = MaterialTheme.typography.labelMedium, color = colors.inkSecondary,
            modifier = Modifier.weight(1f)
        )
        Icon(PoruchIcons.chevronRight, null, Modifier.size(16.dp), tint = colors.inkSecondary)
    }
}

/** Ширина постера в рейці «Від людей»: як в одній колонці сітки, щоб третій визирав із-за краю. */
private val PeopleCardWidth = 176.dp

/**
 * «Від людей»: зустрічі з вільним місцем окремою рейкою, коли їх набралось досить ([HomeRules.people]). Ті самі постери,
 * що в сітці міста, але без підпису походження: заголовок секції вже каже, що це люди.
 */
@Composable
private fun PeopleSection(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    Column(Modifier.padding(top = Spacing.xxl), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(
            stringResource(R.string.from_people), Modifier.padding(horizontal = Spacing.page),
            actionLabel = state.screen.openRooms.takeIf { it > 0 }?.let { stringResource(R.string.home_all_count, it) },
            onAction = { onIntent(HomeIntent.ShowPeopleOnMap) }
        )
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.Top
        ) {
            state.screen.people.forEach { entry ->
                PosterCard(
                    entry.event, entry.source, entry.event.id in state.screen.savedIds, entry.event.id in state.screen.waitlistedIds,
                    { onIntent(HomeIntent.ToggleSaved(entry.event.id)) }, Modifier.width(PeopleCardWidth), showOrigin = false,
                    followName = entry.followName
                ) { onIntent(HomeIntent.OpenEvent(entry.event.id, "home_people")) }
            }
        }
    }
}

/** Обкладинка-плитка блоку «Ваше». */
private val YourTile = 52.dp

/** «Ваше»: найближчий план карткою з діями, решта планів і підписки — рядками під нею. Гостю блоку нема, як і людині без планів і підписок. */
@Composable
private fun PersonalSection(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val now = kotlin.time.Clock.System.now()
    val zoneId = ZoneId.systemDefault().id
    // Велика картка — першому плану, що скоро чи чекає на людину; минула чи далека подія лишається рядком.
    val lead = state.screen.personal.firstOrNull { HomeRules.isLead(it.event, it.chat != null || it.requests > 0, now, zoneId) }
    val inset = Modifier.padding(start = Spacing.lg + YourTile + Spacing.md)
    val rows = buildList<@Composable () -> Unit> {
        state.screen.personal.filter { it !== lead }.forEach { row -> add { PlanRow(row, onIntent) } }
        if (state.screen.moreWaiting > 0) add { WaitingRow(state.screen.moreWaiting, onIntent) }
        if (state.screen.followed.isNotEmpty()) add {
            FollowsRow(state.screen.followNames, state.screen.followed, state.screen.newFollowEvents) { onIntent(HomeIntent.OpenFollows) }
        }
    }
    Column(Modifier.padding(horizontal = Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(
            stringResource(R.string.home_yours),
            actionLabel = if (state.screen.personal.isEmpty()) null else stringResource(R.string.my_events),
            onAction = { onIntent(HomeIntent.OpenMyEvents) }
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

/** Ті, що чекають відповіді, але в «Ваше» не влізли: їх видно лише в «Моїх подіях». */
@Composable
private fun WaitingRow(count: Int, onIntent: (HomeIntent) -> Unit) {
    YourRow(
        overline = null, title = stringResource(R.string.home_waiting_more, count), subtitle = stringResource(R.string.home_waiting_more_hint),
        onClick = { onIntent(HomeIntent.OpenMyEvents) }, tile = { YourTileIcon(PoruchIcons.chat) }
    ) { Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = Poruch.colors.inkTertiary) }
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
                pluralStringResource(R.plurals.requests_count, row.requests, row.requests), BadgeTone.Accent, PoruchIcons.personAdd
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
                stringResource(R.string.open_in_maps), PoruchIcons.directions, Modifier.weight(1f),
                highlight = today && !event.hasStarted(kotlin.time.Clock.System.now())
            ) { context.openInMaps(event) }
            PlanButton(
                if (chat != null) stringResource(R.string.chat_short_unread, chat.unread) else stringResource(R.string.chat_short),
                PoruchIcons.chat, Modifier.weight(1f), highlight = chat != null
            ) { onIntent(HomeIntent.OpenChat(event.id)) }
            if (row.requests > 0) PlanButton(
                stringResource(R.string.home_requests_short, row.requests), PoruchIcons.personAdd, Modifier.weight(1f), highlight = true
            ) { onIntent(HomeIntent.OpenEvent(event.id, "home_your")) }
        }
    }
}

/** «Ви стежите» і за ким — двома першими іменами, як і веде тап: на екран «Ви стежите». Імен нема (список не доїхав) — назва події. */
@Composable
private fun FollowsRow(names: List<String>, events: List<Event>, new: Int, onClick: () -> Unit) {
    val colors = Poruch.colors
    val shown = if (names.isEmpty()) events.first().displayTitle else names.take(2).joinToString(", ")
    YourRow(
        overline = null, title = stringResource(R.string.follows_title),
        subtitle = if (names.size > 2) stringResource(R.string.home_follows_more, shown, names.size - 2) else shown,
        onClick = onClick,
        tile = { YourTileIcon(PoruchIcons.bellActive) }
    ) {
        // Нове ще не переглянуте — бейдж замість шеврона: рядок тепер про те, що чекає.
        if (new > 0) StatusBadge(pluralStringResource(R.plurals.follows_new, new, new), BadgeTone.Accent)
        else Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
    }
}

/** Підпис джерела в стрічці: «Для вас», «Ви стежите · МУР». Афіша міста без підпису. */
@Composable
private fun lane(source: FeedSource, followName: String?): String? = when (source) {
    FeedSource.FOR_YOU -> stringResource(R.string.picked_for_you)
    FeedSource.FOLLOWING -> followName?.let { stringResource(R.string.follow_via, it) } ?: stringResource(R.string.following)
    FeedSource.CITY -> null
}

/** «У місті»: великі картки, що гортаються (сусідня визирає), чипи, далі сітка постерів у дві колонки. */
private fun LazyListScope.cityFeed(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    when {
        state.screen.feed.isNotEmpty() -> {
            val picks = state.screen.feed.take(HomeRules.HERO_COUNT)
            val rest = state.screen.feed.drop(HomeRules.HERO_COUNT)
            item(key = "city") {
                Column(Modifier.padding(top = Spacing.xxl), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    SectionHeader(
                        stringResource(R.string.home_in_city), Modifier.padding(horizontal = Spacing.page),
                        actionLabel = state.screen.totalFound.takeIf { it > 0 }?.let { stringResource(R.string.home_all_count, it) },
                        onAction = { onIntent(HomeIntent.ShowEverythingOnMap) }
                    )
                    HeroPager(picks, state.screen.savedIds, onIntent)
                    if (state.screen.chips.isNotEmpty()) FeedChips(state, onIntent)
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
                            entry.event, entry.source, entry.event.id in state.screen.savedIds, entry.event.id in state.screen.waitlistedIds,
                            { onIntent(HomeIntent.ToggleSaved(entry.event.id)) }, Modifier.weight(1f), followName = entry.followName
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
        state.screen.isEmpty && state.screen.loading -> item(key = "loading") {
            Box(Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center) { PoruchLoader() }
        }
        state.screen.isEmpty -> item(key = "empty") {
            Box(Modifier.padding(top = Spacing.xxl)) {
                EmptyState(
                    PoruchIcons.compass, stringResource(R.string.nothing_here), stringResource(R.string.nothing_here_hint),
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
        state.screen.chips.forEach { chip ->
            PoruchChip(feedChipLabel(chip), chip == state.screen.feedFilter, { onIntent(HomeIntent.SelectFeedFilter(chip)) }, dot = chip.category)
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
private fun HeroPager(picks: List<FeedEntry>, savedIds: List<String>, onIntent: (HomeIntent) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val pageWidth = if (picks.size > 1) maxWidth * 0.86f else maxWidth - Spacing.page * 2
        HorizontalPager(
            rememberPagerState { picks.size }, contentPadding = PaddingValues(horizontal = Spacing.page),
            pageSpacing = Spacing.md, pageSize = PageSize.Fixed(pageWidth)
        ) { index ->
            val entry = picks[index]
            EventHeroCard(
                entry.event, eyebrow = lane(entry.source, entry.followName), saved = entry.event.id in savedIds,
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
    // Подія й джерело окремо, а не `FeedEntry`: обгортка нова на кожну згортку стану, а екземпляр події
    // спільний стор зберігає — картка пропускає перескладання, поки не змінилась сама подія чи її стан.
    event: Event, source: FeedSource, saved: Boolean, waitlisted: Boolean, onSave: () -> Unit, modifier: Modifier = Modifier,
    /** Підпис «Від людей» на кімнаті без стану: у секції «Від людей» він зайвий. */
    showOrigin: Boolean = true,
    /** За ким саме подія з підписок: ім'я на плашці з дзвіночком. */
    followName: String? = null, onClick: () -> Unit
) {
    val colors = Poruch.colors
    // Скасоване й знята афіша вже сказані підписом внизу, двічі не пишемо.
    val state = if (event.gathering == null || event.isCancelled) null else eventState(event, waitlisted)
    // Вузька плашка: дзвіночок замість «Ви стежите», лишається саме ім'я.
    val following = state == null && source == FeedSource.FOLLOWING
    val badge = state ?: (if (following) followName ?: stringResource(R.string.following) else lane(source, followName))?.let { it to BadgeTone.Neutral }
    // Ні стану, ні «Для вас»: кімнату однаково видно як зустріч від людей.
    val fromPeople = showOrigin && badge == null && event.gathering != null
    // «Від 390 ₴» лише коли джерело сказало ціну; для кімнати — «3/8» з гліфом людей, як на iOS, де бейдж капсом і «3 З 8» читалось б «3 3 8».
    val chip: Pair<String, ImageVector?>? = event.gathering?.let { "${it.attendeeCount}/${it.capacity}" to PoruchIcons.social }
        ?: event.listing?.takeIf { it.isFree == true || it.priceMin != null }?.let { listingPrice(it) to null }
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
            badge?.let { (text, tone) ->
                Box(Modifier.align(Alignment.TopStart).padding(Spacing.sm)) { StatusBadge(text, tone, PoruchIcons.bellActive.takeIf { following }) }
            }
            if (fromPeople) Box(Modifier.align(Alignment.TopStart).padding(Spacing.sm)) {
                StatusBadge(stringResource(R.string.from_people), BadgeTone.Neutral, PoruchIcons.social)
            }
            SaveButton(saved, onSave, Modifier.align(Alignment.TopEnd).padding(Spacing.xs))
            chip?.let { (text, icon) -> Box(Modifier.align(Alignment.BottomStart).padding(Spacing.sm)) { StatusBadge(text, BadgeTone.Neutral, icon) } }
        }
        Column(Modifier.padding(horizontal = Spacing.xs), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            // Коли — найважливіше в афіші, тож і найтемніше в підписі, а не найблідіше.
            val words = dateWords()
            Text(
                remember(event) { cardOverline(event, words) }, style = PoruchType.overline, color = colors.ink,
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
        SectionHeader(stringResource(R.string.home_next))
        GroupedRows {
            LinkRow(
                PoruchIcons.map, stringResource(R.string.all_events_section), stringResource(R.string.all_events_hint),
                { onIntent(HomeIntent.ShowEverythingOnMap) }, value = state.screen.totalFound.takeIf { it > 0 }?.toString()
            )
            HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
            LinkRow(
                PoruchIcons.sparkle, stringResource(R.string.create_banner_title), stringResource(R.string.create_banner_subtitle),
                { onIntent(HomeIntent.CreateEvent("home_footer")) }
            )
        }
    }
}

/** Результати пошуку одним списком. */
@Composable
private fun SearchResults(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    state.screen.cityMatch?.let { city ->
        BannerCard(
            stringResource(R.string.home_switch_city, city.city),
            stringResource(R.string.home_switch_city_hint, state.screen.cityName),
            onClick = { onIntent(HomeIntent.SwitchCity(CityResult(city.city, city.latitude, city.longitude))) },
            modifier = Modifier.padding(horizontal = Spacing.page), icon = PoruchIcons.pin
        )
    }
    when {
        state.screen.isEmpty && state.screen.busy -> Box(
            Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center
        ) { PoruchLoader() }
        // У місті порожньо — найближчий крок розширити область, а не йти на мапу.
        state.screen.isEmpty && !state.screen.searchEverywhere -> EmptyState(
            PoruchIcons.search, stringResource(R.string.nothing_found), stringResource(R.string.nothing_found_city_hint, state.screen.cityName),
            actionLabel = stringResource(R.string.search_everywhere), onAction = { onIntent(HomeIntent.SearchEverywhere(true)) }
        )
        // Усюди без кнопки: мапа шукає лише в місті, тож розширювати вже нікуди.
        state.screen.isEmpty -> EmptyState(PoruchIcons.search, stringResource(R.string.nothing_found), stringResource(R.string.nothing_found_hint))
        else -> Column(
            Modifier.padding(horizontal = Spacing.page).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.xl)
        ) {
            // Події, під ними — заклади з тим самим словом. Групові списки: видача пошуку — перелік, а не стрічка.
            if (state.screen.results.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                GroupLabel(
                    stringResource(R.string.search_events_group, maxOf(state.screen.resultsTotal, state.screen.results.size)),
                    // Мапа шукає в межах міста, тож для «усюди» вона показала б інше.
                    actionLabel = if (state.screen.searchEverywhere) null else stringResource(R.string.on_map),
                    onAction = { onIntent(HomeIntent.ShowResultsOnMap) }
                )
                GroupedRows {
                    state.screen.results.take(state.resultsLimit).forEachIndexed { position, event ->
                        if (position > 0) HairLine(Modifier.padding(start = ResultRowInset))
                        EventResultRow(
                            event, waitlisted = event.id in state.screen.waitlistedIds, withCity = state.screen.searchEverywhere
                        ) { onIntent(HomeIntent.OpenEvent(event.id, "home_search")) }
                    }
                }
                if (state.screen.resultsIndexed > state.resultsLimit) SecondaryButton(
                    stringResource(R.string.show_more), { onIntent(HomeIntent.ShowMoreResults) }, Modifier.fillMaxWidth()
                )
            }
            if (state.screen.places.isNotEmpty()) PlacesGroup(state.screen.places, state.screen.searchEverywhere) { onIntent(HomeIntent.OpenPlace(it)) }
            if (state.screen.artists.isNotEmpty()) ArtistsGroup(state.screen.artists) { onIntent(HomeIntent.OpenArtist(it)) }
        }
    }
}
