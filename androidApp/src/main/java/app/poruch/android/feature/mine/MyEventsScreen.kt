package app.poruch.android.feature.mine

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Directions
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.feature.detail.RatingForm
import app.poruch.android.platform.openInMaps
import app.poruch.android.platform.shareEvent
import app.poruch.android.ui.*
import app.poruch.domain.Event
import app.poruch.domain.EventRating
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
                    style = MaterialTheme.typography.displaySmall,
                    color = colors.ink
                )
                Text(
                    if (state.signedIn) subtitle(state) else stringResource(R.string.guest_empty),
                    style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary
                )
            }
            if (state.signedIn) Row(
                Modifier.padding(horizontal = Spacing.page),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                MyEventsTab.entries.forEach { tab ->
                    PoruchChip(
                        stringResource(tab.label),
                        state.tab == tab,
                        { onIntent(MyEventsIntent.PickTab(tab)) },
                        badge = when (tab) {
                            MyEventsTab.GOING -> state.board.goingBadge
                            MyEventsTab.ORGANIZING -> state.board.organizingBadge
                            MyEventsTab.SAVED -> 0
                        }
                    )
                }
            }
        }
        if (!state.signedIn) EmptyState(
            PoruchIcons.lock,
            stringResource(R.string.guest_empty),
            stringResource(R.string.guest_description),
            Modifier.padding(top = Spacing.section),
            stringResource(R.string.login),
            { onIntent(MyEventsIntent.SignIn) }
        ) else PullToRefresh(
            state.refreshing,
            { onIntent(MyEventsIntent.Refresh) },
            Modifier.fillMaxSize()
        ) {
            val sections = state.board.sections(state.tab)
            // Порожній стан теж прокручується: інакше потяг не має за що зачепитись.
            if (sections.isEmpty()) Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
            ) {
                if (state.loading) Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(Spacing.section),
                    contentAlignment = Alignment.Center
                ) { PoruchLoader() }
                else Empty(state.tab, onIntent)
            } else Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .tabBarClearance()
                    .padding(start = Spacing.page, end = Spacing.page, top = Spacing.sm),
                verticalArrangement = Arrangement.spacedBy(Spacing.xxl)
            ) {
                sections.forEach { Section(it, state, onIntent) }
                if (state.tab == MyEventsTab.ORGANIZING) GroupedRows {
                    LinkRow(
                        PoruchIcons.sparkle,
                        stringResource(R.string.create_banner_title),
                        stringResource(R.string.create_banner_subtitle),
                        { onIntent(MyEventsIntent.CreateEvent) }
                    )
                }
            }
        }
    }
    state.rating?.let { event ->
        PoruchSheet({ onIntent(MyEventsIntent.DismissRating) }) { sheet ->
            Column(
                Modifier
                    .padding(horizontal = Spacing.page)
                    .padding(bottom = Spacing.xl)
                    .navigationBarsPadding(),
                verticalArrangement = Arrangement.spacedBy(Spacing.lg)
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    EventImage(
                        event, Modifier
                            .size(52.dp)
                            .clip(Radius.xs)
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            cardOverline(event, dateWords()),
                            style = MaterialTheme.typography.labelSmall,
                            color = Poruch.colors.inkTertiary
                        )
                        Text(
                            event.title,
                            style = MaterialTheme.typography.titleSmall,
                            color = Poruch.colors.ink,
                            maxLines = 2
                        )
                    }
                }
                val mine = state.myRatings[event.id]?.let { EventRating(it, null, "", true) }
                RatingForm(mine, state.mutating) { score, comment ->
                    sheet.close { onIntent(MyEventsIntent.Rate(event.id, score, comment)) }
                }
            }
        }
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
    val b = state.board
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
            modifier
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
                GoingHero(events.first(), state.unread[events.first().id] ?: 0, onIntent)
                Rows(events.drop(1), state, onIntent)
            }

            MyEventsGroup.UPCOMING -> if (state.tab == MyEventsTab.ORGANIZING) {
                Overline(R.string.section_nearest)
                val first = events.first()
                OrganizerPanel(
                    first,
                    state.unread[first.id] ?: 0,
                    state.requests.filter { it.eventId == first.id },
                    state.mutating,
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
    GroupedRows {
        events.forEachIndexed { index, event ->
            val score = state.myRatings[event.id]
            val rate =
                state.tab == MyEventsTab.GOING && score == null && RatingRules.canRate(event, now)
            // Запит до не найближчої події інакше видно лише в бейджі чипа.
            val asks = if (state.tab == MyEventsTab.ORGANIZING) state.requests.count { it.eventId == event.id } else 0
            EventRow(
                event,
                unread = state.unread[event.id] ?: 0,
                waitlisted = event.id in state.waitlistedIds,
                note = score?.let { stringResource(R.string.my_score, it) },
                trailing = when {
                    // Своя дія рядка: «Оцінити» для минулої, закладка — у збережених.
                    rate -> {
                        {
                            RateButton { onIntent(MyEventsIntent.StartRating(event)) }
                        }
                    }

                    state.tab == MyEventsTab.SAVED -> {
                        { SaveButton(true, { onIntent(MyEventsIntent.Unsave(event.id)) }) }
                    }

                    else -> null
                },
                status = if (asks > 0) pluralStringResource(R.plurals.join_requests, asks, asks) to BadgeTone.Accent else null
            ) { onIntent(MyEventsIntent.OpenEvent(event.id)) }
            if (index < events.lastIndex) HairLine(Modifier.padding(start = Spacing.lg + 60.dp + Spacing.md))
        }
    }
}

/** «Оцінити» в рядку минулої. Без гліфа: з ним кнопка забирала місце в назви й адреси. */
@Composable
private fun RateButton(onClick: () -> Unit) {
    val colors = Poruch.colors
    Text(
        stringResource(R.string.rate_action), style = MaterialTheme.typography.labelLarge, color = colors.onBrand, maxLines = 1,
        modifier = Modifier.height(36.dp).background(colors.brand, Radius.pill).clip(Radius.pill)
            .pressable(onClick = onClick).padding(horizontal = Spacing.md).wrapContentHeight(Alignment.CenterVertically)
    )
}

/** Надрядок з відліком: «СЬОГОДНІ · 19:30 · ЧЕРЕЗ 3 ГОД». Після початку `cardOverline` сам каже «триває зараз». */
@Composable
private fun countdownOverline(event: Event): String {
    val base = cardOverline(event, dateWords())
    val now = Clock.System.now()
    val start = event.startInstant
    if (start == null || event.hasStarted(now)) return base
    val minutes = (start - now).inWholeMinutes.toInt().coerceAtLeast(1)
    val left = if (minutes < 60) stringResource(
        R.string.countdown_minutes,
        minutes
    ) else stringResource(R.string.countdown_hours, minutes / 60)
    return "$base · ${left.uppercase()}"
}

/** Велика плитка, відлік, назва, опис — голова картки-героя і панелі організатора. */
@Composable
private fun HeroHead(event: Event, status: @Composable () -> Unit, onClick: () -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier
            .fillMaxWidth()
            .pressable(onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Розмір рядка: картку вирізняють відлік і дії, а велика плитка лише важчала сірим градієнтом.
        EventImage(event, Modifier.size(60.dp).clip(Radius.xs))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(
                countdownOverline(event),
                style = MaterialTheme.typography.labelSmall,
                color = colors.accent
            )
            Text(
                event.title,
                style = MaterialTheme.typography.titleMedium,
                color = colors.ink,
                maxLines = 2,
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
    Column(
        Modifier
            .fillMaxWidth()
            .cardSurface()
            .padding(Spacing.lg)
            .alpha(if (event.isCancelled) 0.6f else 1f),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        HeroHead(event, { EventDescriptor(event) }) { onIntent(MyEventsIntent.OpenEvent(event.id)) }
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            SecondaryButton(
                stringResource(R.string.open_in_maps),
                { context.openInMaps(event) },
                Modifier.weight(1f),
                icon = Icons.Outlined.Directions
            )
            // Чат бачать лише підтверджені: із запитом чи в черзі туди не пускає сервер.
            if (event.gathering?.joined == true) SecondaryButton(
                if (unread > 0) stringResource(
                    R.string.chat_short_unread,
                    unread
                ) else stringResource(R.string.chat_short),
                { onIntent(MyEventsIntent.OpenChat(event.id)) },
                Modifier.weight(1f),
                icon = Icons.Outlined.ChatBubbleOutline
            )
        }
    }
}

/** Найближча своя подія: заповненість, перший запит із відповіддю на місці й дії організатора. */
@Composable
private fun OrganizerPanel(
    event: Event,
    unread: Int,
    requests: List<JoinRequest>,
    mutating: Boolean,
    onIntent: (MyEventsIntent) -> Unit
) {
    val colors = Poruch.colors
    val context = LocalContext.current
    Column(
        Modifier
            .fillMaxWidth()
            .cardSurface()
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        HeroHead(event, {
            if (event.isCancelled) StatusBadge(
                stringResource(R.string.cancelled),
                BadgeTone.Danger
            ) else EventDescriptor(event)
        }) { onIntent(MyEventsIntent.OpenEvent(event.id)) }
        val room = event.gathering
        if (room != null && !event.isCancelled) Column(
            Modifier.semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
            ) {
                Text(
                    "${room.attendeeCount}",
                    style = MaterialTheme.typography.headlineSmall,
                    color = colors.ink
                )
                Text(
                    stringResource(R.string.seats_of, room.capacity),
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.inkSecondary
                )
            }
            LinearProgressIndicator(
                progress = { room.attendeeCount.toFloat() / room.capacity.coerceAtLeast(1) },
                Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .clip(Radius.pill),
                color = colors.success,
                trackColor = colors.hairline,
                drawStopIndicator = {}
            )
        }
        requests.firstOrNull()?.let { request ->
            RequestRow(event, request, requests.size - 1, mutating, onIntent)
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalAlignment = Alignment.CenterVertically
        ) {
            SecondaryButton(
                stringResource(R.string.participants),
                { onIntent(MyEventsIntent.OpenEvent(event.id)) },
                Modifier.weight(1f),
                icon = Icons.Outlined.Group
            )
            SecondaryButton(
                if (unread > 0) stringResource(
                    R.string.chat_short_unread,
                    unread
                ) else stringResource(R.string.chat_short),
                { onIntent(MyEventsIntent.OpenChat(event.id)) },
                Modifier.weight(1f),
                icon = Icons.Outlined.ChatBubbleOutline
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
            ) { Icon(Icons.Outlined.Share, null, Modifier.size(18.dp), tint = colors.ink) }
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
                .pressable(enabled = !mutating) {
                    onIntent(
                        MyEventsIntent.Decline(
                            event.id,
                            request.userId
                        )
                    )
                },
            contentAlignment = Alignment.Center
        ) { Icon(Icons.Outlined.Close, null, Modifier.size(16.dp), tint = colors.ink) }
        Text(
            stringResource(R.string.approve),
            style = MaterialTheme.typography.labelLarge,
            color = colors.onBrand,
            modifier = Modifier
                .height(40.dp)
                .background(colors.brand, Radius.pill)
                .clip(Radius.pill)
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
