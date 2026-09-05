package app.poruch.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Bundle
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.poruch.domain.Event
import org.maplibre.android.MapLibre
import org.maplibre.android.annotations.IconFactory
import org.maplibre.android.annotations.MarkerOptions
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.MapLibreMap

/** Screen-space clustering keeps dense neighborhoods usable without obscuring individual pins. */
@Suppress("DEPRECATION")
@Composable fun EventMap(events: List<Event>, latitude: Double, longitude: Double, select: (String) -> Unit, search: (Double, Double, Double, Double) -> Unit, choosePoint: ((Double, Double) -> Unit)? = null) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val view = remember { MapLibre.getInstance(context); MapView(context).apply { onCreate(Bundle()) } }
    var map by remember { mutableStateOf<MapLibreMap?>(null) }
    var moved by remember { mutableStateOf(false) }
    var revision by remember { mutableIntStateOf(0) }
    var error by remember { mutableStateOf(false) }
    var selectedPoint by remember { mutableStateOf<LatLng?>(null) }
    val latestSelect by rememberUpdatedState(select)
    val latestChoosePoint by rememberUpdatedState(choosePoint)
    DisposableEffect(view, lifecycle) {
        val observer = LifecycleEventObserver { _, event -> when (event) {
            Lifecycle.Event.ON_START -> view.onStart(); Lifecycle.Event.ON_RESUME -> view.onResume(); Lifecycle.Event.ON_PAUSE -> view.onPause(); Lifecycle.Event.ON_STOP -> view.onStop(); else -> Unit
        } }
        lifecycle.addObserver(observer)
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) view.onStart()
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) view.onResume()
        view.addOnDidFailLoadingMapListener { error = true }
        view.getMapAsync { ready ->
            ready.setStyle(BuildConfig.MAP_STYLE_URL) { error = false; map = ready }
            ready.addOnMapLongClickListener { point -> if (latestChoosePoint != null) { selectedPoint=point; latestChoosePoint?.invoke(point.latitude, point.longitude); true } else false }
            ready.addOnCameraIdleListener { moved = true; revision++ }
        }
        onDispose { lifecycle.removeObserver(observer); view.onPause(); view.onStop(); view.onDestroy() }
    }
    LaunchedEffect(map, latitude, longitude) { map?.cameraPosition = CameraPosition.Builder().target(LatLng(latitude, longitude)).zoom(12.0).build(); moved = false }
    LaunchedEffect(map, events, revision, selectedPoint) {
        val ready = map ?: return@LaunchedEffect
        ready.clear()
        selectedPoint?.let { ready.addMarker(MarkerOptions().position(it)) }
        val groups = events.groupBy { val p = ready.projection.toScreenLocation(LatLng(it.latitude, it.longitude)); (p.x / 72).toInt() to (p.y / 72).toInt() }
        val markers = mutableMapOf<Long, List<Event>>()
        groups.values.forEach { group ->
            val event = group.first()
            val label = if (group.size > 1) group.size.toString() else when (event.category) { "music" -> "♪"; "sport" -> "⚑"; "art" -> "✦"; "food" -> "♨"; "games" -> "⚄"; "outdoors" -> "▲"; else -> "●" }
            val bitmap = Bitmap.createBitmap(96, 112, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap); val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.color = android.graphics.Color.WHITE; canvas.drawCircle(48f, 48f, 46f, paint)
            paint.color = android.graphics.Color.rgb(36, 106, 80); canvas.drawCircle(48f, 48f, 41f, paint)
            paint.color = android.graphics.Color.WHITE; paint.textSize = 40f; paint.textAlign = Paint.Align.CENTER; paint.typeface = android.graphics.Typeface.DEFAULT_BOLD
            canvas.drawText(label, 48f, 62f, paint)
            val marker = ready.addMarker(MarkerOptions().position(LatLng(event.latitude, event.longitude)).title(if (group.size > 1) "${group.size}" else event.title).icon(IconFactory.getInstance(context).fromBitmap(bitmap)))
            markers[marker.id] = group
        }
        ready.setOnMarkerClickListener { marker ->
            markers[marker.id]?.let { group -> if (group.size == 1) latestSelect(group.first().id) else ready.animateCamera(CameraUpdateFactory.newLatLngZoom(marker.position, ready.cameraPosition.zoom + 2)) }; true
        }
    }
    Box(Modifier.fillMaxSize()) {
        AndroidView(factory = { view }, modifier = Modifier.fillMaxSize())
        if (moved && choosePoint == null) FilledTonalButton(onClick = { map?.projection?.visibleRegion?.latLngBounds?.let { search(it.latitudeSouth, it.longitudeWest, it.latitudeNorth, it.longitudeEast) }; moved = false }, modifier = Modifier.align(Alignment.TopCenter).padding(top = 120.dp)) { Text(stringResource(R.string.search_here)) }
        if (error) Surface(Modifier.align(Alignment.Center).padding(24.dp)) { Text(stringResource(R.string.map_error), Modifier.padding(16.dp)) }
    }
}
