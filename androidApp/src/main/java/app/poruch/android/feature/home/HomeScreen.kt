package app.poruch.android.feature.home

import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import app.poruch.domain.EventCategory
import androidx.compose.ui.semantics.heading
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import android.content.Context
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.edit
import app.poruch.android.DECK_WEEK
import app.poruch.android.SAVE_ASKED
import app.poruch.android.PROMPTS
import app.poruch.android.R
import app.poruch.shared.PoruchApp
import org.koin.compose.koinInject
import app.poruch.android.feature.explore.CitySearchSheet
import app.poruch.android.feature.explore.SEARCH_SETTLE_MS
import app.poruch.android.feature.explore.dateFilters
import app.poruch.android.feature.mine.countdownOverline
import app.poruch.android.feature.wallet.TodayTickets
import app.poruch.android.platform.openInMaps
import app.poruch.android.ui.*
import app.poruch.domain.CityResult
import app.poruch.domain.Event
import app.poruch.domain.FeedEntry
import app.poruch.domain.FeedFilter
import app.poruch.domain.FeedFilterKind
import app.poruch.domain.FeedSource
import app.poruch.domain.HomeRules
import app.poruch.domain.RadarDate
import java.time.LocalDate
import java.time.ZoneId
import app.poruch.shared.DateFilter
import app.poruch.shared.PersonalRow
import kotlinx.coroutines.delay

/** Головна з двох зон: «Ваше» (плани, чати, підписки) і «У місті» (одна стрічка з даних, які вже завантажила мапа). Малює [HomeState], шле [HomeIntent]. */
@Composable
fun HomeScreen(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    val focus = LocalFocusManager.current
    // «Назад» закриває пошук. На рівні екрана, а не в шапці: шапка — елемент лінивого списку, і після прокрутки
    // результатів її обробник зникав разом із нею, а «Назад» закривав застосунок.
    BackHandler(state.searchMode) { focus.clearFocus(); onIntent(HomeIntent.CancelSearch) }
    // Широке вікно — три квитки в ряду: два на 720 dp розтягували постер до пів екрана.
    val columns = if (LocalWideLayout.current) 3 else 2
    PullToRefresh(
        state.refreshing,
        { onIntent(HomeIntent.Refresh) },
        Modifier
            .fillMaxSize()
            .background(colors.canvas),
        underStatusBar = true
    ) {
        // Лінивий список: «Показати ще» росте без меж, а постерів у композиції має бути стільки, скільки видно.
        // Проміжки між блоками — відступами самих блоків: вони різні всередині «У місті» й між зонами.
        Column(Modifier.fillMaxSize()) {
        // Пошук: поле закріплене над видачею, як на iOS, — змінити запит можна, не гортаючи вгору.
        if (state.searchMode) Box(Modifier.statusBarsPadding()) { Header(state, onIntent) }
        val list = rememberLazyListState()
        LaunchedEffect(list) { HomeScrollToTop.requests.collect { list.animateScrollToItem(0) } }
        // Ряд чипів «У місті» липне вгорі, поки гортається сітка; волосина під ним — лише коли він уже над сіткою.
        val chipsStuck by remember {
            derivedStateOf {
                list.layoutInfo.visibleItemsInfo.firstOrNull { it.key == FEED_CHIPS }
                    ?.let { list.firstVisibleItemIndex > it.index || (list.firstVisibleItemIndex == it.index && list.firstVisibleItemScrollOffset > 0) } == true
            }
        }
        // Чип із закріпленого ряду міняє сітку: на її початок, а не посеред іншого списку.
        LaunchedEffect(state.screen.feedFilter) {
            val chips = list.layoutInfo.visibleItemsInfo.firstOrNull { it.key == FEED_CHIPS }?.index ?: return@LaunchedEffect
            if (list.firstVisibleItemIndex > chips) list.animateScrollToItem(chips)
        }
        // Список — під статус-баром, а не під ним з відступом: липкий ряд чипів інакше прилипав би під годинник.
        LazyColumn(
            Modifier.weight(1f).fillMaxWidth().then(if (state.searchMode) Modifier else Modifier.statusBarsPadding()),
            state = list,
            contentPadding = tabBarClearancePadding(top = 0.dp)
        ) {
            if (!state.searchMode) item(key = "header") { Header(state, onIntent) }
            // Стрічка й фільтри пошуку ніколи разом: у режимі пошуку — видача або підказка.
            if (state.searchMode) item(key = "search") {
                Column(
                    Modifier.padding(top = Spacing.xxl),
                    verticalArrangement = Arrangement.spacedBy(Spacing.xxl)
                ) {
                    if (state.screen.searching) SearchResults(state, onIntent)
                    else EmptyState(
                        PoruchIcons.search, stringResource(R.string.search_hint_title),
                        if (state.screen.searchEverywhere || state.screen.cityName.isBlank()) stringResource(
                            R.string.search_hint_everywhere
                        )
                        else stringResource(R.string.search_hint_in_city, state.screen.cityName)
                    )
                }
            } else {
                // День події: квиток — перше, що відкривають на вході.
                if (state.screen.todayTickets.isNotEmpty()) item(key = "today-tickets") {
                    TodayTickets(state.screen.todayTickets, Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.xxl))
                }
                // Серце продукту — з ким піти: зустрічі від людей і афіші, на які шукають компанію, однією рейкою, під нею
                // порожній квиток «Організувати подію». Активності не вигадуємо: коли зустрічей мало, секцію веде він.
                item(key = "people") { PeopleSection(state, onIntent) }
                // «Ваше» одразу після: непрочитаний чат і запит на участь не мають губитися під афішею. Усе особисте —
                // плани, «Ваш тиждень», дати артистів, підписки — одним блоком у чотири рядки (критика довжини 28.10).
                item(key = "yours") { PersonalSection(state, onIntent) }
                cityFeed(state, onIntent, columns, chipsStuck)
                // Кінець стрічки не глухий кут: далі мапа чи власна подія.
                if (state.screen.feed.isNotEmpty()) item(key = "next") { MoreRows(state, onIntent) }
            }
        }
        }
        StatusBarBand()
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
        Modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.page)
            .padding(top = Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        if (!state.searchMode) Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(
                    stringResource(R.string.home_title),
                    style = PoruchType.brandDisplay,
                    color = colors.ink
                )
                // Що означає «поруч»: завжди ціле місто. «Шукати тут» на мапі головну не звужує.
                // Тап міняє місто тут же, без переходу на мапу.
                // Ціль 48 dp: рядок міста — головний перемикач екрана, а текст у ньому 20 dp заввишки.
                Row(
                    Modifier
                        .coachTarget(CoachTip.CITY)
                        .clickable(
                            onClickLabel = stringResource(R.string.city_search),
                            role = Role.Button
                        ) {
                            onIntent(HomeIntent.ShowCitySheet(true))
                        }
                        .heightIn(min = 48.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        stringResource(R.string.home_subtitle, state.screen.cityName),
                        // Темніший за `inkSecondary`: місто — частина заголовка, а не підпис.
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.ink.copy(alpha = 0.7f),
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Icon(
                        PoruchIcons.chevronDown,
                        null,
                        Modifier.size(18.dp),
                        tint = colors.ink.copy(alpha = 0.7f)
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                IconPill(
                    PoruchIcons.search,
                    stringResource(R.string.home_search_action)
                ) { onIntent(HomeIntent.EnterSearch) }
                IconPill(
                    PoruchIcons.person,
                    stringResource(R.string.profile)
                ) { onIntent(HomeIntent.OpenProfile) }
            }
        } else {
            val focus = LocalFocusManager.current
            val cancel = { focus.clearFocus(); onIntent(HomeIntent.CancelSearch) }
            // Як поле мапи: набране тримаємо тут, нагору — після паузи. Текст зі стану презентера приходив на кадр пізніше,
            // і швидкий набір губив і переставляв літери («peresyp» → «pyper»). «Скасувати» прибирає поле разом із паузою.
            val shared = state.screen.searchText
            var text by rememberSaveable { mutableStateOf(shared) }
            var sent by rememberSaveable { mutableStateOf(shared) }
            LaunchedEffect(shared) {
                if (shared != sent) {
                    sent = shared; text = shared
                }
            }
            LaunchedEffect(text) {
                if (text == sent) return@LaunchedEffect
                delay(SEARCH_SETTLE_MS)
                sent = text
                onIntent(HomeIntent.Search(text))
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Плейсхолдер каже, де шукаємо: інакше пошук лише в місті ніхто не помічав.
                PoruchSearchField(
                    text, { text = it },
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
    var picking by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (state.screen.cityName.isNotBlank()) PoruchChip(
                state.screen.cityName,
                !state.screen.searchEverywhere,
                { onIntent(HomeIntent.SearchEverywhere(false)) },
                PoruchIcons.pin
            )
            PoruchChip(
                stringResource(R.string.everywhere),
                state.screen.searchEverywhere,
                { onIntent(HomeIntent.SearchEverywhere(!state.screen.searchEverywhere)) },
                PoruchIcons.globe
            )
            dateFilters.forEach { (key, label) ->
                // Повторний тап знімає вибір, як на мапі.
                PoruchChip(stringResource(label), state.screen.searchDate == key, {
                    onIntent(HomeIntent.SearchDate(if (state.screen.searchDate == key) DateFilter.ANY else key))
                })
            }
            // Категорії — одним чипом зі шторкою: дванадцять чипів другим рядом були стіною вибору.
            val category = state.screen.searchCategory
            PoruchChip(
                category?.let { stringResource(categoryLabel(it)) }
                    ?: stringResource(R.string.category_single),
                category != null,
                { picking = true },
                dot = category,
                trailingIcon = PoruchIcons.chevronDown
            )
        }
    }
    if (picking) CategoryPickerSheet(state.screen.searchCategory, { picking = false }) {
        onIntent(
            HomeIntent.SearchCategory(it)
        )
    }
}

/** Шторка категорії для пошуку: плитки всіх категорій і «Усі категорії». Відповідь спершу закриває шторку, потім діє. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryPickerSheet(
    selected: EventCategory?,
    onDismiss: () -> Unit,
    onSelect: (EventCategory?) -> Unit
) {
    PoruchSheet(onDismiss) { sheet ->
        Column(
            Modifier
                .padding(horizontal = Spacing.page)
                .padding(bottom = Spacing.section),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Text(
                stringResource(R.string.categories),
                style = PoruchType.brandTitle2,
                color = Poruch.colors.ink,
                modifier = Modifier.semantics { heading() })
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                verticalArrangement = Arrangement.spacedBy(Spacing.lg)
            ) {
                categories.forEach { key ->
                    CategoryTile(
                        key,
                        selected == key
                    ) { sheet.close { onSelect(if (selected == key) null else key) } }
                }
            }
            SecondaryButton(
                stringResource(R.string.all_categories),
                { sheet.close { onSelect(null) } },
                Modifier.fillMaxWidth()
            )
        }
    }
}

/** Рядок входу для гостя: порожній квиток вгорі — єдина головна дія, а вхід — для тих, хто вже має профіль, тож без картки й заливки. */
@Composable
private fun GuestLoginRow(onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.page)
            .minimumInteractiveComponentSize()
            .pressable(pressedScale = 1f) { onIntent(HomeIntent.OpenProfile) }
            .padding(horizontal = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        Icon(PoruchIcons.lock, null, Modifier.size(14.dp), tint = colors.inkSecondary)
        Text(
            stringResource(R.string.guest_home_slim),
            style = MaterialTheme.typography.labelMedium,
            color = colors.inkSecondary,
            modifier = Modifier.weight(1f)
        )
        Icon(PoruchIcons.chevronRight, null, Modifier.size(16.dp), tint = colors.inkSecondary)
    }
}

/** Ширина постера в рейці «Від людей»: як в одній колонці сітки, щоб третій визирав із-за краю. */
private val PeopleCardWidth = 176.dp

/**
 * «З ким піти»: зустрічі з вільним місцем і афіші, на які шукають компанію, однією рейкою квитків; останній квиток —
 * порожній «Організувати подію». Рейки нема — він на всю ширину: секція є завжди й каже, що свою можна зібрати. Гостю під
 * рейкою лише тихий рядок входу (без картки): дві картки поспіль товпились би.
 */
@Composable
private fun PeopleSection(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    Column(
        Modifier.padding(top = Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        SectionHeader(
            stringResource(R.string.home_with_whom), Modifier.padding(horizontal = Spacing.page),
            actionLabel = state.screen.openRooms.takeIf { it > 0 }
                ?.let { stringResource(R.string.home_all_count, it) },
            onAction = { onIntent(HomeIntent.ShowPeopleOnMap) }
        )
        // Одна рейка: спершу зустрічі з вільним місцем, далі афіші, на які хтось шукає компанію. Дві секції поруч про
        // одне питання плутали. Квитки однакової висоти — за найвищим: корінці стоять в одну лінію.
        if (state.screen.people.isNotEmpty() || state.screen.company.isNotEmpty()) Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = Spacing.page)
                .height(IntrinsicSize.Min),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
            verticalAlignment = Alignment.Top
        ) {
            state.screen.people.forEach { entry ->
                val id = entry.event.id
                UnfoldSource(id, "home_people", { onIntent(HomeIntent.OpenEvent(id, "home_people")) }) { source, open ->
                    PosterCard(
                        entry.event,
                        entry.source,
                        id in state.screen.savedIds,
                        id in state.screen.waitlistedIds,
                        { onIntent(HomeIntent.ToggleSaved(id)) },
                        Modifier
                            .width(PeopleCardWidth)
                            .fillMaxHeight()
                            .then(source),
                        showOrigin = false,
                        followName = entry.followName,
                        onClick = open
                    )
                }
            }
            state.screen.company.forEach { entry ->
                val id = entry.event.id
                val because = pluralStringResource(R.plurals.company_reason, entry.count, entry.count)
                UnfoldSource(id, "home_company", { onIntent(HomeIntent.OpenEvent(id, "home_company")) }) { source, open ->
                    PosterCard(
                        entry.event, FeedSource.CITY,
                        id in state.screen.savedIds, id in state.screen.waitlistedIds,
                        { onIntent(HomeIntent.ToggleSaved(id)) },
                        Modifier.width(PeopleCardWidth).fillMaxHeight().then(source),
                        because = because,
                        printedOnly = true,
                        onClick = open
                    )
                }
            }
            // Кінцем рейки, а не окремим блоком під нею: менше гортати до афіші (критика довжини 28.10).
            CreateCard(onIntent, Modifier.width(PeopleCardWidth).fillMaxHeight(), vertical = true)
        }
        val railless = state.screen.people.isEmpty() && state.screen.company.isEmpty()
        if (railless || !state.screen.signedIn) Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            if (railless) CreateCard(onIntent, Modifier.padding(horizontal = Spacing.page), vertical = false)
            if (!state.screen.signedIn) GuestLoginRow(onIntent)
        }
    }
}

@Composable
private fun CreateCard(onIntent: (HomeIntent) -> Unit, modifier: Modifier, vertical: Boolean) = CreateEventCard(
    stringResource(R.string.home_create_title), stringResource(R.string.home_create_subtitle),
    { onIntent(HomeIntent.CreateEvent("home_top")) }, modifier, vertical = vertical
)

/** Обкладинка-плитка блоку «Ваше». */
private val YourTile = 52.dp

/**
 * «Ваше»: усе особисте одним блоком у [HomeRules.YOURS_ROWS] рядки — найближчий план карткою з діями, решта планів,
 * «Ваш тиждень», дати артистів у місті й «Ви стежите». Кожен новий гачок дістає рядок тут, а не секцію над афішею. Гостю —
 * те, що в нього є без входу: стос і артисти на телефоні. Порожньо — блоку нема: створити подію пропонує рейка вище.
 */
@Composable
private fun PersonalSection(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val app = koinInject<PoruchApp>()
    val context = LocalContext.current
    val prompts = remember { context.getSharedPreferences(PROMPTS, Context.MODE_PRIVATE) }
    // «Ваш тиждень» — раз на тиждень, поки стос цього тижня не відкривали (docs/return-hooks.md).
    var opened by remember { mutableStateOf(prompts.getString(DECK_WEEK, null)) }
    // Відкритий стос переживає поворот: картки — зі стану головної, тут лише прапорець.
    var deckOpen by rememberSaveable { mutableStateOf(false) }
    val screen = state.screen
    val slots = screen.yours(opened != screen.deckWeek)
    if (deckOpen && screen.deck.isNotEmpty()) Dialog({ deckOpen = false }, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DeckScreen(app, screen.deck) { deckOpen = false }
    }
    if (slots.isEmpty) return
    val now = kotlin.time.Clock.System.now()
    val zoneId = ZoneId.systemDefault().id
    val personal = screen.personal.take(slots.plans)
    // Велика картка — першому плану, що скоро чи чекає на людину; минула чи далека подія лишається рядком.
    val lead = personal.firstOrNull { HomeRules.isLead(it.event, it.chat != null || it.requests > 0, now, zoneId) }
    val inset = Modifier.padding(start = Spacing.lg + YourTile + Spacing.md)
    val rows = buildList<@Composable () -> Unit> {
        personal.filter { it !== lead }.forEach { row -> add { PlanRow(row, onIntent) } }
        if (slots.waiting) add { WaitingRow(screen.moreWaiting, onIntent) }
        if (slots.deck) add {
            YourRow(
                null, stringResource(R.string.deck_title), stringResource(R.string.deck_row_subtitle),
                onClick = {
                    // Про сповіщення питає кінець стосу, а не перша закладка в ньому — як у стосі після онбордингу.
                    prompts.edit { putString(DECK_WEEK, screen.deckWeek); putBoolean(SAVE_ASKED, true) }
                    opened = screen.deckWeek
                    deckOpen = true
                },
                tile = { YourTileIcon(PoruchIcons.sparkle) }
            ) { Chevron() }
        }
        screen.radarDates.take(slots.dates).forEach { date -> add { DateRow(date, onIntent) } }
        if (slots.follows) add {
            FollowsRow(screen.followLine(slots.dates), screen.followed, screen.newFollowEvents, screen.followNames.isEmpty()) {
                onIntent(HomeIntent.OpenFollows)
            }
        }
    }
    Column(
        Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        SectionHeader(
            stringResource(R.string.home_yours),
            actionLabel = if (screen.personal.isEmpty()) null else stringResource(R.string.my_events),
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

@Composable
private fun Chevron() = Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = Poruch.colors.inkTertiary)

private val RADAR_DAY = java.time.format.DateTimeFormatter.ofPattern("EE d.MM", java.util.Locale.forLanguageTag("uk"))

/** Вечір «Ваших артистів» у місті (docs/artist-radar.md): дата, назва події, хто з артистів — усі, а не рядок на кожного. */
@Composable
private fun DateRow(date: RadarDate, onIntent: (HomeIntent) -> Unit) {
    val day = runCatching {
        java.time.OffsetDateTime.parse(date.event.startsAt).atZoneSameInstant(ZoneId.of(date.event.timeZone)).format(RADAR_DAY).uppercase()
    }.getOrNull()
    val id = date.event.eventId
    UnfoldSource(id, "radar", { onIntent(HomeIntent.OpenEvent(id, "radar")) }, bare = true) { source, open ->
        YourRow(
            day, date.event.displayTitle, date.artists.joinToString(", "),
            onClick = open,
            // Плитка кольору й гліфа жанру, як корінець квитка: три дати поспіль не зливаються в однакові рядки.
            tile = {
                Box(
                    Modifier.size(YourTile).clip(Radius.sm).background(categoryGradient(date.event.category)),
                    contentAlignment = Alignment.Center
                ) { Icon(categoryIcon(date.event.category), null, Modifier.size(24.dp), tint = categoryInk(date.event.category)) }
            },
            modifier = source,
            brandTitle = true
        ) { Chevron() }
    }
}

/** Гліф у плитці рядка «Ваше» (підписки, порожній стан, «чекають відповіді»). */
@Composable
private fun YourTileIcon(icon: ImageVector) {
    val colors = Poruch.colors
    Box(
        Modifier
            .size(YourTile)
            .background(colors.surfaceMuted, Radius.sm),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, null, Modifier.size(20.dp), tint = colors.ink)
    }
}

/** Ті, що чекають відповіді, але в «Ваше» не влізли: їх видно лише в «Моїх подіях». */
@Composable
private fun WaitingRow(count: Int, onIntent: (HomeIntent) -> Unit) {
    YourRow(
        overline = null,
        title = stringResource(R.string.home_waiting_more, count),
        subtitle = stringResource(R.string.home_waiting_more_hint),
        onClick = { onIntent(HomeIntent.OpenMyEvents) },
        tile = { YourTileIcon(PoruchIcons.chat) }
    ) {
        Icon(
            PoruchIcons.chevronRight,
            null,
            Modifier.size(18.dp),
            tint = Poruch.colors.inkTertiary
        )
    }
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
    brandTitle: Boolean = false,
    trailing: @Composable () -> Unit = {}
) {
    val colors = Poruch.colors
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier
                .weight(1f)
                .semantics(mergeDescendants = true) {}
                .pressable(pressedScale = 1f, onClick = onClick),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
            verticalAlignment = Alignment.CenterVertically
        ) {
            tile()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                overline?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.inkTertiary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Text(
                    title,
                    style = if (brandTitle) PoruchType.brandTitle3 else MaterialTheme.typography.titleSmall,
                    color = colors.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                subtitle?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            if (chat == null) trailing()
        }
        chat?.let { (count, open) ->
            val label = stringResource(R.string.home_chat_a11y, count)
            Box(
                Modifier
                    .minimumInteractiveComponentSize()
                    .clip(CircleShape)
                    .pressable(onClick = open)
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
        event.isCancelled -> stringResource(R.string.cancelled_short) to BadgeTone.Danger
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
        if (body.isBlank()) pluralStringResource(
            R.plurals.chat_unread_count,
            chat.unread,
            chat.unread
        )
        else stringResource(
            R.string.home_chat_preview,
            chat.lastAuthorName.ifBlank { stringResource(R.string.chat_member) },
            body
        )
    } ?: event.placeLabel
    UnfoldSource(event.id, "home_your", { onIntent(HomeIntent.OpenEvent(event.id, "home_your")) }, bare = true) { source, open ->
        YourRow(
            overline,
            event.cardTitle,
            subtitle,
            onClick = open,
            tile = { EventImage(event, Modifier
                .size(YourTile)
                .clip(Radius.sm), glyphSize = 24.dp) },
            modifier = source,
            // Лічильник — кнопка в чат, поки праворуч не зайняли запити: на них теж чекає людина, і вони важливіші.
            chat = row.chat?.takeIf { row.requests == 0 }
                ?.let { it.unread to { onIntent(HomeIntent.OpenChat(event.id)) } },
            brandTitle = true
        ) {
            when {
                event.isCancelled -> TicketStamp(
                    stringResource(R.string.cancelled_short),
                    BadgeTone.Danger
                )

                row.requests > 0 -> StatusBadge(
                    pluralStringResource(R.plurals.requests_count, row.requests, row.requests),
                    BadgeTone.Accent,
                    PoruchIcons.personAdd
                )

                role != null -> StatusBadge(role.first, role.second)
            }
        }
    }
}

/** Кнопка-пігулка картки плану. Підсвічена (чорнилом), коли за нею є що робити: нове в чаті, запити. */
@Composable
private fun PlanButton(
    text: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    highlight: Boolean = false,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val content = if (highlight) colors.onBrand else colors.ink
    Row(
        modifier
            .heightIn(min = 48.dp)
            .background(if (highlight) colors.brand else colors.brandContainer, ButtonShape)
            .clip(ButtonShape)
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, Modifier.size(16.dp), tint = content)
        Text(
            text,
            style = MaterialTheme.typography.labelMedium,
            color = content,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/**
 * Найближчий план великою карткою, як посадковий талон: відлік, назва, місце й дії — маршрут, чат, запити. Картка — квиток:
 * розгортається в деталі ([UnfoldSource]) і з голови, і з «Запити».
 */
@Composable
private fun NextPlanCard(row: PersonalRow, onIntent: (HomeIntent) -> Unit) =
    UnfoldSource(row.event.id, "home_next", { onIntent(HomeIntent.OpenEvent(row.event.id, "home_your")) }) { source, open ->
        NextPlanCard(row, source, open, onIntent)
    }

@Composable
private fun NextPlanCard(row: PersonalRow, modifier: Modifier, open: () -> Unit, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    val context = LocalContext.current
    val event = row.event
    // Відлік лише для сьогоднішнього: «через 25 год» про завтрашнє нічого не каже.
    val today = runCatching {
        java.time.Instant.parse(event.startsAt).atZone(ZoneId.systemDefault())
            .toLocalDate() == LocalDate.now()
    }.getOrDefault(false)
    val overline = if (today) countdownOverline(event) else cardOverline(event, dateWords())
    // Остання репліка чату, коли є нове; інакше моя роль і місце в один рядок: повна адреса живе в «Маршруті».
    val chat = row.chat
    val preview = chat?.takeIf { it.lastBody.isNotBlank() }?.let {
        stringResource(
            R.string.home_chat_preview,
            it.lastAuthorName.ifBlank { stringResource(R.string.chat_member) },
            it.lastBody.replace('\n', ' ')
        )
    }
    val role = stringResource(if (row.organizing) R.string.home_role_organizer else R.string.going)
    val subtitle =
        preview ?: listOf(role, event.placeLabel).filter { it.isNotBlank() }.joinToString(" · ")
    Column(
        modifier
            .fillMaxWidth()
            .cardSurface(Radius.xl)
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .semantics(mergeDescendants = true) {}
                .pressable(pressedScale = 1f, onClick = open),
            horizontalArrangement = Arrangement.spacedBy(Spacing.lg),
            verticalAlignment = Alignment.Top
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(
                    overline,
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.accentText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    event.cardTitle,
                    style = PoruchType.brandTitle2,
                    color = colors.ink,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.inkSecondary,
                    maxLines = if (preview == null) 1 else 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
            EventImage(event, Modifier
                .size(88.dp)
                .clip(Radius.md), glyphSize = 30.dp)
        }
        val buttons = @Composable { width: Modifier ->
            // Маршрут — головна дія, поки подія сьогодні й ще не почалась; далі — звичайна.
            PlanButton(
                stringResource(R.string.open_in_maps), PoruchIcons.directions, width,
                highlight = today && !event.hasStarted(kotlin.time.Clock.System.now())
            ) { context.openInMaps(event) }
            PlanButton(
                if (chat != null) stringResource(
                    R.string.chat_short_unread,
                    chat.unread
                ) else stringResource(R.string.chat_short),
                PoruchIcons.chat, width, highlight = chat != null
            ) { onIntent(HomeIntent.OpenChat(event.id)) }
            if (row.requests > 0) PlanButton(
                stringResource(R.string.home_requests_short, row.requests),
                PoruchIcons.personAdd,
                width,
                highlight = true,
                onClick = open
            )
        }
        // Великий шрифт: дії одна під одною, як у «Моїх подіях», — три в ряд обрізали б «Маршрут» до «Ма…».
        if (LocalDensity.current.fontScale >= 1.3f) Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            buttons(Modifier.fillMaxWidth())
        } else Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) { buttons(Modifier.weight(1f)) }
    }
}

/**
 * «Ви стежите» і за ким — двома першими іменами, як і веде тап: на екран «Ви стежите». Спершу артисти дат, що не влізли
 * вище, далі заклади й організатори. Імен нема (список не доїхав) — назва події.
 */
@Composable
private fun FollowsRow(names: List<String>, events: List<Event>, new: Int, artistsOnly: Boolean, onClick: () -> Unit) {
    val colors = Poruch.colors
    // Лише артисти дат, що не влізли: одне ім'я й «та ще 5 артистів» — число не читається подіями й влазить у рядок.
    val lead = if (artistsOnly) 1 else 2
    val shown =
        if (names.isEmpty()) events.firstOrNull()?.displayTitle.orEmpty() else names.take(lead).joinToString(", ")
    YourRow(
        overline = null, title = stringResource(R.string.follows_title),
        subtitle = when {
            names.size <= lead -> shown
            artistsOnly -> "$shown " + pluralStringResource(R.plurals.home_follows_more_artists, names.size - lead, names.size - lead)
            else -> stringResource(R.string.home_follows_more, shown, names.size - lead)
        },
        onClick = onClick,
        tile = { YourTileIcon(PoruchIcons.bellActive) }
    ) {
        // Нове ще не переглянуте — бейдж замість шеврона: рядок тепер про те, що чекає.
        if (new > 0) StatusBadge(
            pluralStringResource(R.plurals.follows_new, new, new),
            BadgeTone.Accent
        )
        else Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
    }
}

/** Підпис джерела в стрічці: «Для вас», «Ви стежите · МУР». Афіша міста без підпису. */
@Composable
private fun lane(source: FeedSource, followName: String?): String? = when (source) {
    FeedSource.FOR_YOU -> stringResource(R.string.picked_for_you)
    FeedSource.FOLLOWING -> followName?.let { stringResource(R.string.follow_via, it) }
        ?: stringResource(R.string.following)

    FeedSource.CITY -> null
}

/** «У місті»: великі картки, що гортаються (сусідня визирає), чипи, далі сітка постерів у дві колонки. */
private const val FEED_CHIPS = "feed-chips"

private fun LazyListScope.cityFeed(state: HomeState, onIntent: (HomeIntent) -> Unit, columns: Int, chipsStuck: Boolean) {
    when {
        state.screen.feed.isNotEmpty() -> {
            val picks = state.screen.feed.take(HomeRules.HERO_COUNT)
            val rest = state.screen.feed.drop(HomeRules.HERO_COUNT)
            item(key = "city") {
                Column(
                    Modifier.padding(top = Spacing.xxl),
                    verticalArrangement = Arrangement.spacedBy(Spacing.md)
                ) {
                    if (state.screen.offline) OfflineNote(Modifier.padding(horizontal = Spacing.page))
                    SectionHeader(
                        stringResource(R.string.home_in_city),
                        Modifier.padding(horizontal = Spacing.page),
                        actionLabel = state.screen.totalFound.takeIf { it > 0 }
                            ?.let { stringResource(R.string.home_all_count, it) },
                        onAction = { onIntent(HomeIntent.ShowEverythingOnMap) }
                    )
                    HeroPager(picks, state.screen.savedIds, onIntent)
                }
            }
            // Чипи «Сьогодні / Вихідні» під рукою, поки гортається сітка: п'ятничний вибір не за два екрани вгору.
            if (state.screen.chips.isNotEmpty()) stickyHeader(key = FEED_CHIPS) {
                Box(Modifier.fillMaxWidth().background(Poruch.colors.canvas).padding(top = Spacing.md, bottom = Spacing.sm)) {
                    FeedChips(state, onIntent)
                    if (chipsStuck) HairLine(Modifier.align(Alignment.BottomCenter).offset(y = Spacing.sm))
                }
            }
            val rows = rest.take(state.feedLimit).chunked(columns)
            itemsIndexed(rows, key = { _, pair -> pair.first().event.id }, contentType = { _, _ -> "poster-row" }) { index, pair ->
                // Ряд квитків однакової висоти: корінці сусідів на одній лінії.
                Row(
                    Modifier
                        .padding(horizontal = Spacing.page)
                        .padding(top = if (index == 0 && state.screen.chips.isEmpty()) Spacing.xxl else Spacing.xl)
                        .height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                ) {
                    pair.forEach { entry ->
                        val id = entry.event.id
                        UnfoldSource(id, "home_poster", { onIntent(HomeIntent.OpenEvent(id, "home_poster")) }) { source, open ->
                            PosterCard(
                                entry.event,
                                entry.source,
                                id in state.screen.savedIds,
                                id in state.screen.waitlistedIds,
                                { onIntent(HomeIntent.ToggleSaved(id)) },
                                Modifier
                                    .weight(1f)
                                    .fillMaxHeight()
                                    .then(source),
                                followName = entry.followName,
                                onClick = open
                            )
                        }
                    }
                    repeat(columns - pair.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            if (rest.size > state.feedLimit) item(key = "more-feed") {
                SecondaryButton(
                    stringResource(R.string.show_more), { onIntent(HomeIntent.ShowMoreFeed) },
                    Modifier
                        .padding(horizontal = Spacing.page)
                        .padding(top = Spacing.xl)
                        .fillMaxWidth()
                )
            }
        }

        // Стрічка ще їде: лоадер і тоді, коли вище вже є плани чи «З ким піти», — інакше «У місті» просто нема.
        state.screen.loading -> item(key = "loading") {
            Box(
                Modifier
                    .fillMaxWidth()
                    .padding(Spacing.section),
                contentAlignment = Alignment.Center
            ) { PoruchLoader() }
        }
        // Без мережі «тихо» було б неправдою: афіша є, її не видно. Відкриється сама, щойно мережа повернеться.
        state.screen.offline -> item(key = "offline") {
            Box(Modifier.padding(top = Spacing.xxl)) {
                OfflineState(stringResource(R.string.offline_home_hint))
            }
        }

        state.screen.isEmpty -> item(key = "empty") {
            Box(Modifier.padding(top = Spacing.xxl)) {
                EmptyState(
                    PoruchIcons.compass,
                    stringResource(R.string.nothing_here),
                    stringResource(R.string.nothing_here_hint),
                    actionLabel = stringResource(R.string.find_on_map),
                    onAction = { onIntent(HomeIntent.OpenMap) }
                )
            }
        }
    }
}

/** Ряд чипів над сіткою: час, безкоштовне й найбільші категорії. Звужує лише сітку, великі картки стоять. */
@Composable
private fun FeedChips(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    Row(
        Modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = Spacing.page),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        state.screen.chips.forEach { chip ->
            PoruchChip(
                feedChipLabel(chip),
                chip == state.screen.feedFilter,
                { onIntent(HomeIntent.SelectFeedFilter(chip)) },
                dot = chip.category
            )
        }
    }
}

@Composable
private fun feedChipLabel(chip: FeedFilter): String = when (chip.kind) {
    FeedFilterKind.TODAY -> stringResource(R.string.today)
    FeedFilterKind.TOMORROW -> stringResource(R.string.tomorrow)
    FeedFilterKind.WEEKEND -> stringResource(R.string.weekend)
    FeedFilterKind.FREE -> stringResource(R.string.listing_free)
    FeedFilterKind.CATEGORY -> chip.category?.let { stringResource(categoryLabel(it)) }
        ?: stringResource(R.string.feed_all)

    FeedFilterKind.ALL -> stringResource(R.string.feed_all)
}

/** Гортана стрічка великих карток: наступна визирає з-за краю, як у Moonly. */
@Composable
private fun HeroPager(
    picks: List<FeedEntry>,
    savedIds: List<String>,
    onIntent: (HomeIntent) -> Unit
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val pageWidth = if (picks.size > 1) maxWidth * 0.86f else maxWidth - Spacing.page * 2
        HorizontalPager(
            rememberPagerState { picks.size },
            contentPadding = PaddingValues(horizontal = Spacing.page),
            pageSpacing = Spacing.md,
            pageSize = PageSize.Fixed(pageWidth)
        ) { index ->
            val entry = picks[index]
            val id = entry.event.id
            val eyebrow = lane(entry.source, entry.followName)
            UnfoldSource(id, "home_hero", { onIntent(HomeIntent.OpenEvent(id, "home_hero")) }) { source, open ->
                EventHeroCard(
                    entry.event,
                    source,
                    eyebrow = eyebrow,
                    saved = id in savedIds,
                    onSave = { onIntent(HomeIntent.ToggleSaved(id)) },
                    onClick = open
                )
            }
        }
    }
}

/**
 * Вертикальний квиток у сітці «У місті» й рейці «Від людей»: обкладинка 4:5 і назва вгорі, а за перфорацією корінець
 * кольору жанру з годиною, днем і, для зустрічі, місцями «3/8». Ціна — плашкою на фото, стан кімнати («Ви йдете»,
 * «Лишилось 2») — штампом нагорі замість підпису «Для вас».
 */
@Composable
private fun PosterCard(
    // Подія й джерело окремо, а не `FeedEntry`: обгортка нова на кожну згортку стану, а екземпляр події
    // спільний стор зберігає — картка пропускає перескладання, поки не змінилась сама подія чи її стан.
    event: Event,
    source: FeedSource,
    saved: Boolean,
    waitlisted: Boolean,
    onSave: () -> Unit,
    modifier: Modifier = Modifier,
    /** Підпис «Від людей» на кімнаті без стану: у секції «Від людей» він зайвий. */
    showOrigin: Boolean = true,
    /** За ким саме подія з підписок: ім'я на штампі з дзвіночком. */
    followName: String? = null,
    /** Причина від рейки, а не від джерела: «2 хочуть піти з компанією». */
    because: String? = null,
    /** Друкований квиток без фото й з афіші: у рейці «З ким піти» всі квитки однієї висоти, без порожнього поля. */
    printedOnly: Boolean = false,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    // Скасоване — штампом (корінець тоді погашений); для кімнати — «Ви йдете», «Лишилось 2». Знята афіша сказана підписом.
    val state =
        if (event.gathering == null && !event.isCancelled) null else eventState(event, waitlisted)
    // Чому квиток у стрічці: за ким стежите (дзвіночок і ім'я), «Для вас», «Від людей». Не штамп, бо нічого з квитком
    // не сталось — штамп поруч зі «Скасовано» й «Лишилось 2» мав би однакову вагу.
    val laneLabel = lane(source, followName)
    val reason: Pair<String, ImageVector>? = when {
        because != null -> because to PoruchIcons.social
        source == FeedSource.FOLLOWING -> (followName
            ?: stringResource(R.string.following)) to PoruchIcons.bellActive

        laneLabel != null -> laneLabel to PoruchIcons.sparkle
        showOrigin && event.gathering != null -> stringResource(R.string.from_people) to PoruchIcons.social
        else -> null
    }
    // «Від 390 ₴» лише коли джерело сказало ціну. Місця зустрічі — на корінці.
    val price =
        event.listing?.takeIf { event.gathering == null && (it.isFree == true || it.priceMin != null) }
            ?.let { listingPrice(it) }
    // Афіша завжди підписана джерелом (docs/event-ingestion.md §8).
    val note: Pair<String, Color>? = event.listing?.let {
        ((if (it.isWithdrawn) listingStamp(it)?.first else null)
            ?: stringResource(R.string.listing_badge, it.sellerNames)) to colors.inkTertiary
    }
    val words = dateWords()
    val series = remember(event, words) { seriesNote(event, words) }
    // Штамп — лише стан квитка.
    val stamp: Triple<String, BadgeTone, ImageVector?>? =
        state?.let { Triple(it.first, it.second, null) }
    val printed = printedOnly || event.imageUrl == null
    // Друкована сторона без фото дає назві чотири рядки; з великим текстом — на рядок більше, щоб назва не тонула в «…».
    val titleLines = (if (printed) 4 else 2) + if (LocalDensity.current.fontScale >= 1.3f) 1 else 0
    Ticket(
        ticketStub(event), stub = { StubTime(event, row = true) },
        modifier = modifier
            .ticketSemantics(
                ticketA11yLabel(
                    event,
                    listOfNotNull(
                        stamp?.first,
                        reason?.first,
                        price,
                        note?.first
                    ).joinToString(", ")
                ), onClick, saved, onSave
            ),
        vertical = true, onClick = onClick,
        // 64: жанр над часом — два рядки, і в 52 вони впирались у перфорацію та нижній край.
        stubLength = 64.dp
    ) {
        Column(Modifier.fillMaxHeight()) {
            if (!printed) Box(Modifier
                .fillMaxWidth()
                .aspectRatio(4f / 5f)
                .clipToBounds()) {
                EventArt(event, Modifier.fillMaxSize(), glyph = 130.dp)
                // Штамп не заходить під «Зберегти»: довге ім'я з підписок стискається трьома крапками.
                stamp?.let { (text, tone, icon) ->
                    TicketStamp(
                        text, tone, icon, onFill = true,
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(start = Spacing.sm, top = Spacing.sm, end = 52.dp)
                    )
                }
                SaveButton(saved, onSave, Modifier
                    .align(Alignment.TopEnd)
                    .padding(Spacing.xs))
                price?.let {
                    Box(
                        Modifier
                            .align(Alignment.BottomStart)
                            .padding(Spacing.sm)
                    ) { StatusBadge(it) }
                }
            } else Row(
                Modifier
                    .fillMaxWidth()
                    .padding(start = Spacing.sm, end = Spacing.sm, top = Spacing.sm),
                verticalAlignment = Alignment.Top
            ) {
                // Без фото — друкована сторона квитка: штамп і «Зберегти» вгорі, назва великим кеглем.
                Box(
                    Modifier
                        .weight(1f)
                        .padding(top = Spacing.xs)
                ) { stamp?.let { (text, tone, icon) -> TicketStamp(text, tone, icon) } }
                SaveButton(saved, onSave)
            }
            // Як на друкованому квитку: місце й підписи притиснуті до перфорації, вільне поле лишається під назвою.
            // Вага лише в розпірки: фото бере свої 4:5 першим.
            Column(
                Modifier
                    .weight(1f)
                    .padding(horizontal = Spacing.md)
                    .padding(top = Spacing.md, bottom = Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(Spacing.xs)
            ) {
                Text(
                    event.cardTitle,
                    style = if (printed) PoruchType.brandTitle2 else PoruchType.brandTitle3,
                    color = colors.ink,
                    maxLines = titleLines,
                    overflow = TextOverflow.Ellipsis
                )
                HostLine(event)
                Spacer(Modifier.weight(1f))
                reason?.let { (text, icon) -> ReasonLine(text, icon) }
                EventDescriptor(event, placeFirst = true)
                if (printed) price?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                series?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                note?.let { (text, color) ->
                    Text(
                        text,
                        style = MaterialTheme.typography.labelSmall,
                        color = color,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

/** Куди далі, коли стрічку переглянуто: мапа з усім, що є, і створення власної події. */
@Composable
private fun MoreRows(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    Column(
        Modifier
            .padding(horizontal = Spacing.page)
            .padding(top = Spacing.xxl),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        SectionHeader(stringResource(R.string.home_next))
        GroupedRows {
            LinkRow(
                PoruchIcons.map,
                stringResource(R.string.all_events_section),
                stringResource(R.string.all_events_hint),
                { onIntent(HomeIntent.ShowEverythingOnMap) },
                value = state.screen.totalFound.takeIf { it > 0 }?.toString()
            )
            HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
            LinkRow(
                PoruchIcons.sparkle,
                stringResource(R.string.create_banner_title),
                stringResource(R.string.create_banner_subtitle),
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
            onClick = {
                onIntent(
                    HomeIntent.SwitchCity(
                        CityResult(
                            city.city,
                            city.latitude,
                            city.longitude
                        )
                    )
                )
            },
            modifier = Modifier.padding(horizontal = Spacing.page), icon = PoruchIcons.pin
        )
    }
    when {
        state.screen.isEmpty && state.screen.busy -> Box(
            Modifier
                .fillMaxWidth()
                .padding(Spacing.section), contentAlignment = Alignment.Center
        ) { PoruchLoader() }
        // У місті порожньо — найближчий крок розширити область, а не йти на мапу.
        state.screen.isEmpty && !state.screen.searchEverywhere -> EmptyState(
            PoruchIcons.search,
            stringResource(R.string.nothing_found),
            stringResource(R.string.nothing_found_city_hint, state.screen.cityName),
            actionLabel = stringResource(R.string.search_everywhere),
            onAction = { onIntent(HomeIntent.SearchEverywhere(true)) }
        )
        // Усюди без кнопки: мапа шукає лише в місті, тож розширювати вже нікуди.
        state.screen.isEmpty -> EmptyState(
            PoruchIcons.search,
            stringResource(R.string.nothing_found),
            stringResource(R.string.nothing_found_hint)
        )

        else -> Column(
            Modifier
                .padding(horizontal = Spacing.page)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(Spacing.xl)
        ) {
            // Район — першим, як на мапі: це рядок-два, і «Київський» найчастіше саме про нього.
            val (localities, adminDistricts) = state.screen.districts.partition { it.district.isLocality }
            if (adminDistricts.isNotEmpty()) DistrictsGroup(adminDistricts) {
                onIntent(
                    HomeIntent.OpenDistrict(
                        it
                    )
                )
            }
            if (localities.isNotEmpty()) DistrictsGroup(
                localities,
                title = stringResource(R.string.search_localities_group)
            ) {
                onIntent(HomeIntent.OpenDistrict(it))
            }
            // Події, під ними — заклади з тим самим словом. Групові списки: видача пошуку — перелік, а не стрічка.
            if (state.screen.results.isNotEmpty()) Column(
                verticalArrangement = Arrangement.spacedBy(
                    Spacing.sm
                )
            ) {
                GroupLabel(
                    stringResource(
                        R.string.search_events_group,
                        maxOf(state.screen.resultsTotal, state.screen.results.size)
                    ),
                    // Мапа шукає в межах міста, тож для «усюди» вона показала б інше.
                    actionLabel = if (state.screen.searchEverywhere) null else stringResource(R.string.on_map),
                    onAction = { onIntent(HomeIntent.ShowResultsOnMap) }
                )
                GroupedRows {
                    state.screen.results.take(state.resultsLimit)
                        .forEachIndexed { position, event ->
                            if (position > 0) HairLine(Modifier.padding(start = ResultRowInset))
                            UnfoldSource(event.id, "home_search", { onIntent(HomeIntent.OpenEvent(event.id, "home_search")) }, bare = true) { source, open ->
                                EventResultRow(
                                    event, source,
                                    waitlisted = event.id in state.screen.waitlistedIds,
                                    withCity = state.screen.searchEverywhere,
                                    onClick = open
                                )
                            }
                        }
                }
                if (state.screen.resultsIndexed > state.resultsLimit) SecondaryButton(
                    stringResource(R.string.show_more),
                    { onIntent(HomeIntent.ShowMoreResults) },
                    Modifier.fillMaxWidth()
                )
            }
            if (state.screen.places.isNotEmpty()) PlacesGroup(
                state.screen.places,
                state.screen.searchEverywhere
            ) { onIntent(HomeIntent.OpenPlace(it)) }
            if (state.screen.artists.isNotEmpty()) ArtistsGroup(state.screen.artists) {
                onIntent(
                    HomeIntent.OpenArtist(it)
                )
            }
        }
    }
}

/** Повторний тап «Головна» в таббарі (`MainActivity`): головна гортає вгору. */
object HomeScrollToTop {
    private val flow = kotlinx.coroutines.flow.MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val requests: kotlinx.coroutines.flow.Flow<Unit> = flow
    fun request() { flow.tryEmit(Unit) }
}
