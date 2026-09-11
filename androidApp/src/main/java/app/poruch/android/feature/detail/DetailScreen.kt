package app.poruch.android.feature.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.Event
import app.poruch.domain.asIndexEntry
import app.poruch.domain.Gathering
import app.poruch.domain.ReportReason
import coil3.compose.AsyncImage

@Composable
fun DetailScreen(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val event = state.event
    if (event == null) {
        Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
            PageHeader(stringResource(R.string.about_event), back = { onIntent(DetailIntent.Back) })
            if (state.loading) Box(Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.ink)
            } else EmptyState(PoruchIcons.search, stringResource(R.string.details), stringResource(R.string.event_unavailable))
        }
        return
    }
    Box(Modifier.fillMaxSize().background(colors.canvas)) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 128.dp)) {
            Hero(event, state.saved, onIntent)
            Column(Modifier.padding(horizontal = Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
                Headline(event, state)
                Facts(event)
                if (state.attendees.isNotEmpty()) Roster(state, event)
                ExternalActions(state, onIntent)
                Venue(event, onIntent)
                Description(event, onIntent)
                if (state.organizer && state.requests.isNotEmpty()) JoinRequests(state, onIntent)
                if (state.organizer && !state.cancelled) OrganizerActions(state, onIntent)
                if (!state.organizer) SafetyActions(event, onIntent)
            }
        }
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
    state.reporting?.let { target -> ReportSheet(target, onIntent) }
}

/**
 * A report is a named reason plus, optionally, a sentence. The reason is what a moderation queue
 * can sort by — «this is about a minor» has to be answerable before «this is spam» — and the
 * sentence is what a person needs to say when the list does not fit their case.
 */
@Composable
private fun ReportSheet(target: ReportTarget, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    var reason by remember { mutableStateOf(ReportReason.MINORS) }
    var details by remember { mutableStateOf("") }
    PoruchSheet({ onIntent(DetailIntent.ShowReport(null)) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(
                stringResource(if (target == ReportTarget.EVENT) R.string.report_event_title else R.string.report_user_title),
                style = MaterialTheme.typography.titleLarge, color = colors.ink
            )
            Text(stringResource(R.string.report_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                reportReasons.forEach { (value, label) ->
                    Row(
                        Modifier.fillMaxWidth().clip(Radius.sm)
                            .selectable(reason == value, role = Role.RadioButton) { reason = value }
                            .padding(vertical = Spacing.md, horizontal = Spacing.sm),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                    ) {
                        Box(
                            Modifier.size(20.dp).background(if (reason == value) colors.brand else colors.surfaceMuted, CircleShape),
                            contentAlignment = Alignment.Center
                        ) { if (reason == value) Icon(Icons.Outlined.Check, null, Modifier.size(12.dp), tint = colors.onBrand) }
                        Text(stringResource(label), style = MaterialTheme.typography.bodyLarge, color = colors.ink)
                    }
                }
            }
            LabelledField(
                stringResource(R.string.report_details), details, { details = it },
                singleLine = false, minLines = 3
            )
            PrimaryButton(
                stringResource(R.string.report_send),
                { sheet.close { onIntent(DetailIntent.SendReport(reason, details)) } },
                Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun Hero(event: Event, saved: Boolean, onIntent: (DetailIntent) -> Unit) {
    Box(Modifier.fillMaxWidth().height(272.dp).padding(Spacing.sm).clip(Radius.lg)) {
        Box(Modifier.fillMaxSize().background(categoryGradient(event.category)), contentAlignment = Alignment.Center) {
            Icon(categoryIcon(event.category), null, Modifier.size(48.dp), tint = categoryInk(event.category))
            event.imageUrl?.let {
                AsyncImage(model = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            }
        }
        // Обкладинка афіші — чужа й довільна: під годинником і батареєю трапляється і білий вечір
        // на терасі, і яскравий постер. Тонка тінь зверху коштує нічого й тримає системну смугу
        // читабельною, чого власний скрим кожної кнопки зробити не може.
        Box(
            Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars.add(WindowInsets(top = Spacing.lg)))
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.32f), Color.Transparent)))
        )
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
            ScrimButton(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back)) { onIntent(DetailIntent.Back) }
            Spacer(Modifier.weight(1f))
            ScrimButton(Icons.Outlined.Share, stringResource(R.string.share)) { onIntent(DetailIntent.Share) }
            Spacer(Modifier.width(Spacing.sm))
            ScrimButton(
                if (saved) PoruchIcons.bookmarkFilled else PoruchIcons.bookmark,
                stringResource(if (saved) R.string.unsave else R.string.save)
            ) { onIntent(DetailIntent.ToggleSaved) }
        }
    }
}

@Composable
private fun Headline(event: Event, state: DetailState) {
    val colors = Poruch.colors
    val room = state.room
    Text(eventOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
    Text(event.title, style = MaterialTheme.typography.displaySmall, color = colors.ink)
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        EventDescriptor(event, Modifier.weight(1f, fill = false))
        when {
            state.cancelled -> StatusBadge(stringResource(R.string.cancelled), BadgeTone.Danger)
            // Афіша підписана джерелом завжди: атрибуція обов'язкова, а стану участі в неї немає.
            state.listing?.isWithdrawn == true -> StatusBadge(stringResource(R.string.listing_withdrawn), BadgeTone.Neutral)
            state.listing != null -> StatusBadge(stringResource(R.string.listing_badge, state.listing!!.sourceName), BadgeTone.Neutral)
            state.organizer -> StatusBadge(stringResource(R.string.you_organize), BadgeTone.Neutral, PoruchIcons.sparkle)
            room?.joined == true -> StatusBadge(stringResource(R.string.going), BadgeTone.Success, Icons.Outlined.Check)
            state.waitlisted -> StatusBadge(stringResource(R.string.in_queue), BadgeTone.Accent, PoruchIcons.queue)
            room?.awaitingApproval == true -> StatusBadge(stringResource(R.string.request_pending), BadgeTone.Accent, PoruchIcons.clock)
            room?.isScarce == true && !state.cancelled ->
                StatusBadge(stringResource(R.string.seats_left, room.seatsLeft), BadgeTone.Accent)
        }
    }
    // Who the evening is for, said on the card rather than discovered when the server refuses.
    // Обмежень віку в афіші не буває: їх встановлює організатор, якого в неї немає.
    if (room != null && (room.hasAgeLimit || room.approvalRequired)) Row(
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
    ) {
        if (room.hasAgeLimit) StatusBadge(ageLimitLabel(room), BadgeTone.Brand, PoruchIcons.person)
        if (room.approvalRequired) StatusBadge(stringResource(R.string.approval_badge), BadgeTone.Neutral, PoruchIcons.lock)
    }
}

@Composable
private fun ageLimitLabel(room: Gathering): String = room.maxAge?.let {
    stringResource(R.string.age_badge_range, room.minAge, it)
} ?: stringResource(R.string.age_badge_from, room.minAge)

/**
 * The door of an event that vets its guests. It sits inside the detail screen rather than on a
 * screen of its own because an organizer answers a request while looking at what they published —
 * the age limit they set is right above it.
 */
@Composable
private fun JoinRequests(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.requests_section))
        state.requests.forEach { person ->
            Row(
                Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                AvatarStack(listOf(person), total = 1, size = 36.dp)
                Text(person.name, style = MaterialTheme.typography.titleSmall, color = colors.ink, modifier = Modifier.weight(1f))
                GhostButton(stringResource(R.string.decline), { onIntent(DetailIntent.DeclineRequest(person.userId)) }, tone = colors.inkSecondary)
                PrimaryButton(stringResource(R.string.approve), { onIntent(DetailIntent.ApproveRequest(person.userId)) }, enabled = !state.mutating)
            }
        }
    }
}

/**
 * Reporting and blocking, at the bottom of the page and not hidden in a menu: somebody who needs
 * them is not in the mood to go looking, and a report that is hard to file is a report not filed.
 */
@Composable
private fun SafetyActions(event: Event, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    HairLine()
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        GhostButton(stringResource(R.string.report), { onIntent(DetailIntent.ShowReport(ReportTarget.EVENT)) }, tone = colors.inkSecondary)
        // Блокувати нема кого там, де немає людини: скарга на саму афішу лишається доступною.
        if (event.organizerId != null) GhostButton(
            stringResource(R.string.block_user), { onIntent(DetailIntent.ConfirmBlock(true)) }, tone = colors.inkSecondary
        )
    }
}

/**
 * Що це за подія, у чотирьох рядках. Останні два різні для кімнати й для афіші, і саме тут
 * найдовше жила вада: «ОРГАНІЗАТОР Karabas» і «0 з 1 учасників» під чужим концертом.
 */
@Composable
private fun Facts(event: Event) {
    Column(Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        InfoRow(PoruchIcons.calendar, stringResource(R.string.when_label), eventTime(event, dateWords()))
        InfoRow(PoruchIcons.pin, stringResource(R.string.where), listOf(event.city, event.address).filter { it.isNotBlank() }.joinToString(" · "))
        event.gathering?.let { room ->
            InfoRow(
                PoruchIcons.person, stringResource(R.string.organizer_short),
                room.organizerName.ifBlank { stringResource(R.string.organizer_short) }
            )
            InfoRow(
                PoruchIcons.social, stringResource(R.string.capacity_label),
                stringResource(R.string.attendees, room.attendeeCount, room.capacity)
            )
        }
        event.listing?.let { listing ->
            InfoRow(Icons.Outlined.Public, stringResource(R.string.listing_source_label), listing.sourceName)
            InfoRow(Icons.Outlined.ConfirmationNumber, stringResource(R.string.listing_price_label), listingPrice(listing))
        }
    }
}

@Composable
private fun Roster(state: DetailState, event: Event) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        AvatarStack(state.attendees, total = event.gathering?.attendeeCount ?: state.attendees.size)
        Column {
            Text(stringResource(R.string.attendees_going).uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                state.attendees.joinToString(", ") { it.name }.take(ROSTER_PREVIEW),
                style = MaterialTheme.typography.bodyMedium, color = colors.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun ExternalActions(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SecondaryButton(
            stringResource(R.string.add_to_calendar), { onIntent(DetailIntent.AddToCalendar) },
            Modifier.weight(1f), enabled = !state.cancelled, icon = Icons.Outlined.EditCalendar
        )
        SecondaryButton(
            stringResource(R.string.open_in_maps), { onIntent(DetailIntent.OpenInMaps) },
            Modifier.weight(1f), icon = Icons.Outlined.Directions
        )
    }
}

/**
 * Місце події та вихід на велику мапу.
 *
 * Сама мініатюра жестів не приймає — сто вісімдесят точок замало, щоб у ній щось шукати. Але
 * питання «а що там поруч?» виникає саме тут, і відповідь у застосунку вже є, тож тап веде на
 * мапу, наведену на цей самий пін. Прозорий шар поверх мапи ловить дотик, бо MapView з
 * вимкненими жестами все одно поглинає його сам.
 */
@Composable
private fun Venue(event: Event, onIntent: (DetailIntent) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(if (event.isCommunity) R.string.venue else R.string.venue_listing))
        Box(Modifier.fillMaxWidth().height(180.dp).cardSurface(Radius.md).padding(Spacing.xs).clip(Radius.sm)) {
            EventMap(listOf(event.asIndexEntry()), event.latitude, event.longitude, selectedId = event.id, interactive = false)
            Box(
                Modifier.matchParentSize().pressable { onIntent(DetailIntent.OpenMap) },
                contentAlignment = Alignment.BottomEnd
            ) {
                Box(Modifier.padding(Spacing.sm)) {
                    StatusBadge(stringResource(R.string.show_map), BadgeTone.Neutral, PoruchIcons.map)
                }
            }
        }
    }
}

/**
 * Свій опис показуємо повністю, чужий — уривком і з посиланням. Межу проводить домен
 * ([Event.displayDescription]); тут лишається тільки не забути про сам вихід до джерела, без
 * якого уривок був би просто обрізаним текстом.
 */
@Composable
private fun Description(event: Event, onIntent: (DetailIntent) -> Unit) {
    // 867 подій із 1256 приходять узагалі без опису — джерело його не дає. Заголовок «опис» над
    // порожнечею гірший за відсутність секції: він обіцяє текст, якого немає й не буде.
    val text = event.displayDescription.trim()
    if (text.isEmpty() && event.listing?.hasSource != true) return
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        if (text.isNotEmpty()) {
            SectionHeader(stringResource(R.string.description_title))
            Text(text, style = PoruchType.lead, color = Poruch.colors.inkSecondary)
        }
        if (event.listing?.hasSource == true) GhostButton(
            stringResource(R.string.listing_read_more), { onIntent(DetailIntent.OpenSource) },
            tone = Poruch.colors.brand
        )
    }
}

@Composable
private fun OrganizerActions(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    HairLine()
    PhotoPickerButton(state.mutating) { bytes, mime -> onIntent(DetailIntent.AttachPhoto(bytes, mime)) }
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SecondaryButton(stringResource(R.string.edit), { onIntent(DetailIntent.Edit) }, Modifier.weight(1f), icon = Icons.Outlined.Edit)
        SecondaryButton(
            stringResource(R.string.cancel_event), { onIntent(DetailIntent.ConfirmCancel(true)) },
            Modifier.weight(1f), enabled = !state.mutating, tone = colors.danger
        )
    }
    if (state.confirmingCancel) PoruchConfirmSheet(
        title = stringResource(R.string.cancel_event),
        message = stringResource(R.string.cancel_explain),
        confirmLabel = stringResource(R.string.cancel_event),
        dismissLabel = stringResource(R.string.keep),
        onConfirm = { onIntent(DetailIntent.CancelEvent) },
        onDismiss = { onIntent(DetailIntent.ConfirmCancel(false)) },
        tone = colors.danger
    )
}

@Composable
private fun StickyAction(state: DetailState, event: Event, modifier: Modifier, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    Row(
        modifier.fillMaxWidth().background(colors.canvas).navigationBarsPadding().padding(Spacing.page),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
    ) {
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
        // Кнопки може не бути зовсім: у знятої афіші й у афіші без посилання нема куди вести, і
        // вимкнена кнопка тут була б лише запрошенням у нікуди.
        if (state.action != DetailAction.NONE) PrimaryButton(
            stringResource(state.action.label),
            { onIntent(DetailIntent.PrimaryAction) },
            enabled = state.action.isEnabled && !state.mutating, loading = state.mutating,
            tone = when (state.action) {
                DetailAction.LEAVE -> colors.success
                DetailAction.LEAVE_WAITLIST -> colors.accent
                else -> null
            }
        )
    }
}

/**
 * Рядок під датою в нижній панелі: одна фраза про те, що зараз можливо. Для кімнати це місця й
 * черга, для афіші — ціна або причина, чому кнопки немає.
 */
@Composable
private fun stickyHint(state: DetailState): String {
    if (state.cancelled) return stringResource(R.string.cancelled)
    state.listing?.let { listing ->
        return when {
            listing.isWithdrawn -> stringResource(R.string.listing_withdrawn_hint)
            listing.hasSource -> listingPrice(listing)
            else -> stringResource(R.string.listing_hint_no_link)
        }
    }
    val room = state.room ?: return ""
    return when {
        room.awaitingApproval -> stringResource(R.string.request_pending_hint)
        room.approvalRequired && !room.joined && !state.organizer -> stringResource(R.string.approval_hint)
        room.isFull && !room.joined && !state.organizer -> stringResource(R.string.waitlist_hint)
        else -> stringResource(R.string.seats, room.seatsLeft)
    }
}

private val DetailAction.label: Int
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

@Composable
private fun ScrimButton(icon: ImageVector, description: String, onClick: () -> Unit) {
    // The hero photo is arbitrary, so these sit on their own light scrim rather than on a token.
    Box(
        Modifier.size(40.dp).background(Color.White.copy(alpha = 0.92f), CircleShape)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), CircleShape).clip(CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(icon, description, Modifier.size(18.dp), tint = Color(0xFF14130F)) }
}

@Composable
private fun InfoRow(icon: ImageVector, label: String, value: String) {
    val colors = Poruch.colors
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(34.dp).background(colors.surfaceMuted, Radius.xs), contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(17.dp), tint = colors.inkSecondary)
        }
        Column {
            Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(value, style = MaterialTheme.typography.bodyLarge, color = colors.ink)
        }
    }
}

private const val ROSTER_PREVIEW = 80
