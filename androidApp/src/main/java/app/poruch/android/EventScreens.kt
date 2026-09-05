package app.poruch.android

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.domain.Event
import app.poruch.shared.*
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

val categories = listOf("music", "sport", "art", "food", "games", "outdoors", "social")
val categoryLabels = listOf(R.string.music, R.string.sport, R.string.art, R.string.food, R.string.games, R.string.outdoors, R.string.social)
fun categoryLabel(key: String) = categoryLabels.getOrElse(categories.indexOf(key)) { R.string.all }
fun eventTime(event: Event): String = runCatching { Instant.parse(event.startsAt).atZone(ZoneId.of(event.timeZone)).format(DateTimeFormatter.ofPattern("d MMM · HH:mm", Locale.forLanguageTag("uk"))) + " · " + event.timeZone }.getOrDefault(event.startsAt)
@Composable fun PageHeader(title: String, back: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (back != null) IconButton(onClick = back) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back)) }
        Text(title, style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 8.dp))
    }
}
@Composable fun EventCard(event: Event, onClick: () -> Unit) {
    ElevatedCard(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(categoryLabel(event.category)), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Text(event.title, style = MaterialTheme.typography.titleLarge)
            Text(eventTime(event), style = MaterialTheme.typography.bodyMedium)
            Text(event.address, style = MaterialTheme.typography.bodyMedium)
            Text(if (event.status == "cancelled") stringResource(R.string.cancelled) else stringResource(R.string.seats, (event.capacity - event.attendeeCount).coerceAtLeast(0)), color = MaterialTheme.colorScheme.primary)
        }
    }
}
@Composable fun EventList(events: List<Event>, loading: Boolean, onClick: (String) -> Unit) {
    if (events.isEmpty() && !loading) Text(stringResource(R.string.no_events), Modifier.padding(24.dp))
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { items(events, key = { it.id }) { EventCard(it) { onClick(it.id) } } }
}
@Composable fun MyEventsScreen(state: AppState, open: (String) -> Unit, login: () -> Unit, refresh: () -> Unit) {
    Column { PageHeader(stringResource(R.string.my_events)); if (state.userId == null) Button(onClick = login, Modifier.padding(20.dp)) { Text(stringResource(R.string.login)) } else { TextButton(onClick = refresh) { Text(stringResource(R.string.refresh)) }; EventList(state.myEvents, state.loading, open) } }
}
@Composable fun DetailScreen(state: AppState, app: PoruchApp, back: () -> Unit, authenticated: (() -> Unit) -> Unit, edit: (String) -> Unit) {
    val event = state.selectedEvent
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        PageHeader(stringResource(R.string.details), back)
        if (event == null) { Text(stringResource(if (state.loading) R.string.loading else R.string.event_unavailable), Modifier.padding(24.dp)); return@Column }
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(stringResource(categoryLabel(event.category)), color = MaterialTheme.colorScheme.primary)
            Text(event.title, style = MaterialTheme.typography.headlineLarge)
            Text(eventTime(event)); Text(event.city + " · " + event.address)
            Text(stringResource(R.string.organizer, event.organizerName), style = MaterialTheme.typography.titleMedium)
            EventPhoto(event, app, event.organizerId == state.userId && event.status != "cancelled", state.mutating)
            Text(event.description, style = MaterialTheme.typography.bodyLarge)
            Text(stringResource(R.string.seats, (event.capacity - event.attendeeCount).coerceAtLeast(0)))
            val cancelled = event.status == "cancelled"
            val full = event.attendeeCount >= event.capacity
            Button(onClick = { authenticated { if (event.joined) app.leaveEvent(event.id) else app.joinEvent(event.id) } }, enabled = !state.mutating && !cancelled && (!full || event.joined), modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(if (cancelled) R.string.cancelled else if (event.joined) R.string.leave else if (full) R.string.full else R.string.join))
            }
            OutlinedButton(onClick = { authenticated { app.toggleSaved(event.id) } }, enabled = !state.mutating, modifier = Modifier.fillMaxWidth()) { Text(stringResource(if (event.id in state.savedIds) R.string.unsave else R.string.save)) }
            if (event.organizerId == state.userId && !cancelled) {
                TextButton(onClick = { edit(event.id) }) { Text(stringResource(R.string.edit)) }
                var confirmation by remember { mutableStateOf(false) }
                TextButton(onClick = { confirmation = true }, enabled = !state.mutating) { Text(stringResource(R.string.cancel_event), color = MaterialTheme.colorScheme.error) }
                if (confirmation) AlertDialog(onDismissRequest = { confirmation = false }, title = { Text(stringResource(R.string.cancel_event)) }, text = { Text(stringResource(R.string.cancel_explain)) }, confirmButton = { TextButton(onClick = { confirmation = false; app.cancelEvent(event.id) }) { Text(stringResource(R.string.cancel_event)) } }, dismissButton = { TextButton(onClick = { confirmation = false }) { Text(stringResource(R.string.keep)) } })
            }
        }
    }
}
