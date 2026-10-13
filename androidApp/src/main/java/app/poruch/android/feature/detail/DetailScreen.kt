package app.poruch.android.feature.detail

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.filled.Star
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

@Composable
fun DetailScreen(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val event = state.event
    if (event == null) {
        Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
            PageHeader(stringResource(R.string.about_event), back = { onIntent(DetailIntent.Back) })
            if (state.loading) Box(Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center) {
                PoruchLoader()
            } else EmptyState(PoruchIcons.search, stringResource(R.string.details), stringResource(R.string.event_unavailable))
        }
        return
    }
    val scroll = rememberScrollState()
    Box(Modifier.fillMaxSize().background(colors.canvas)) {
        PullToRefresh(state.refreshing, { onIntent(DetailIntent.Refresh) }, Modifier.fillMaxSize(), underStatusBar = true) {
            // Під нижньою панеллю дії: її висота плюс системна смуга, якою б вона не була.
            // Дві кнопки в панелі («Шукаю компанію» і квиток) стоять другим рядом — панель вища.
            val bottom = if (state.canSeekCompany) 168.dp else 104.dp
            Column(Modifier.fillMaxSize().verticalScroll(scroll).navigationBarsPadding().padding(bottom = bottom)) {
                Hero(event, state, scroll, onIntent)
                // Аркуш із заокругленим верхом наїжджає на обкладинку: сторінка лягає на афішу, а не продовжує її.
                Column(
                    Modifier.offset(y = -HERO_OVERLAP).fillMaxWidth().background(colors.canvas, Radius.sheet)
                ) {
                    Column(
                        Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.xl),
                        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                    ) {
                        Restrictions(state)
                        state.companionOf?.let { parent ->
                            GroupedRows {
                                LinkRow(PoruchIcons.social, stringResource(R.string.companion_parent, TitleRules.display(parent.title)), onClick = { onIntent(DetailIntent.OpenEvent(parent.id)) })
                            }
                        }
                        ExternalActions(state, onIntent)
                    }
                    // Поза колонкою з полями: смуга дат іде від краю до краю.
                    if (state.sessions.size > 1) Sessions(state, onIntent, Modifier.padding(top = Spacing.lg))
                    Column(
                        Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.lg),
                        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                    ) {
                        if (event.artists.isNotEmpty()) Lineup(event, onIntent)
                        Facts(event)
                        if (state.companions.isNotEmpty() && !state.cancelled) Companions(state, onIntent)
                        event.gathering?.let { People(state, it, onIntent) }
                        Venue(event, state.followingPlace, onIntent)
                        if (!state.cancelled && !state.ended) Safety(state, onIntent)
                        Description(event, onIntent)
                        if (state.othersHere.isNotEmpty()) OthersHere(state.othersHere, event.placeName, onIntent)
                        // Чат і посилання — для своїх: сервер віддає посилання лише організатору й підтвердженим.
                        if (state.hasChat || event.gathering?.hasContact == true) ContactSection(state, event, onIntent)
                        if (state.organizer && state.requests.isNotEmpty()) JoinRequests(state, onIntent)
                        if (state.canRate) RateEvent(state, onIntent)
                        if (state.organizer && state.ended && !state.cancelled) Ratings(state)
                        // Після кінця редагувати й скасовувати нічого: лишаються відгуки.
                        if (state.organizer && !state.cancelled && !state.ended) OrganizerActions(state, onIntent)
                        if (!state.organizer) SafetyActions(event, onIntent)
                    }
                }
            }
        }
        // Коли аркуш доїхав до годинника, текст інакше йде під нього: смуга статусу набирає колір полотна.
        // Не раніше: світла смуга над темною обкладинкою відрізала б її.
        val density = LocalDensity.current
        val statusTop = WindowInsets.statusBars.getTop(density)
        Box(
            Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars)
                .graphicsLayer {
                    val from = (HERO_HEIGHT - HERO_OVERLAP - SCRIM_FADE).toPx() - statusTop
                    alpha = ((scroll.value - from) / SCRIM_FADE.toPx()).coerceIn(0f, 1f)
                }
                .background(colors.canvas)
        )
        StickyAction(state, event, Modifier.align(Alignment.BottomCenter), onIntent)
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
    if (state.confirmingContact) event.gathering?.contactUrl?.let { url ->
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
    if (state.seekingCompany) CompanionSheet(event, state.mutating, onIntent)
    state.person?.let { person ->
        val request = state.organizer && state.requests.any { it.userId == person.userId }
        PersonSheet(
            person, isMe = person.userId == state.userId,
            onDismiss = { onIntent(DetailIntent.ClosePerson) },
            onBlock = { onIntent(DetailIntent.BlockPerson(person.userId)) },
            onReport = { onIntent(DetailIntent.ReportPerson(person.userId)) },
            follow = FollowAction(person.userId in state.followedOrganizers) {
                onIntent(DetailIntent.ToggleFollowPerson(person.userId, person.profile?.name.orEmpty()))
            }
        ) { sheet ->
            if (request) {
                Text(stringResource(R.string.person_request), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    SecondaryButton(
                        stringResource(R.string.decline), { sheet.close { onIntent(DetailIntent.DeclineRequest(person.userId)) } },
                        Modifier.weight(1f), enabled = !state.mutating
                    )
                    PrimaryButton(
                        stringResource(R.string.approve), { sheet.close { onIntent(DetailIntent.ApproveRequest(person.userId)) } },
                        Modifier.weight(1f), enabled = !state.mutating
                    )
                }
            }
        }
    }
}

@Composable
internal fun StickyAction(state: DetailState, event: Event, modifier: Modifier, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    // Плаває над сторінкою, як таббар головної: дія під пальцем, а не смуга на всю ширину.
    Column(
        modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = Spacing.md, vertical = Spacing.sm)
            .cardSurface(Radius.xl, Elevation.overlay).padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    eventOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary,
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
                Text(
                    stickyHint(state),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (state.cancelled) colors.danger else colors.inkSecondary,
                    maxLines = 2, overflow = TextOverflow.Ellipsis
                )
            }
            // Кнопки може не бути: у знятої афіші й афіші без посилання нема куди вести.
            if (state.action != DetailAction.NONE) PrimaryAction(state, onIntent)
        }
        // «Шукаю компанію» під квитком на всю ширину: поруч із ціною й квитком не влазить.
        if (state.canSeekCompany) SecondaryButton(
            stringResource(R.string.companion_seek), { onIntent(DetailIntent.SeekCompany(true)) },
            Modifier.fillMaxWidth(), enabled = !state.mutating, icon = PoruchIcons.social
        )
    }
}

@Composable
internal fun PrimaryAction(state: DetailState, onIntent: (DetailIntent) -> Unit, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    PrimaryButton(
        stringResource(state.action.label),
        { onIntent(DetailIntent.PrimaryAction) },
        modifier,
        enabled = state.action.isEnabled && !state.mutating, loading = state.mutating,
        tone = when (state.action) {
            DetailAction.LEAVE -> colors.success
            DetailAction.LEAVE_WAITLIST -> colors.accent
            else -> null
        }
    )
}

/** Рядок під датою в нижній панелі: місця й черга для кімнати, ціна або причина відсутності кнопки для афіші. */
@Composable
internal fun stickyHint(state: DetailState): String {
    if (state.cancelled) return stringResource(R.string.cancelled)
    state.listing?.let { listing ->
        return when {
            listing.isWithdrawn -> stringResource(R.string.listing_withdrawn_hint)
            state.sessionStarted -> stringResource(R.string.session_started_hint)
            listing.hasSource -> listingPrice(listing)
            else -> stringResource(R.string.listing_hint_no_link)
        }
    }
    val room = state.room ?: return ""
    return when {
        state.ended -> stringResource(R.string.event_ended)
        room.awaitingApproval -> stringResource(R.string.request_pending_hint)
        // Гостю — що його чекає, не текст перемикача з редактора.
        room.approvalRequired && !room.joined && !state.organizer -> stringResource(R.string.approval_guest_hint)
        room.isFull && !room.joined && !state.organizer -> stringResource(R.string.waitlist_hint)
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
