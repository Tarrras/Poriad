package app.poruch.android

import android.content.Context
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.domain.EventDraft
import app.poruch.shared.*
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable fun EditorScreen(state: AppState, app: PoruchApp, editing: Boolean, back: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("event_draft", Context.MODE_PRIVATE) }
    val event = if (editing) state.selectedEvent else null
    var title by rememberSaveable { mutableStateOf(event?.title ?: prefs.getString("title", "").orEmpty()) }
    var description by rememberSaveable { mutableStateOf(event?.description ?: prefs.getString("description", "").orEmpty()) }
    var category by rememberSaveable { mutableStateOf(event?.category ?: prefs.getString("category", "social").orEmpty()) }
    var city by rememberSaveable { mutableStateOf(event?.city ?: prefs.getString("city", state.cityName).orEmpty()) }
    var address by rememberSaveable { mutableStateOf(event?.address ?: prefs.getString("address", "").orEmpty()) }
    var latitude by rememberSaveable { mutableStateOf(event?.latitude?.toString() ?: prefs.getString("latitude", state.cityLatitude.toString()).orEmpty()) }
    var longitude by rememberSaveable { mutableStateOf(event?.longitude?.toString() ?: prefs.getString("longitude", state.cityLongitude.toString()).orEmpty()) }
    var zone by rememberSaveable { mutableStateOf(event?.timeZone ?: prefs.getString("zone", "Europe/Kyiv").orEmpty()) }
    fun localTime(value: String?) = value?.let { runCatching { java.time.Instant.parse(it).atZone(ZoneId.of(zone)).toLocalDateTime().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")) }.getOrNull() }.orEmpty()
    var starts by rememberSaveable { mutableStateOf(if (editing) localTime(event?.startsAt) else prefs.getString("starts", "").orEmpty()) }
    var ends by rememberSaveable { mutableStateOf(if (editing) localTime(event?.endsAt) else prefs.getString("ends", "").orEmpty()) }
    var capacity by rememberSaveable { mutableStateOf(event?.capacity?.toString() ?: prefs.getString("capacity", "20").orEmpty()) }
    var step by rememberSaveable { mutableIntStateOf(0) }
    var error by remember { mutableStateOf<String?>(null) }
    var submitted by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.completedEventId) { if (submitted && state.completedEventId != null) { if (!editing) prefs.edit().clear().apply(); app.clearCompletedEvent(); back() } }
    LaunchedEffect(title, description, category, address, city, latitude, longitude, starts, ends, zone, capacity) { if (!editing) prefs.edit().putString("title", title).putString("description", description).putString("category", category).putString("address", address).putString("city", city).putString("latitude", latitude).putString("longitude", longitude).putString("starts", starts).putString("ends", ends).putString("zone", zone).putString("capacity", capacity).apply() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PageHeader(stringResource(if (editing) R.string.edit else R.string.create), back)
        Text(stringResource(R.string.step, step + 1), color = MaterialTheme.colorScheme.primary)
        LinearProgressIndicator(progress = { (step + 1) / 3f }, modifier = Modifier.fillMaxWidth())
        when (step) {
            0 -> {
                Field(title, { title = it }, R.string.title)
                Field(description, { description = it }, R.string.description, false)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) { categories.forEach { key -> FilterChip(category == key, { category = key }, label = { Text(stringResource(categoryLabel(key))) }) } }
            }
            1 -> {
                Field(city, { city = it }, R.string.city); Field(address, { address = it }, R.string.address)
                Text(stringResource(R.string.point_help))
                Box(Modifier.fillMaxWidth().height(260.dp)) { EventMap(emptyList(), state.cityLatitude, state.cityLongitude, {}, { _, _, _, _ -> }, { lat, lon -> latitude = lat.toString(); longitude = lon.toString() }) }
                Field(latitude, { latitude = it }, R.string.latitude); Field(longitude, { longitude = it }, R.string.longitude)
            }
            2 -> {
                Text(title, style = MaterialTheme.typography.titleLarge); Text("$city · $address")
                DateTimeField(starts, { starts = it }, R.string.starts); DateTimeField(ends, { ends = it }, R.string.ends)
                Field(zone, { zone = it }, R.string.timezone); Field(capacity, { capacity = it }, R.string.capacity)
                Text(stringResource(R.string.photo_after_publish))
                Text(stringResource(R.string.date_help), style = MaterialTheme.typography.bodySmall)
            }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (step > 0) TextButton(onClick = { step-- }) { Text(stringResource(R.string.back)) }
        Button(onClick = {
            if (step < 2) step++ else {
                runCatching {
                    val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
                    EventDraft(title.trim(), description.trim(), category, city.trim(), address.trim(), latitude.toDouble(), longitude.toDouble(), LocalDateTime.parse(starts, formatter).atZone(ZoneId.of(zone)).toInstant().toString(), LocalDateTime.parse(ends, formatter).atZone(ZoneId.of(zone)).toInstant().toString(), zone, capacity.toInt(), event?.imageUrl)
                }.onSuccess { draft -> error = null; app.clearCompletedEvent(); submitted = true; if (editing && event != null) app.updateEvent(event.id, draft) else app.createEvent(draft) }.onFailure { error = context.getString(R.string.invalid_draft) }
            }
        }, enabled = !state.mutating, modifier = Modifier.fillMaxWidth()) { Text(stringResource(if (step < 2) R.string.next else R.string.publish)) }
    }
}
@Composable private fun Field(value: String, change: (String) -> Unit, label: Int, single: Boolean = true) { OutlinedTextField(value, change, label = { Text(stringResource(label)) }, singleLine = single, minLines = if (single) 1 else 4, modifier = Modifier.fillMaxWidth()) }

@Composable private fun DateTimeField(value: String, change: (String) -> Unit, label: Int) {
    val context = LocalContext.current
    val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
    OutlinedButton(onClick = {
        val initial = runCatching { LocalDateTime.parse(value, formatter) }.getOrDefault(LocalDateTime.now().plusDays(1).withMinute(0))
        DatePickerDialog(context, { _, year, month, day ->
            TimePickerDialog(context, { _, hour, minute -> change(LocalDateTime.of(year, month + 1, day, hour, minute).format(formatter)) }, initial.hour, initial.minute, true).show()
        }, initial.year, initial.monthValue - 1, initial.dayOfMonth).show()
    }, modifier = Modifier.fillMaxWidth()) { Column(Modifier.padding(8.dp)) { Text(stringResource(label)); if (value.isNotBlank()) Text(value, style = MaterialTheme.typography.titleMedium) } }
}
