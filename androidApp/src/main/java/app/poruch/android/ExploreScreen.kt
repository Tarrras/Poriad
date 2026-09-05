package app.poruch.android

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.location.LocationManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.domain.CityResult
import app.poruch.shared.*

@SuppressLint("MissingPermission")
@Composable fun ExploreScreen(state: AppState, app: PoruchApp, detail: (String) -> Unit, create: () -> Unit) {
    var list by rememberSaveable { mutableStateOf(false) }
    var citySearch by rememberSaveable { mutableStateOf(false) }
    var available by rememberSaveable { mutableStateOf(false) }
    var locationError by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        if (results.values.any { it }) {
            val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val location = manager.getProviders(true).mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }
            if (location != null) app.selectCity(CityResult(context.getString(R.string.nearby), location.latitude, location.longitude))
            else {
                val provider = if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) LocationManager.NETWORK_PROVIDER else LocationManager.GPS_PROVIDER
                if (android.os.Build.VERSION.SDK_INT >= 30 && manager.isProviderEnabled(provider)) {
                    manager.getCurrentLocation(provider, null, context.mainExecutor) { fresh ->
                        if (fresh != null) app.selectCity(CityResult(context.getString(R.string.nearby), fresh.latitude, fresh.longitude)) else locationError=true
                    }
                } else locationError=true
            }
        } else locationError = true
    }
    val events = if (available) state.events.filter { it.attendeeCount < it.capacity } else state.events
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Column { Text(stringResource(R.string.discover), style = MaterialTheme.typography.labelLarge); TextButton(onClick = { citySearch = true }) { Text(state.cityName + " ⌄", style = MaterialTheme.typography.headlineSmall) } }
            TextButton(onClick = { list = !list }) { Text(stringResource(if (list) R.string.map else R.string.list)) }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("all" to R.string.any_date, "today" to R.string.today, "weekend" to R.string.weekend).forEach { (key, label) -> FilterChip(selected = state.dateFilter == key, onClick = { app.setDateFilter(key) }, label = { Text(stringResource(label)) }) }
            FilterChip(selected = available, onClick = { available = !available }, label = { Text(stringResource(R.string.available)) })
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = state.category.isEmpty() || state.category == "all", onClick = { app.setCategory("all") }, label = { Text(stringResource(R.string.all)) })
            categories.forEach { category -> FilterChip(selected = state.category == category, onClick = { app.setCategory(category) }, label = { Text(stringResource(categoryLabel(category))) }) }
        }
        if (locationError) Text(stringResource(R.string.location_fallback), Modifier.padding(16.dp), style = MaterialTheme.typography.bodySmall)
        Box(Modifier.weight(1f)) {
            if (list) EventList(events, state.loading) { app.selectEvent(it); detail(it) } else EventMap(events, state.cityLatitude, state.cityLongitude, app::selectEvent, app::searchArea)
            if (!list) {
                Column(Modifier.align(Alignment.TopEnd).padding(12.dp), horizontalAlignment = Alignment.End) {
                    FilledTonalButton(onClick = { permission.launch(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)) }) { Text(stringResource(R.string.nearby)) }
                    Button(onClick = create) { Text(stringResource(R.string.create)) }
                }
                if (events.isEmpty() && !state.loading && state.selectedEvent == null) Surface(Modifier.align(Alignment.BottomCenter).padding(20.dp), shape = MaterialTheme.shapes.large, tonalElevation = 2.dp) {
                    Text(stringResource(R.string.empty_map), Modifier.padding(16.dp), style=MaterialTheme.typography.bodyMedium)
                }
                state.selectedEvent?.let { event -> Box(Modifier.align(Alignment.BottomCenter).padding(16.dp)) { EventCard(event) { detail(event.id) } } }
            }
        }
        if (list) Button(onClick = create, modifier = Modifier.fillMaxWidth().padding(16.dp)) { Text(stringResource(R.string.create)) }
    }
    if (citySearch) {
        var query by rememberSaveable { mutableStateOf("") }
        AlertDialog(onDismissRequest = { citySearch = false }, title = { Text(stringResource(R.string.city_search)) }, text = {
            Column {
                OutlinedTextField(query, { query = it }, label = { Text(stringResource(R.string.city)) }, singleLine = true)
                TextButton(onClick = { app.searchCity(query) }, enabled = query.length >= 2) { Text(stringResource(R.string.search)) }
                state.cities.take(6).forEach { city -> TextButton(onClick = { app.selectCity(city); app.dismissEvent(); citySearch = false }) { Text(city.name) } }
            }
        }, confirmButton = { TextButton(onClick = { citySearch = false }) { Text(stringResource(R.string.close)) } })
    }
}
