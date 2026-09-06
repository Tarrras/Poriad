package app.poruch.android.feature.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
                Venue(event)
                Description(event)
                if (state.organizer && !state.cancelled) OrganizerActions(state, onIntent)
            }
        }
        StickyAction(state, event, Modifier.align(Alignment.BottomCenter), onIntent)
    }
}

@Composable
private fun Hero(event: Event, saved: Boolean, onIntent: (DetailIntent) -> Unit) {
    Box(Modifier.fillMaxWidth().height(272.dp).padding(Spacing.sm).clip(Radius.lg)) {
        Box(Modifier.fillMaxSize().background(categoryWash(event.category)), contentAlignment = Alignment.Center) {
            Icon(categoryIcon(event.category), null, Modifier.size(48.dp), tint = categoryColor(event.category))
            event.imageUrl?.let {
                AsyncImage(model = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            }
        }
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
    Text(eventOverline(event), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
    Text(event.title, style = MaterialTheme.typography.displaySmall, color = colors.ink)
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        EventDescriptor(event, Modifier.weight(1f, fill = false))
        when {
            state.cancelled -> StatusBadge(stringResource(R.string.cancelled), BadgeTone.Danger)
            state.organizer -> StatusBadge(stringResource(R.string.you_organize), BadgeTone.Neutral, PoruchIcons.sparkle)
            event.joined -> StatusBadge(stringResource(R.string.going), BadgeTone.Success, Icons.Outlined.Check)
            state.waitlisted -> StatusBadge(stringResource(R.string.in_queue), BadgeTone.Accent, PoruchIcons.queue)
            eventScarce(event) -> StatusBadge(stringResource(R.string.seats_left, event.seatsLeft), BadgeTone.Accent)
        }
    }
}

@Composable
private fun Facts(event: Event) {
    Column(Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        InfoRow(PoruchIcons.calendar, stringResource(R.string.when_label), eventTime(event))
        InfoRow(PoruchIcons.pin, stringResource(R.string.where), "${event.city} · ${event.address}")
        InfoRow(
            PoruchIcons.person, stringResource(R.string.organizer_short),
            event.organizerName.ifBlank { stringResource(R.string.organizer_short) }
        )
        InfoRow(
            PoruchIcons.social, stringResource(R.string.capacity_label),
            stringResource(R.string.attendees, event.attendeeCount, event.capacity)
        )
    }
}

@Composable
private fun Roster(state: DetailState, event: Event) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        AvatarStack(state.attendees, total = event.attendeeCount)
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

@Composable
private fun Venue(event: Event) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.venue))
        Box(Modifier.fillMaxWidth().height(180.dp).cardSurface(Radius.md).padding(Spacing.xs).clip(Radius.sm)) {
            EventMap(listOf(event), event.latitude, event.longitude, selectedId = event.id, interactive = false)
        }
    }
}

@Composable
private fun Description(event: Event) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.description_title))
        Text(event.description, style = MaterialTheme.typography.bodyLarge, color = Poruch.colors.inkSecondary)
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
    if (state.confirmingCancel) AlertDialog(
        onDismissRequest = { onIntent(DetailIntent.ConfirmCancel(false)) }, containerColor = colors.surface, shape = Radius.lg,
        title = { Text(stringResource(R.string.cancel_event), style = MaterialTheme.typography.titleLarge, color = colors.ink) },
        text = { Text(stringResource(R.string.cancel_explain), style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary) },
        confirmButton = { GhostButton(stringResource(R.string.cancel_event), { onIntent(DetailIntent.CancelEvent) }, tone = colors.danger) },
        dismissButton = { GhostButton(stringResource(R.string.keep), { onIntent(DetailIntent.ConfirmCancel(false)) }) }
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
                eventOverline(event), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(
                when {
                    state.cancelled -> stringResource(R.string.cancelled)
                    state.full && !event.joined && !state.organizer -> stringResource(R.string.waitlist_hint)
                    else -> stringResource(R.string.seats, event.seatsLeft)
                },
                style = MaterialTheme.typography.bodyMedium,
                color = if (state.cancelled) colors.danger else colors.inkSecondary,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
        }
        PrimaryButton(
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

private val DetailAction.label: Int
    get() = when (this) {
        DetailAction.JOIN -> R.string.join
        DetailAction.LEAVE -> R.string.leave
        DetailAction.JOIN_WAITLIST -> R.string.join_waitlist
        DetailAction.LEAVE_WAITLIST -> R.string.leave_waitlist
        DetailAction.ORGANIZER -> R.string.you_organize
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
