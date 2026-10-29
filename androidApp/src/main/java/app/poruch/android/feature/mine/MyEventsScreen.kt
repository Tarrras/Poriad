package app.poruch.android.feature.mine

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.feature.wallet.TicketsSection
import app.poruch.android.feature.detail.RatingSheet
import app.poruch.android.platform.openInMaps
import app.poruch.android.platform.shareEvent
import app.poruch.android.ui.*
import app.poruch.domain.Event
import app.poruch.domain.EventRating
import app.poruch.domain.FollowRules
import app.poruch.domain.JoinRequest
import app.poruch.domain.MyEventsGroup
import app.poruch.domain.MyEventsRules
import app.poruch.domain.MyEventsSection
import app.poruch.domain.MyEventsTab
import app.poruch.domain.RatingRules
import kotlin.time.Clock

@Composable
fun MyEventsScreen(state: MyEventsState, onIntent: (MyEventsIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.canvas)
    ) {
        Column(
            Modifier
                .statusBarsPadding()
                .padding(top = Spacing.xl, bottom = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Column(
                Modifier.padding(horizontal = Spacing.page),
                verticalArrangement = Arrangement.spacedBy(Spacing.xs)
            ) {
                Text(
                    stringResource(R.string.my_events),
                    style = PoruchType.brandDisplay,
                    color = colors.ink
                )
                // Гостю підзаголовка нема: те саме каже порожній стан нижче.
                if (state.screen.signedIn) Text(
                    subtitle(state), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary
                )
            }
            // Гортаються: на великому шрифті три чипи не вміщались і обрізались.
            if (state.screen.signedIn) Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                MyEventsTab.entries.forEach { tab ->
                    PoruchChip(
                        stringResource(tab.label),
                        state.tab == tab,
                        { onIntent(MyEventsIntent.PickTab(tab)) },
                        badge = when (tab) {
                            MyEventsTab.GOING -> state.screen.board.goingBadge
                            MyEventsTab.ORGANIZING -> state.screen.board.organizingBadge
                            MyEventsTab.SAVED -> 0
                        }
                    )
                }
            }
        }
        // Квитки з телефона (docs/ticket-wallet.md) — там, де «йду»: у «Іду», а в гостя, у якого розріз один, — у ньому.
        val showsTickets = !state.screen.signedIn || state.tab == MyEventsTab.GOING
        if (!state.screen.signedIn && state.screen.board.savedAhead == 0) Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            TicketsSection(state.screen.tickets, state.screen.pastTickets, Modifier.padding(horizontal = Spacing.page, vertical = Spacing.md))
            EmptyState(
                PoruchIcons.ticket,
                stringResource(R.string.guest_empty),
                stringResource(R.string.guest_saved_hint),
                Modifier.padding(top = Spacing.section),
                stringResource(R.string.login),
                { onIntent(MyEventsIntent.SignIn) }
            )
        } else PullToRefresh(
            state.refreshing,
            { onIntent(MyEventsIntent.Refresh) },
            Modifier.fillMaxSize()
        ) {
            val sections = state.screen.board.sections(state.tab)
            // Порожній стан теж прокручується: інакше потяг не має за що зачепитись.
            if (sections.isEmpty()) Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
            ) {
                if (showsTickets) TicketsSection(state.screen.tickets, state.screen.pastTickets, Modifier.padding(horizontal = Spacing.page, vertical = Spacing.md))
                // Плану на телефоні ще нема, а мережі нема: «нічого не заплановано» було б неправдою.
                if (state.screen.offline && state.screen.myEvents.isEmpty()) OfflineState(
                    stringResource(R.string.offline_mine_hint),
                    actionLabel = stringResource(R.string.try_again), onAction = { onIntent(MyEventsIntent.Refresh) }
                )
                else if (state.screen.loading) Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(Spacing.section),
                    contentAlignment = Alignment.Center
                ) { PoruchLoader() }
                else Empty(state.tab, onIntent)
            } else {
                // Лінивий стовпець по секціях: зміна однієї (нове в чаті, запит) не перескладає решту.
                val bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + TabBarClearance
                LazyColumn(
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = Spacing.page, end = Spacing.page, top = Spacing.sm, bottom = bottom),
                    verticalArrangement = Arrangement.spacedBy(Spacing.xxl)
                ) {
                    val nothingAhead = state.screen.board.nothingAhead(state.tab)
                    if (state.screen.offline) item(key = "offline") { OfflineNote() }
                    if (!state.screen.signedIn) item(key = "guest") { GuestNote { onIntent(MyEventsIntent.SignIn) } }
                    if (showsTickets) item(key = "tickets") { TicketsSection(state.screen.tickets, state.screen.pastTickets) }
                    // Попереду нічого, а минулі є: першою йде дія, а не три сірі минулі.
                    if (nothingAhead) item(key = "ahead") { AheadCard(state.tab, onIntent) }
                    items(sections, key = { it.group.name }) { Section(it, state, onIntent) }
                    // Те саме, що порожній квиток на головній: свою зустріч друкуєш сам.
                    if (state.tab == MyEventsTab.ORGANIZING && !nothingAhead) item(key = "create") {
                        CreateEventCard(
                            stringResource(R.string.home_create_title),
                            stringResource(R.string.create_banner_subtitle),
                            { onIntent(MyEventsIntent.CreateEvent) }
                        )
                    }
                }
            }
        }
    }
    state.rating?.let { event ->
        val mine = state.screen.myRatings[event.id]?.let { EventRating(it, null, "", true) }
        // Оцінюють лише те, куди ходили: організатор тут завжди хтось інший.
        val follow = event.organizerId?.let { FollowRules.followOnRating(it in state.screen.followedOrganizers, mine != null) }
        RatingSheet(
            event,
            mine,
            state.screen.mutating,
            follow,
            { onIntent(MyEventsIntent.DismissRating) }) { score, comment, tags, following ->
            onIntent(MyEventsIntent.Rate(event.id, score, comment, tags, following))
        }
    }
}

/** Закладки гостя живуть лише на телефоні: чесно кажемо, навіщо входити. */
@Composable
private fun GuestNote(onSignIn: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onSignIn),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            stringResource(R.string.guest_saved_note), Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium, color = Poruch.colors.inkSecondary
        )
        Text(stringResource(R.string.login), style = MaterialTheme.typography.labelLarge, color = Poruch.colors.ink)
    }
}

private val MyEventsTab.label: Int
    get() = when (this) {
        MyEventsTab.GOING -> R.string.tab_going
        MyEventsTab.ORGANIZING -> R.string.organizing
        MyEventsTab.SAVED -> R.string.saved
    }

/** Лічильники замість опису. Нуль — частину не показуємо; усе нуль — загальний підпис. */
@Composable
private fun subtitle(state: MyEventsState): String {
    val b = state.screen.board
    val parts = buildList {
        when (state.tab) {
            MyEventsTab.GOING -> {
                if (b.goingAhead > 0) add(
                    pluralStringResource(
                        R.plurals.going_ahead,
                        b.goingAhead,
                        b.goingAhead
                    )
                )
                if (b.awaiting > 0) add(
                    pluralStringResource(
                        R.plurals.awaiting_reply,
                        b.awaiting,
                        b.awaiting
                    )
                )
            }

            MyEventsTab.ORGANIZING -> {
                if (b.organizingAhead > 0) add(
                    pluralStringResource(
                        R.plurals.organizing_ahead,
                        b.organizingAhead,
                        b.organizingAhead
                    )
                )
                if (b.requests > 0) add(
                    pluralStringResource(
                        R.plurals.join_requests,
                        b.requests,
                        b.requests
                    )
                )
            }

            MyEventsTab.SAVED -> {
                if (b.savedAhead > 0) add(
                    pluralStringResource(
                        R.plurals.saved_ahead,
                        b.savedAhead,
                        b.savedAhead
                    )
                )
                if (b.savedThisWeek > 0) add(
                    stringResource(
                        R.string.saved_this_week,
                        b.savedThisWeek
                    )
                )
            }
        }
    }
    return if (parts.isEmpty()) stringResource(R.string.my_events_subtitle) else parts.joinToString(
        " · "
    )
}

/** Порожній квиток з першою дією розрізу, над минулими. */
@Composable
private fun AheadCard(tab: MyEventsTab, onIntent: (MyEventsIntent) -> Unit) {
    if (tab == MyEventsTab.ORGANIZING) CreateEventCard(
        stringResource(R.string.home_create_title),
        stringResource(R.string.home_create_subtitle),
        { onIntent(MyEventsIntent.CreateEvent) }
    ) else CreateEventCard(
        stringResource(R.string.going_nothing_ahead_title),
        stringResource(R.string.going_nothing_ahead_text),
        { onIntent(MyEventsIntent.FindNearby) },
        icon = PoruchIcons.map
    )
}

@Composable
private fun Empty(tab: MyEventsTab, onIntent: (MyEventsIntent) -> Unit) {
    val modifier = Modifier.padding(top = Spacing.section)
    when (tab) {
        MyEventsTab.GOING -> EmptyState(
            PoruchIcons.calendar,
            stringResource(R.string.going_empty_title),
            stringResource(R.string.going_empty_text),
            modifier,
            stringResource(R.string.find_nearby),
            { onIntent(MyEventsIntent.FindNearby) }
        )

        MyEventsTab.ORGANIZING -> EmptyState(
            PoruchIcons.sparkle,
            stringResource(R.string.organizing_empty_title),
            stringResource(R.string.organizing_empty_text),
            modifier,
            stringResource(R.string.create),
            { onIntent(MyEventsIntent.CreateEvent) }
        )

        MyEventsTab.SAVED -> EmptyState(
            PoruchIcons.bookmark,
            stringResource(R.string.saved_empty_title),
            stringResource(R.string.saved_empty_text),
            modifier,
            stringResource(R.string.find_nearby),
            { onIntent(MyEventsIntent.FindNearby) }
        )
    }
}

@Composable
private fun Section(
    section: MyEventsSection,
    state: MyEventsState,
    onIntent: (MyEventsIntent) -> Unit
) {
    val events = section.events
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        when (section.group) {
            MyEventsGroup.TODAY -> {
                // Перша сьогоднішня — картка з маршрутом і чатом, решта — рядками.
                Overline(R.string.section_today)
                GoingHero(events.first(), state.screen.unread[events.first().id] ?: 0, onIntent)
                Rows(events.drop(1), state, onIntent)
            }

            MyEventsGroup.UPCOMING -> if (state.tab == MyEventsTab.ORGANIZING) {
                Overline(R.string.section_nearest)
                val first = events.first()
                val declining = state.declining
                OrganizerPanel(
                    first,
                    state.screen.unread[first.id] ?: 0,
                    state.screen.requests.filter {
                        it.eventId == first.id && !(declining?.eventId == it.eventId && declining.userId == it.userId)
                    },
                    declining?.takeIf { it.eventId == first.id },
                    state.screen.mutating,
                    onIntent
                )
                if (events.size > 1) {
                    Overline(R.string.section_next, Modifier.padding(top = Spacing.lg))
                    Rows(events.drop(1), state, onIntent)
                }
            } else {
                Overline(R.string.section_next)
                Rows(events, state, onIntent)
            }

            MyEventsGroup.PAST -> {
                val shown = if (state.allPast) events else events.take(MyEventsRules.PAST_PREVIEW)
                Overline(R.string.section_past)
                Rows(shown, state, onIntent)
                if (events.size > shown.size) GhostButton(
                    stringResource(R.string.show_all_past, events.size),
                    { onIntent(MyEventsIntent.ShowAllPast) }
                )
            }

            MyEventsGroup.THIS_WEEK -> {
                Overline(R.string.section_this_week)
                Rows(events, state, onIntent)
            }

            MyEventsGroup.LATER -> {
                Overline(R.string.section_later)
                Rows(events, state, onIntent)
            }
        }
    }
}

@Composable
private fun Overline(text: Int, modifier: Modifier = Modifier) = Text(
    stringResource(text).uppercase(),
    modifier,
    style = MaterialTheme.typography.labelSmall,
    color = Poruch.colors.inkTertiary
)

@Composable
private fun Rows(events: List<Event>, state: MyEventsState, onIntent: (MyEventsIntent) -> Unit) {
    if (events.isEmpty()) return
    val now = Clock.System.now()
    // На великому шрифті «Оцінити» стає під рядок: поруч вона лишала назві кілька літер.
    val stacked = LocalDensity.current.fontScale > STACK_FONT_SCALE
    GroupedRows {
        events.forEachIndexed { index, event ->
            val score = state.screen.myRatings[event.id]
            val rate =
                state.tab == MyEventsTab.GOING && score == null && RatingRules.canRate(event, now)
            // Запит до не найближчої події інакше видно лише в бейджі чипа.
            val asks =
                if (state.tab == MyEventsTab.ORGANIZING) state.screen.requests.count { it.eventId == event.id } else 0
            val note = score?.let { stringResource(R.string.my_score, it) }
            val status = if (asks > 0) pluralStringResource(R.plurals.join_requests, asks, asks) to BadgeTone.Accent else null
            UnfoldSource(event.id, "mine", { onIntent(MyEventsIntent.OpenEvent(event.id)) }, bare = true) { source, open ->
                EventRow(
                    event,
                    source,
                    unread = state.screen.unread[event.id] ?: 0,
                    waitlisted = event.id in state.screen.waitlistedIds,
                    note = note,
                    trailing = when {
                        // Своя дія рядка: «Оцінити» для минулої, закладка — у збережених.
                        rate && !stacked -> {
                            {
                                RateButton { onIntent(MyEventsIntent.StartRating(event)) }
                            }
                        }

                        state.tab == MyEventsTab.SAVED -> {
                            { SaveButton(true, { onIntent(MyEventsIntent.Unsave(event.id)) }) }
                        }

                        else -> null
                    },
                    status = status,
                    onClick = open
                )
            }
            if (rate && stacked) Box(Modifier.padding(start = Spacing.lg, bottom = Spacing.md)) {
                RateButton { onIntent(MyEventsIntent.StartRating(event)) }
            }
            if (index < events.lastIndex) HairLine(Modifier.padding(start = Spacing.lg + 60.dp + Spacing.md))
        }
    }
}

/**
 * «Оцінити» в рядку минулої. Тонова, а не чорнильна: три головні кнопки підряд сперечались за увагу. Без гліфа: з ним
 * кнопка забирала місце в назви й адреси.
 */
@Composable
private fun RateButton(onClick: () -> Unit) {
    val colors = Poruch.colors
    Text(
        stringResource(R.string.rate_action),
        style = MaterialTheme.typography.labelLarge,
        color = colors.ink,
        maxLines = 1,
        modifier = Modifier
            .minimumInteractiveComponentSize()
            .heightIn(min = 36.dp)
            .background(colors.brandContainer, ButtonShape)
            .clip(ButtonShape)
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.md)
            .wrapContentHeight(Alignment.CenterVertically)
    )
}

/** Надрядок з відліком: «СЬОГОДНІ · 19:30 · ЧЕРЕЗ 3 ГОД». Після початку `cardOverline` сам каже «триває зараз». */
@Composable
internal fun countdownOverline(event: Event): String {
    val base = cardOverline(event, dateWords())
    val now = Clock.System.now()
    val start = event.startInstant
    if (start == null || event.hasStarted(now)) return base
    val minutes = (start - now).inWholeMinutes.toInt().coerceAtLeast(1)
    // Далі за добу дата в надрядку каже більше, ніж «через 644 год».
    if (minutes >= MyEventsRules.COUNTDOWN_MAX_MINUTES) return base
    val left = if (minutes < 60) stringResource(
        R.string.countdown_minutes,
        minutes
    ) else stringResource(R.string.countdown_hours, minutes / 60)
    return "$base · ${left.uppercase()}"
}

/**
 * Відлік над назвою квитка панелі: «ТРИВАЄ ЗАРАЗ» чи «ЧЕРЕЗ 3 ГОД» у межах доби. День і час уже друкує корінець,
 * тож надрядок «ЧТ, 12 ЛИСТ. · 19:30» лише повторював би його.
 */
@Composable
private fun panelCountdown(event: Event): String? {
    val now = Clock.System.now()
    if (event.isUnderway(now)) return stringResource(R.string.underway_now).uppercase()
    val start = event.startInstant ?: return null
    if (start <= now) return null
    val minutes = (start - now).inWholeMinutes.toInt().coerceAtLeast(1)
    if (minutes >= MyEventsRules.COUNTDOWN_MAX_MINUTES) return null
    return (if (minutes < 60) stringResource(R.string.countdown_minutes, minutes)
    else stringResource(R.string.countdown_hours, minutes / 60)).uppercase()
}

/**
 * Голова панелей «Сьогодні» й «Найближча»: квиток із корінцем, як у стрічці, — відлік, назва й опис на поверхні, жанр,
 * час і місця «0/2» на корінці. Мініатюра 60 лише важчала сірим градієнтом і випадала зі світу квитків. Розгортається в
 * деталі ([UnfoldSource]).
 */
@Composable
private fun HeroHead(event: Event, status: @Composable () -> Unit, onClick: () -> Unit) =
    UnfoldSource(event.id, "mine_next", onClick) { source, open -> HeroHead(event, source, status, open) }

@Composable
private fun HeroHead(event: Event, modifier: Modifier, status: @Composable () -> Unit, onClick: () -> Unit) {
    val colors = Poruch.colors
    val cancelled = stringResource(R.string.cancelled_short)
    Ticket(
        ticketStub(event),
        stub = { StubTime(event) },
        modifier = modifier.fillMaxWidth()
            .ticketSemantics(ticketA11yLabel(event, if (event.isCancelled) cancelled else null), onClick),
        onClick = onClick
    ) {
        Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            panelCountdown(event)?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = colors.accentText)
            }
            Text(
                event.displayTitle,
                style = PoruchType.brandTitle3,
                color = colors.ink,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
            status()
        }
    }
}

/** Сьогоднішній план: дві дії, по які сюди приходять перед виходом. */
@Composable
private fun GoingHero(event: Event, unread: Int, onIntent: (MyEventsIntent) -> Unit) {
    val context = LocalContext.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        HeroHead(event, {
            if (event.isCancelled) TicketStamp(stringResource(R.string.cancelled_short), BadgeTone.Danger) else EventDescriptor(event)
        }) { onIntent(MyEventsIntent.OpenEvent(event.id)) }
        PanelActions { weight ->
            SecondaryButton(
                stringResource(R.string.open_in_maps),
                { context.openInMaps(event) },
                weight,
                icon = PoruchIcons.directions
            )
            // Чат бачать лише підтверджені: із запитом чи в черзі туди не пускає сервер.
            if (event.gathering?.joined == true) SecondaryButton(
                if (unread > 0) stringResource(
                    R.string.chat_short_unread,
                    unread
                ) else stringResource(R.string.chat_short),
                { onIntent(MyEventsIntent.OpenChat(event.id)) },
                weight,
                icon = PoruchIcons.chat
            )
        }
    }
}

/**
 * Дії панелі в ряд; на великому шрифті — одна під одною, бо в третину ширини «Учасники» обрізались. [content] отримує
 * модифікатор ширини кнопки: частка ряду або вся ширина.
 */
@Composable
private fun PanelActions(content: @Composable (Modifier) -> Unit) {
    if (LocalDensity.current.fontScale > STACK_FONT_SCALE) Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        content(Modifier.fillMaxWidth())
    } else Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        content(Modifier.weight(1f))
    }
}

/** Найближча своя подія: квиток (місця — на корінці), перший запит із відповіддю на місці й дії організатора. */
@Composable
private fun OrganizerPanel(
    event: Event,
    unread: Int,
    requests: List<JoinRequest>,
    /** Щойно відхилений запит: кілька секунд на його місці «Повернути». */
    declined: JoinRequest?,
    mutating: Boolean,
    onIntent: (MyEventsIntent) -> Unit
) {
    val colors = Poruch.colors
    val context = LocalContext.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        HeroHead(event, {
            if (event.isCancelled) StatusBadge(
                stringResource(R.string.cancelled),
                BadgeTone.Danger
            ) else EventDescriptor(event)
        }) { onIntent(MyEventsIntent.OpenEvent(event.id)) }
        if (declined != null) DeclinedRow(declined, onIntent)
        else requests.firstOrNull()?.let { request ->
            RequestRow(event, request, requests.size - 1, mutating, onIntent)
        }
        PanelActions { weight ->
            SecondaryButton(
                stringResource(R.string.participants),
                { onIntent(MyEventsIntent.OpenEvent(event.id)) },
                weight,
                icon = PoruchIcons.social
            )
            SecondaryButton(
                if (unread > 0) stringResource(
                    R.string.chat_short_unread,
                    unread
                ) else stringResource(R.string.chat_short),
                { onIntent(MyEventsIntent.OpenChat(event.id)) },
                weight,
                icon = PoruchIcons.chat
            )
            val share = stringResource(R.string.share)
            Box(
                Modifier
                    .size(52.dp)
                    .background(colors.brandContainer, CircleShape)
                    .clip(CircleShape)
                    .semantics { contentDescription = share }
                    .pressable { context.shareEvent(event) },
                contentAlignment = Alignment.Center
            ) { Icon(PoruchIcons.share, null, Modifier.size(18.dp), tint = colors.ink) }
        }
    }
}

@Composable
private fun RequestRow(
    event: Event,
    request: JoinRequest,
    more: Int,
    mutating: Boolean,
    onIntent: (MyEventsIntent) -> Unit
) {
    val colors = Poruch.colors
    val name = request.name.ifBlank { stringResource(R.string.chat_member) }
    val decline = stringResource(R.string.decline_request_a11y, name)
    Row(
        Modifier
            .fillMaxWidth()
            .background(colors.accentContainer, Radius.md)
            .padding(Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Avatar(name, request.avatarUrl, 36.dp)
        Column(Modifier.weight(1f)) {
            Text(
                name,
                style = MaterialTheme.typography.titleSmall,
                color = colors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                if (more > 0) stringResource(R.string.wants_to_join_more, more) else stringResource(
                    R.string.wants_to_join
                ),
                style = MaterialTheme.typography.bodySmall,
                color = colors.onAccentContainer,
                maxLines = 1
            )
        }
        Box(
            Modifier
                .size(40.dp)
                .background(colors.surface, CircleShape)
                .clip(CircleShape)
                .semantics { contentDescription = decline }
                .pressable(enabled = !mutating) { onIntent(MyEventsIntent.Decline(request)) },
            contentAlignment = Alignment.Center
        ) { Icon(PoruchIcons.close, null, Modifier.size(16.dp), tint = colors.ink) }
        Text(
            stringResource(R.string.approve),
            style = MaterialTheme.typography.labelLarge,
            color = colors.onBrand,
            modifier = Modifier
                .height(40.dp)
                .background(colors.brand, ButtonShape)
                .clip(ButtonShape)
                .pressable(enabled = !mutating) {
                    onIntent(
                        MyEventsIntent.Approve(
                            event.id,
                            request.userId
                        )
                    )
                }
                .padding(horizontal = Spacing.lg)
                .wrapContentHeight(Alignment.CenterVertically)
        )
    }
}

/**
 * Відмова ще не пішла: тиха смужка з «Повернути» замість запиту. «Повернути» — зліва: справа в цьому рядку стоїть
 * «Прийняти» наступного запиту, і запізнілий дотик після відліку приймав чужу людину.
 */
@Composable
private fun DeclinedRow(request: JoinRequest, onIntent: (MyEventsIntent) -> Unit) {
    val colors = Poruch.colors
    val name = request.name.ifBlank { stringResource(R.string.chat_member) }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .background(colors.surfaceMuted, Radius.md)
            .padding(horizontal = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        GhostButton(stringResource(R.string.undo), { onIntent(MyEventsIntent.UndoDecline) })
        Text(
            stringResource(R.string.request_declined, name),
            Modifier.weight(1f),
            style = MaterialTheme.typography.labelLarge,
            color = colors.inkSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/** Звідки «Оцінити» стає під рядок: 1.3 — найбільший системний шрифт без «екстра». */
private const val STACK_FONT_SCALE = 1.3f
