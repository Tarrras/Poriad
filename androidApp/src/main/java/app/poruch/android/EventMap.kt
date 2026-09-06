package app.poruch.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Bundle
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorNode
import androidx.compose.ui.graphics.vector.VectorPath
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.poruch.android.ui.Poruch
import app.poruch.android.ui.PoruchColors
import app.poruch.android.ui.categories
import app.poruch.android.ui.categoryColor
import app.poruch.android.ui.categoryIcon
import app.poruch.domain.Event
import app.poruch.domain.PoruchLog
import app.poruch.domain.shortId
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonOptions
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.Point

data class MapBounds(val south: Double, val west: Double, val north: Double, val east: Double)

private const val EventSource = "poruch-events"
private const val PointSource = "poruch-point"
private const val ClusterHaloLayer = "poruch-cluster-halo"
private const val ClusterLayer = "poruch-cluster"
private const val ClusterCountLayer = "poruch-cluster-count"
private const val PinLayer = "poruch-pin"
private const val PointLayer = "poruch-point-pin"
private const val ChosenPointIcon = "poruch-chosen"
private const val CityZoom = 12.0
private const val FocusZoom = 15.0

/**
 * Vector-tile clustering keeps dense neighbourhoods usable: MapLibre groups points inside the style,
 * so panning stays smooth where the previous screen-space grouping rebuilt every marker on each idle.
 */
@Composable fun EventMap(
    events: List<Event>,
    latitude: Double,
    longitude: Double,
    modifier: Modifier = Modifier,
    selectedId: String? = null,
    choosePoint: ((Double, Double) -> Unit)? = null,
    topInset: Dp = 0.dp,
    bottomInset: Dp = 0.dp,
    centerToken: Int = 0,
    interactive: Boolean = true,
    onSelect: (String) -> Unit = {},
    onAreaChanged: (MapBounds) -> Unit = {},
    onLoadFailed: (Boolean) -> Unit = {}
) {
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val colors = Poruch.colors
    val reducedMotion = Poruch.reducedMotion
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val view = remember { MapLibre.getInstance(context); MapView(context).apply { onCreate(Bundle()) } }
    var map by remember { mutableStateOf<MapLibreMap?>(null) }
    var styleRevision by remember { mutableIntStateOf(0) }
    var gestured by remember { mutableStateOf(false) }
    var chosen by remember { mutableStateOf<LatLng?>(null) }
    val latestSelect by rememberUpdatedState(onSelect)
    val latestArea by rememberUpdatedState(onAreaChanged)
    val latestChoose by rememberUpdatedState(choosePoint)
    val latestFailure by rememberUpdatedState(onLoadFailed)

    DisposableEffect(view, lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> view.onStart()
                Lifecycle.Event.ON_RESUME -> view.onResume()
                Lifecycle.Event.ON_PAUSE -> view.onPause()
                Lifecycle.Event.ON_STOP -> view.onStop()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) view.onStart()
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) view.onResume()
        view.addOnDidFailLoadingMapListener { PoruchLog.w("map") { "style failed to load" }; latestFailure(true) }
        view.getMapAsync { ready ->
            map = ready
            ready.uiSettings.isRotateGesturesEnabled = false
            ready.uiSettings.isTiltGesturesEnabled = false
            if (!interactive) ready.uiSettings.setAllGesturesEnabled(false)
            ready.cameraPosition = CameraPosition.Builder().target(LatLng(latitude, longitude)).zoom(CityZoom).build()
            ready.addOnCameraMoveStartedListener { reason ->
                if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) gestured = true
            }
            ready.addOnCameraIdleListener {
                if (!gestured) return@addOnCameraIdleListener
                gestured = false
                ready.projection.visibleRegion.latLngBounds.let {
                    latestArea(MapBounds(it.latitudeSouth, it.longitudeWest, it.latitudeNorth, it.longitudeEast))
                }
            }
            ready.addOnMapLongClickListener { point ->
                val choose = latestChoose ?: return@addOnMapLongClickListener false
                chosen = point; choose(point.latitude, point.longitude); true
            }
            if (interactive) ready.addOnMapClickListener { point -> tap(ready, point, latestSelect) }
        }
        onDispose { lifecycle.removeObserver(observer); view.onPause(); view.onStop(); view.onDestroy() }
    }

    // Reloading the style on a theme flip re-registers images and layers, so it bumps the revision.
    LaunchedEffect(map, colors.dark) {
        val ready = map ?: return@LaunchedEffect
        val url = if (colors.dark) BuildConfig.MAP_STYLE_DARK_URL else BuildConfig.MAP_STYLE_URL
        ready.setStyle(url) { style ->
            registerImages(context, style, colors, density)
            style.addSource(
                GeoJsonSource(
                    EventSource, FeatureCollection.fromFeatures(emptyList()),
                    GeoJsonOptions().withCluster(true).withClusterRadius(56).withClusterMaxZoom(15)
                )
            )
            style.addSource(GeoJsonSource(PointSource, FeatureCollection.fromFeatures(emptyList())))
            style.addLayer(clusterHaloLayer(colors))
            style.addLayer(clusterLayer(colors))
            style.addLayer(clusterCountLayer(colors))
            style.addLayer(pinLayer())
            style.addLayer(chosenPointLayer())
            latestFailure(false)
            styleRevision++
            PoruchLog.i("map") { "style ready (${if (colors.dark) "dark" else "light"}), layers and pin images registered" }
        }
    }

    LaunchedEffect(map, styleRevision, events, selectedId) {
        val style = map?.style ?: return@LaunchedEffect
        val source = style.getSourceAs<GeoJsonSource>(EventSource) ?: return@LaunchedEffect
        source.setGeoJson(FeatureCollection.fromFeatures(events.map { it.toFeature(it.id == selectedId) }))
        PoruchLog.d("map") { "${events.size} pins, selected=${selectedId.shortId()}" }
    }

    LaunchedEffect(map, styleRevision, chosen) {
        val style = map?.style ?: return@LaunchedEffect
        val source = style.getSourceAs<GeoJsonSource>(PointSource) ?: return@LaunchedEffect
        val point = chosen
        source.setGeoJson(
            FeatureCollection.fromFeatures(
                if (point == null) emptyList() else listOf(Feature.fromGeometry(Point.fromLngLat(point.longitude, point.latitude)))
            )
        )
    }

    // Padding keeps the focused pin above the carousel and below the search controls.
    LaunchedEffect(map, topInset, bottomInset) {
        val ready = map ?: return@LaunchedEffect
        val top = (topInset.value * density).toInt()
        val bottom = (bottomInset.value * density).toInt()
        ready.setPadding(0, top, 0, bottom)
        // Attribution and logo share the bottom-left corner, which no overlay is allowed to cover.
        ready.uiSettings.apply {
            attributionGravity = android.view.Gravity.BOTTOM or android.view.Gravity.START
            setAttributionMargins((4 * density).toInt(), 0, 0, bottom + (4 * density).toInt())
            setLogoMargins((44 * density).toInt(), 0, 0, bottom + (8 * density).toInt())
            setCompassMargins(0, top + (8 * density).toInt(), (12 * density).toInt(), 0)
        }
    }

    LaunchedEffect(map, latitude, longitude, centerToken) {
        val ready = map ?: return@LaunchedEffect
        val update = CameraUpdateFactory.newLatLngZoom(LatLng(latitude, longitude), CityZoom)
        if (reducedMotion) ready.moveCamera(update) else ready.animateCamera(update, 450)
        gestured = false
    }

    LaunchedEffect(map, selectedId) {
        val ready = map ?: return@LaunchedEffect
        val event = events.firstOrNull { it.id == selectedId } ?: return@LaunchedEffect
        val zoom = maxOf(ready.cameraPosition.zoom, FocusZoom)
        val update = CameraUpdateFactory.newLatLngZoom(LatLng(event.latitude, event.longitude), zoom)
        if (reducedMotion) ready.moveCamera(update) else ready.animateCamera(update, 420)
        gestured = false
    }

    Box(modifier.fillMaxSize()) { AndroidView(factory = { view }, modifier = Modifier.fillMaxSize()) }
}

/** A tap hits a pin first, then a cluster; clusters expand to the zoom that splits them apart. */
private fun tap(map: MapLibreMap, point: LatLng, select: (String) -> Unit): Boolean {
    val screen = map.projection.toScreenLocation(point)
    val target = RectF(screen.x - 28f, screen.y - 28f, screen.x + 28f, screen.y + 28f)
    map.queryRenderedFeatures(target, PinLayer).firstOrNull()?.getStringProperty("id")?.let {
        PoruchLog.i("map") { "pin tapped ${it.shortId()}" }
        select(it); return true
    }
    val cluster = map.queryRenderedFeatures(target, ClusterLayer).firstOrNull() ?: return false
    val source = map.style?.getSourceAs<GeoJsonSource>(EventSource) ?: return false
    val geometry = cluster.geometry() as? Point ?: return false
    val zoom = runCatching { source.getClusterExpansionZoom(cluster).toDouble() }.getOrNull() ?: (map.cameraPosition.zoom + 2)
    PoruchLog.i("map") { "cluster tapped, expanding to zoom ${zoom.coerceAtMost(19.0)}" }
    map.animateCamera(
        CameraUpdateFactory.newLatLngZoom(LatLng(geometry.latitude(), geometry.longitude()), zoom.coerceAtMost(19.0)), 400
    )
    return true
}

private fun Event.toFeature(selected: Boolean): Feature =
    Feature.fromGeometry(Point.fromLngLat(longitude, latitude)).apply {
        addStringProperty("id", id)
        addStringProperty("icon", iconName(category, selected))
        addNumberProperty("sort", if (selected) 1 else 0)
    }

private fun iconName(category: String, selected: Boolean) = "poruch-pin-$category" + if (selected) "-on" else ""

private fun clusterHaloLayer(colors: PoruchColors) = CircleLayer(ClusterHaloLayer, EventSource).withProperties(
    PropertyFactory.circleColor(colors.brand.toArgb()),
    PropertyFactory.circleOpacity(if (colors.dark) 0.28f else 0.16f),
    PropertyFactory.circleRadius(
        Expression.interpolate(Expression.linear(), Expression.get("point_count"), Expression.stop(2, 26f), Expression.stop(60, 42f))
    )
).withFilter(Expression.has("point_count"))

private fun clusterLayer(colors: PoruchColors) = CircleLayer(ClusterLayer, EventSource).withProperties(
    PropertyFactory.circleColor(colors.brand.toArgb()),
    PropertyFactory.circleStrokeWidth(3f),
    PropertyFactory.circleStrokeColor(colors.surface.toArgb()),
    PropertyFactory.circleRadius(
        Expression.interpolate(Expression.linear(), Expression.get("point_count"), Expression.stop(2, 18f), Expression.stop(60, 30f))
    )
).withFilter(Expression.has("point_count"))

private fun clusterCountLayer(colors: PoruchColors) = SymbolLayer(ClusterCountLayer, EventSource).withProperties(
    PropertyFactory.textField(Expression.toString(Expression.get("point_count"))),
    PropertyFactory.textFont(arrayOf("Noto Sans Bold")),
    PropertyFactory.textSize(13f),
    PropertyFactory.textColor(colors.onBrand.toArgb()),
    PropertyFactory.textAllowOverlap(true),
    PropertyFactory.textIgnorePlacement(true)
).withFilter(Expression.has("point_count"))

private fun pinLayer() = SymbolLayer(PinLayer, EventSource).withProperties(
    PropertyFactory.iconImage(Expression.get("icon")),
    PropertyFactory.iconAnchor(Property.ICON_ANCHOR_BOTTOM),
    PropertyFactory.iconAllowOverlap(true),
    PropertyFactory.iconIgnorePlacement(true),
    PropertyFactory.symbolSortKey(Expression.get("sort"))
).withFilter(Expression.not(Expression.has("point_count")))

private fun chosenPointLayer() = SymbolLayer(PointLayer, PointSource).withProperties(
    PropertyFactory.iconImage(ChosenPointIcon),
    PropertyFactory.iconAnchor(Property.ICON_ANCHOR_BOTTOM),
    PropertyFactory.iconAllowOverlap(true)
)

private fun registerImages(context: Context, style: Style, colors: PoruchColors, density: Float) {
    val surface = colors.surface.toArgb()
    categories.forEach { category ->
        val hue = categoryColor(category).toArgb()
        val glyph = categoryIcon(category)
        style.addImage(iconName(category, false), pinBitmap(context, glyph, hue, surface, false, density))
        style.addImage(iconName(category, true), pinBitmap(context, glyph, hue, surface, true, density))
    }
    style.addImage(ChosenPointIcon, pinBitmap(context, categoryIcon("social"), colors.brand.toArgb(), surface, true, density))
}

/**
 * Pin plate drawn once per category and cached by the style: a category ring on a surface disc while
 * resting, and the inverse — a filled disc with a surface ring — once the pin is focused.
 */
private fun pinBitmap(context: Context, glyph: ImageVector, hue: Int, surface: Int, selected: Boolean, density: Float): Bitmap {
    val disc = (if (selected) 46f else 38f) * density
    val pointer = 9f * density
    val pad = 6f * density
    val width = (disc + pad * 2).toInt()
    val height = (disc + pointer + pad * 2).toInt()
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    bitmap.density = context.resources.displayMetrics.densityDpi
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    val cx = width / 2f
    val cy = pad + disc / 2f
    val radius = disc / 2f
    paint.color = if (selected) hue else surface
    paint.setShadowLayer(5f * density, 0f, 2f * density, 0x40000000)
    canvas.drawPath(Path().apply {
        moveTo(cx - pointer * 0.6f, cy + radius - density)
        lineTo(cx, cy + radius + pointer)
        lineTo(cx + pointer * 0.6f, cy + radius - density)
        close()
    }, paint)
    canvas.drawCircle(cx, cy, radius, paint)
    paint.clearShadowLayer()
    paint.style = Paint.Style.STROKE
    paint.strokeWidth = 2.5f * density
    paint.color = if (selected) surface else hue
    canvas.drawCircle(cx, cy, radius - paint.strokeWidth / 2f, paint)
    val size = (if (selected) 22f else 18f) * density
    canvas.save()
    canvas.translate(cx - size / 2f, cy - size / 2f)
    canvas.scale(size / glyph.defaultWidth.value, size / glyph.defaultHeight.value)
    paint.color = if (selected) surface else hue
    glyph.root.drawInto(canvas, paint)
    canvas.restore()
    return bitmap
}

/**
 * Rasterises a vector for the pin plate. Each sub-path is drawn the way it was authored: the app's
 * own glyphs are outlines, and filling them would turn a die into a solid square.
 */
private fun VectorGroup.drawInto(canvas: Canvas, paint: Paint) {
    forEach { node: VectorNode ->
        when (node) {
            is VectorPath -> {
                if (node.stroke != null) {
                    paint.style = Paint.Style.STROKE
                    // The canvas is already scaled to the glyph's own grid, so the authored width
                    // scales with it and the pin keeps the weight the rest of the app draws.
                    paint.strokeWidth = node.strokeLineWidth
                    paint.strokeCap = node.strokeLineCap.toAndroidCap()
                    paint.strokeJoin = node.strokeLineJoin.toAndroidJoin()
                } else {
                    paint.style = Paint.Style.FILL
                }
                val path = PathParser().addPathNodes(node.pathData).toPath().asAndroidPath()
                // Solid glyphs carry their counters as inner subpaths; without the even-odd rule
                // a palette's wells fill in and it becomes a disc.
                if (node.pathFillType == PathFillType.EvenOdd) path.fillType = Path.FillType.EVEN_ODD
                canvas.drawPath(path, paint)
            }
            is VectorGroup -> node.drawInto(canvas, paint)
        }
    }
}

private fun StrokeCap.toAndroidCap() = when (this) {
    StrokeCap.Round -> Paint.Cap.ROUND
    StrokeCap.Square -> Paint.Cap.SQUARE
    else -> Paint.Cap.BUTT
}

private fun StrokeJoin.toAndroidJoin() = when (this) {
    StrokeJoin.Round -> Paint.Join.ROUND
    StrokeJoin.Bevel -> Paint.Join.BEVEL
    else -> Paint.Join.MITER
}
