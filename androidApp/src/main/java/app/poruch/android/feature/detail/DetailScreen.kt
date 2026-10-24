package app.poruch.android.feature.detail

import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.android.feature.mine.countdownOverline
import app.poruch.domain.ArtistRole
import app.poruch.domain.ContactRules
import app.poruch.domain.Event
import app.poruch.domain.EventIndexEntry
import app.poruch.domain.TitleRules
import app.poruch.domain.FollowRules
import app.poruch.domain.CompanionRules
import app.poruch.domain.Membership
import app.poruch.domain.EventSession
import app.poruch.domain.asIndexEntry
import app.poruch.domain.Gathering
import app.poruch.domain.EventRating
import app.poruch.domain.RatingRules
import app.poruch.domain.RatingTag
import app.poruch.domain.ReportReason
import app.poruch.domain.ShelterKind
import app.poruch.domain.ListingState
import app.poruch.shared.DetailAction
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import kotlinx.coroutines.delay

@Composable
fun DetailScreen(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val event = state.screen.event
    if (event == null) {
        Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
            PageHeader(stringResource(R.string.about_event), back = { onIntent(DetailIntent.Back) })
            if (state.screen.loading) Box(Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center) {
                PoruchLoader()
            } else EmptyState(PoruchIcons.search, stringResource(R.string.details), stringResource(R.string.event_unavailable))
        }
        return
    }
    val scroll = rememberScrollState()
    var barHeight by remember { mutableStateOf(0.dp) }
    Box(Modifier.fillMaxSize().background(colors.canvas)) {
        PullToRefresh(state.refreshing, { onIntent(DetailIntent.Refresh) }, Modifier.fillMaxSize(), underStatusBar = true) {
            // Під нижньою панеллю дії — її виміряна висота разом із системною смугою: з великим шрифтом і другим рядом
            // («Шукаю компанію» під квитком) панель росте, і стала висота ховала під нею останню секцію.
            Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(bottom = barHeight + Spacing.md)) {
                Hero(event, state, scroll, onIntent)
                // Аркуш із заокругленим верхом наїжджає на обкладинку: сторінка лягає на афішу, а не продовжує її.
                Column(
                    Modifier.offset(y = -HERO_OVERLAP).fillMaxWidth().background(colors.canvas, Radius.sheet)
                ) {
                    Column(
                        Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.xl),
                        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                    ) {
                        state.screen.pendingMeet?.let { pending ->
                            state.screen.companionOf?.let { parent -> MeetDecision(state, event, parent, pending, onIntent) }
                        }
                        Restrictions(state)
                        state.screen.companionOf?.let { parent ->
                            GroupedRows {
                                LinkRow(PoruchIcons.social, stringResource(R.string.companion_parent, TitleRules.display(parent.title)), onClick = { onIntent(DetailIntent.OpenEvent(parent.id)) })
                            }
                        }
                        // Щось сталось — стан і продавці першими: по них сюди й прийшли.
                        state.screen.listing?.takeIf { it.needsAttention }?.let { Tickets(state, it, onIntent) }
                        ExternalActions(state, onIntent)
                    }
                    // Поза колонкою з полями: смуга дат іде від краю до краю.
                    if (state.screen.sessions.size > 1) Sessions(state, onIntent, Modifier.padding(top = Spacing.lg))
                    Column(
                        Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.lg),
                        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                    ) {
                        if (event.artists.isNotEmpty()) Lineup(event, onIntent)
                        Facts(event)
                        state.screen.listing?.takeIf { !it.needsAttention }?.let { Tickets(state, it, onIntent) }
                        if (state.screen.companions.isNotEmpty() && !state.screen.cancelled) Companions(state, onIntent)
                        event.gathering?.let { People(state, it, onIntent) }
                        Venue(event, state.screen.followingPlace, onIntent)
                        if (!state.screen.cancelled && !state.screen.ended) Safety(state, onIntent)
                        Description(event, onIntent)
                        if (state.screen.othersHere.isNotEmpty()) OthersHere(state.screen.othersHere, event.placeName, onIntent)
                        // Чат і посилання — для своїх: сервер віддає посилання лише організатору й підтвердженим.
                        if (state.screen.hasChat || event.gathering?.hasContact == true) ContactSection(state, event, onIntent)
                        if (state.screen.organizer && state.screen.requests.isNotEmpty()) JoinRequests(state, onIntent)
                        if (state.screen.canRate) RateEvent(state, onIntent)
                        if (state.screen.organizer && state.screen.ended && !state.screen.cancelled) Ratings(state)
                        // Після кінця редагувати й скасовувати нічого: лишаються відгуки.
                        if (state.screen.organizer && !state.screen.cancelled && !state.screen.ended) OrganizerActions(state, onIntent)
                        if (!state.screen.organizer) SafetyActions(event, onIntent)
                    }
                }
            }
        }
        // Коли аркуш доїхав до годинника, текст інакше йде під нього: смуга статусу набирає колір полотна.
        // Не раніше: світла смуга над темною обкладинкою відрізала б її.
        val density = LocalDensity.current
        val statusTop = WindowInsets.statusBars.getTop(density)
        val hero = heroHeight()
        Box(
            Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars)
                .graphicsLayer {
                    val from = (hero - HERO_OVERLAP - SCRIM_FADE).toPx() - statusTop
                    alpha = ((scroll.value - from) / SCRIM_FADE.toPx()).coerceIn(0f, 1f)
                }
                .background(colors.canvas)
        )
        StickyAction(
            state, event,
            Modifier.align(Alignment.BottomCenter).onSizeChanged { barHeight = with(density) { it.height.toDp() } },
            onIntent
        )
        AnimatedVisibility(
            state.boughtPrompt, Modifier.align(Alignment.BottomCenter).padding(bottom = barHeight),
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()
        ) { BoughtCard(onIntent) }
        // Без відповіді за 10 с картка зникає сама: це питання, а не перешкода.
        if (state.boughtPrompt) LaunchedEffect(Unit) { delay(10_000); onIntent(DetailIntent.BoughtPromptAnswered(false)) }
        CoachMarks(listOf(CoachTip.COMPANION), enabled = state.screen.canSeekCompany)
    }
    if (state.confirmingBlock) PoruchConfirmSheet(
        title = stringResource(R.string.block_user_title),
        message = stringResource(R.string.block_user_body),
        confirmLabel = stringResource(R.string.block_confirm),
        dismissLabel = stringResource(R.string.close),
        onConfirm = { onIntent(DetailIntent.BlockOrganizer) },
        onDismiss = { onIntent(DetailIntent.ConfirmBlock(false)) },
        tone = colors.danger
    )
    if (state.confirmingContact) state.screen.contactUrl?.let { url ->
        PoruchConfirmSheet(
            title = stringResource(R.string.contact_confirm_title),
            message = stringResource(R.string.contact_confirm_body, ContactRules.host(url)),
            confirmLabel = stringResource(R.string.contact_confirm_open),
            dismissLabel = stringResource(R.string.close),
            onConfirm = { onIntent(DetailIntent.OpenContact) },
            onDismiss = { onIntent(DetailIntent.ConfirmContact(false)) }
        )
    }
    state.reporting?.let { target -> ReportSheet(target, onIntent) }
    if (state.seekingCompany) CompanionSheet(event, state.screen.mutating, onIntent)
    state.movingMeet?.let { from ->
        val parent = state.screen.companionOf
        val start = parent?.startsAt
        if (parent != null && start != null) MeetTimeSheet(event, parent, start, from, state.screen.mutating, onIntent)
    }
    state.screen.person?.let { person ->
        val request = state.screen.organizer && state.screen.requests.any { it.userId == person.userId }
        PersonSheet(
            person, isMe = person.userId == state.screen.userId,
            onDismiss = { onIntent(DetailIntent.ClosePerson) },
            onBlock = { onIntent(DetailIntent.BlockPerson(person.userId)) },
            onReport = { onIntent(DetailIntent.ReportPerson(person.userId)) },
            follow = FollowAction(person.userId in state.screen.followedOrganizers) {
                onIntent(DetailIntent.ToggleFollowPerson(person.userId, person.profile?.name.orEmpty()))
            }
        ) { sheet ->
            if (request) {
                Text(stringResource(R.string.person_request), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    SecondaryButton(
                        stringResource(R.string.decline), { sheet.close { onIntent(DetailIntent.DeclineRequest(person.userId)) } },
                        Modifier.weight(1f), enabled = !state.screen.mutating
                    )
                    PrimaryButton(
                        stringResource(R.string.approve), { sheet.close { onIntent(DetailIntent.ApproveRequest(person.userId)) } },
                        Modifier.weight(1f), enabled = !state.screen.mutating
                    )
                }
            }
        }
    }
}

@Composable
internal fun StickyAction(state: DetailState, event: Event, modifier: Modifier, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    // Панель дії — квиток у руці: місця чи ціна й дії на поверхні, а корінець із часом, днем і кольором жанру — справа.
    // Дата на екрані одна, тут; обкладинка її не повторює. Плаває над сторінкою: дія під пальцем, а не смуга на всю ширину.
    Ticket(
        ticketStub(event), stub = { StubTime(event) },
        modifier = modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = Spacing.md, vertical = Spacing.sm),
        radius = Corner.xl, surface = colors.surfaceRaised, elevation = Elevation.overlay
    ) {
        Column(
            Modifier.padding(horizontal = Spacing.lg, vertical = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            val hint = @Composable { modifier: Modifier ->
                Text(
                    stickyHint(state),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (event.isCalledOff) colors.danger else colors.inkSecondary,
                    maxLines = 3, overflow = TextOverflow.Ellipsis, modifier = modifier
                )
            }
            if (state.screen.canSeekCompany) {
                // Афіша: ціна й квиток в один рядок — квиток купують на чужому сайті, тож він другорядний.
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                    hint(Modifier.weight(1f))
                    if (state.screen.action != DetailAction.NONE) SecondaryButton(
                        stringResource(state.screen.action.label), { onIntent(DetailIntent.PrimaryAction) },
                        enabled = state.screen.action.isEnabled && !state.screen.mutating, compact = true
                    )
                }
            } else {
                // Зустріч: пояснення («Організатор підтверджує кожного», «Лишилось 2 місця») — окремим рядком на всю
                // ширину, а дія під ним. Поруч із кнопкою воно обрізалось саме в момент рішення.
                hint(Modifier.fillMaxWidth())
                // Кнопки може не бути: у знятої афіші й афіші без посилання нема куди вести.
                if (state.screen.action != DetailAction.NONE) PrimaryAction(state, onIntent, Modifier.fillMaxWidth())
            }
            // Серце продукту — люди: на афіші головна дія — «Шукаю компанію», на всю ширину під ціною й квитком.
            if (state.screen.canSeekCompany) PrimaryButton(
                stringResource(R.string.companion_seek), { onIntent(DetailIntent.SeekCompany(true)) },
                Modifier.fillMaxWidth().coachTarget(CoachTip.COMPANION), enabled = !state.screen.mutating, icon = PoruchIcons.social
            )
        }
    }
}

@Composable
internal fun PrimaryAction(state: DetailState, onIntent: (DetailIntent) -> Unit, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    PrimaryButton(
        stringResource(state.screen.action.label),
        { onIntent(DetailIntent.PrimaryAction) },
        modifier,
        enabled = state.screen.action.isEnabled && !state.screen.mutating, loading = state.screen.mutating,
        tone = when (state.screen.action) {
            DetailAction.LEAVE -> colors.success
            DetailAction.LEAVE_WAITLIST -> colors.accentText
            else -> null
        }
    )
}

/** Рядок під датою в нижній панелі: місця й черга для кімнати, ціна або причина відсутності кнопки для афіші. */
@Composable
internal fun stickyHint(state: DetailState): String {
    if (state.screen.cancelled) return stringResource(R.string.cancelled)
    state.screen.listing?.let { listing ->
        return when {
            listing.state == ListingState.POSTPONED -> stringResource(R.string.state_postponed_summary)
            listing.isWithdrawn -> stringResource(R.string.state_unknown)
            state.screen.sessionStarted -> stringResource(R.string.session_started_hint)
            listing.hasSource -> listingPrice(listing)
            else -> stringResource(R.string.listing_hint_no_link)
        }
    }
    val room = state.screen.room ?: return ""
    return when {
        state.screen.ended -> stringResource(R.string.event_ended)
        room.awaitingApproval -> stringResource(R.string.request_pending_hint)
        // Гостю — що його чекає, не текст перемикача з редактора.
        room.approvalRequired && !room.joined && !state.screen.organizer -> stringResource(R.string.approval_guest_hint)
        room.isFull && !room.joined && !state.screen.organizer -> stringResource(R.string.waitlist_hint)
        else -> stringResource(R.string.seats, room.seatsLeft)
    }
}

internal val DetailAction.label: Int
    get() = when (this) {
        DetailAction.JOIN -> R.string.join
        DetailAction.LEAVE -> R.string.leave
        DetailAction.JOIN_WAITLIST -> R.string.join_waitlist
        DetailAction.LEAVE_WAITLIST -> R.string.leave_waitlist
        DetailAction.REQUEST -> R.string.request_join
        DetailAction.REQUESTED -> R.string.request_pending
        DetailAction.ORGANIZER -> R.string.you_organize
        DetailAction.TICKETS -> R.string.listing_tickets
        DetailAction.CANCELLED, DetailAction.NONE -> R.string.cancelled
    }
