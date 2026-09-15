package app.poruch.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Bundle
import android.view.ViewGroup
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
import app.poruch.domain.EventIndexEntry
import app.poruch.domain.MapPins
import app.poruch.domain.VenuePin
import app.poruch.domain.PoruchLog
import app.poruch.domain.shortId
import app.poruch.shared.MapEndpoints
import app.poruch.shared.MapTokens
import app.poruch.shared.poruchMapStyle
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
private const val PinCountLayer = "poruch-pin-count"
private const val PointLayer = "poruch-point-pin"
private const val ChosenPointIcon = "poruch-chosen"
/** Радіус кластера в dp. Більший перетворював місто на кілька чорних бульбашок. */
private const val ClusterRadius = 40
/** Керування зумом з екрана: на виборі точки масштаб має бути й кнопкою, не лише щипком. */
class MapController {
    internal var apply: ((Double) -> Unit)? = null
    fun zoomIn() = apply?.invoke(1.0)
    fun zoomOut() = apply?.invoke(-1.0)
}

/** Масштаби, спільні для мапи й редактора. */
object MapZoom {
    /** Видно ціле місто. */
    const val city = 12.0
    /** Видно будинок. */
    const val street = 15.0
}


/**
 * MapView, що живе стільки, скільки Activity: створення MapView і розбір стилю — найдорожче на
 * головному потоці, і робити це на кожен вхід у вкладку не можна. [styledDark] пам'ятає, для
 * якої теми зібрано стиль. Лише для вкладки: міні-мапа деталей і редактор створюють власні.
 */
class SharedMapView(private val context: Context) {
    // Ліниво: платить лише запуск, у якому мапу справді відкрили.
    private var created: MapView? = null
    val view: MapView
        get() = created ?: run { MapLibre.getInstance(context); MapView(context).apply { onCreate(Bundle()) } }.also { created = it }
    var styledDark: Boolean? = null
    fun destroy() { created?.apply { onPause(); onStop(); onDestroy() }; created = null }
}

/** Спільна мапа вкладки. Корінь створює її і руйнує разом із собою. */
val LocalSharedMapView = staticCompositionLocalOf<SharedMapView?> { null }

/** Мапа подій. Кластеризацію робить MapLibre всередині стилю, тож панорамування не перебудовує маркери. */
@Composable fun EventMap(
    /** Індекс, а не картки: мапі досить координат і категорії, а індекс повний з першої відповіді. */
    events: List<EventIndexEntry>,
    latitude: Double,
    longitude: Double,
    modifier: Modifier = Modifier,
    selectedId: String? = null,
    /** Поставлена крапка. Мапа лише малює її; джерело одне — екран, бо крапку ставить і підказка адреси. */
    chosenPoint: Pair<Double, Double>? = null,
    /** Зум, коли центр змінився ззовні. */
    centerZoom: Double = MapZoom.city,
    /** Керування зумом кнопками. */
    controller: MapController? = null,
    topInset: Dp = 0.dp,
    bottomInset: Dp = 0.dp,
    centerToken: Int = 0,
    interactive: Boolean = true,
    onSelect: (String) -> Unit = {},
    /** Тап у місце з кількома подіями: усі id під пальцем. */
    onSelectStack: (List<String>) -> Unit = { ids -> ids.firstOrNull()?.let(onSelect) },
    onAreaChanged: (MapBounds) -> Unit = {},
    /** Центр камери, а не середина видимих меж: у Меркаторі це різні числа. */
    onCenterChanged: (Double, Double) -> Unit = { _, _ -> },
    onLoadFailed: (Boolean) -> Unit = {},
    /** Спільна мапа вкладки або null для власної. Див. [SharedMapView]. */
    shared: SharedMapView? = null
) {
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val colors = Poruch.colors
    val reducedMotion = Poruch.reducedMotion
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val view = shared?.view ?: remember { MapLibre.getInstance(context); MapView(context).apply { onCreate(Bundle()) } }
    var map by remember { mutableStateOf<MapLibreMap?>(null) }
    var styleRevision by remember { mutableIntStateOf(0) }
    var gestured by remember { mutableStateOf(false) }
    val latestSelect by rememberUpdatedState(onSelect)
    val latestStack by rememberUpdatedState(onSelectStack)
    val latestArea by rememberUpdatedState(onAreaChanged)
    val latestCenter by rememberUpdatedState(onCenterChanged)
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
        val failListener = MapView.OnDidFailLoadingMapListener { PoruchLog.w("map") { "style failed to load" }; latestFailure(true) }
        view.addOnDidFailLoadingMapListener(failListener)
        // Слухачі іменовані, щоб зняти їх при виході: спільна мапа інакше накопичувала б їх.
        val moveStarted = MapLibreMap.OnCameraMoveStartedListener { reason ->
            if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) gestured = true
        }
        var ready: MapLibreMap? = null
        val idle = MapLibreMap.OnCameraIdleListener {
            val m = ready ?: return@OnCameraIdleListener
            m.cameraPosition.target?.let { latestCenter(it.latitude, it.longitude) }
            if (!gestured) return@OnCameraIdleListener
            gestured = false
            m.projection.visibleRegion.latLngBounds.let {
                latestArea(MapBounds(it.latitudeSouth, it.longitudeWest, it.latitudeNorth, it.longitudeEast))
            }
        }
        val click = MapLibreMap.OnMapClickListener { point -> ready?.let { tap(it, point, latestStack) } ?: false }
        view.getMapAsync { m ->
            ready = m
            map = m
            m.uiSettings.isRotateGesturesEnabled = false
            m.uiSettings.isTiltGesturesEnabled = false
            m.uiSettings.setAllGesturesEnabled(interactive)
            m.cameraPosition = CameraPosition.Builder().target(LatLng(latitude, longitude)).zoom(centerZoom).build()
            m.addOnCameraMoveStartedListener(moveStarted)
            m.addOnCameraIdleListener(idle)
            if (interactive) m.addOnMapClickListener(click)
            controller?.apply = { delta ->
                // Обмежуємо межами мапи, щоб кнопка лишалась живою.
                val target = (m.cameraPosition.zoom + delta).coerceIn(m.minZoomLevel, m.maxZoomLevel)
                m.animateCamera(CameraUpdateFactory.zoomTo(target), 200)
            }
        }
        onDispose {
            controller?.apply = null
            lifecycle.removeObserver(observer)
            view.removeOnDidFailLoadingMapListener(failListener)
            ready?.apply {
                removeOnCameraMoveStartedListener(moveStarted); removeOnCameraIdleListener(idle); removeOnMapClickListener(click)
            }
            view.onPause(); view.onStop()
            // Спільну мапу руйнує корінь.
            if (shared == null) view.onDestroy()
        }
    }

    // Зміна теми перезавантажує стиль з іконками й шарами, тому підіймає ревізію.
    LaunchedEffect(map, colors.dark) {
        val ready = map ?: return@LaunchedEffect
        // Спільна мапа вже має стиль для цієї теми: лише повідомляємо ефекти нижче.
        if (shared != null) {
            val style = ready.style
            if (shared.styledDark == colors.dark && style?.getSource(EventSource) != null) {
                styleRevision++
                PoruchLog.d("map") { "style reused (${if (colors.dark) "dark" else "light"})" }
                return@LaunchedEffect
            }
            PoruchLog.d("map") { "shared map restyled: styledDark=${shared.styledDark} style=${style != null} source=${style?.getSource(EventSource) != null}" }
        }
        // Логотип рендерера прибираємо, атрибуцію даних лишаємо у тихому кольорі палітри.
        ready.uiSettings.isLogoEnabled = false
        ready.uiSettings.setAttributionTintColor(colors.inkTertiary.toArgb())
        ready.setStyle(Style.Builder().fromJson(poruchMapStyle(colors.mapTokens(), tilesUrl(), glyphsUrl()))) { style ->
            registerImages(context, style, colors, density)
            style.addSource(
                GeoJsonSource(
                    EventSource, FeatureCollection.fromFeatures(emptyList()),
                    // Пін — це місце, тож point_count рахував би місця; кількість подій збирає власна властивість.
                    GeoJsonOptions().withCluster(true).withClusterRadius(ClusterRadius).withClusterMaxZoom(15)
                        .withClusterProperty("events", Expression.sum(Expression.accumulated(), Expression.get("events")), Expression.get("count"))
                )
            )
            style.addSource(GeoJsonSource(PointSource, FeatureCollection.fromFeatures(emptyList())))
            style.addLayer(clusterHaloLayer(colors))
            style.addLayer(clusterLayer(colors))
            style.addLayer(clusterCountLayer(colors))
            style.addLayer(pinLayer())
            style.addLayer(pinCountLayer(colors))
            style.addLayer(chosenPointLayer())
            latestFailure(false)
            shared?.styledDark = colors.dark
            styleRevision++
            PoruchLog.i("map") { "poruch style ready (${if (colors.dark) "dark" else "light"}), layers and pin images registered" }
        }
    }

    // Групування залежить лише від подій, не від selectedId: інакше кожен крок каруселі перегруповував усе.
    val pins = remember(events) { MapPins.group(events) }

    // Той самий набір удруге не пишемо: перебудова GeoJSON коштує кадру.
    val written = remember { arrayOf<Any?>(null, null, null) }
    LaunchedEffect(map, styleRevision, pins, selectedId) {
        val style = map?.style ?: return@LaunchedEffect
        val source = style.getSourceAs<GeoJsonSource>(EventSource) ?: return@LaunchedEffect
        if (written[0] == styleRevision && written[1] === pins && written[2] == selectedId) return@LaunchedEffect
        written[0] = styleRevision; written[1] = pins; written[2] = selectedId
        source.setGeoJson(FeatureCollection.fromFeatures(pins.map { it.toFeature(selectedId) }))
        PoruchLog.d("map") {
            "${pins.size} pins for ${events.size} events, selected=${selectedId.shortId()}, style rev $styleRevision"
        }
    }

    LaunchedEffect(map, styleRevision, chosenPoint) {
        val style = map?.style ?: return@LaunchedEffect
        val source = style.getSourceAs<GeoJsonSource>(PointSource) ?: return@LaunchedEffect
        val point = chosenPoint?.let { (lat, lon) -> LatLng(lat, lon) }
        source.setGeoJson(
            FeatureCollection.fromFeatures(
                if (point == null) emptyList() else listOf(Feature.fromGeometry(Point.fromLngLat(point.longitude, point.latitude)))
            )
        )
    }

    // Відступи тримають обраний пін над каруселлю і під пошуком.
    LaunchedEffect(map, topInset, bottomInset) {
        val ready = map ?: return@LaunchedEffect
        val top = (topInset.value * density).toInt()
        val bottom = (bottomInset.value * density).toInt()
        ready.setPadding(0, top, 0, bottom)
        // Атрибуція в лівому нижньому куті, який ніщо не перекриває.
        ready.uiSettings.apply {
            attributionGravity = android.view.Gravity.BOTTOM or android.view.Gravity.START
            setAttributionMargins((8 * density).toInt(), 0, 0, bottom + (8 * density).toInt())
            setCompassMargins(0, top + (8 * density).toInt(), (12 * density).toInt(), 0)
        }
    }

    LaunchedEffect(map, latitude, longitude, centerToken) {
        val ready = map ?: return@LaunchedEffect
        val update = CameraUpdateFactory.newLatLngZoom(LatLng(latitude, longitude), centerZoom)
        if (reducedMotion) ready.moveCamera(update) else ready.animateCamera(update, 450)
        gestured = false
    }

    LaunchedEffect(map, selectedId) {
        val ready = map ?: return@LaunchedEffect
        val event = events.firstOrNull { it.id == selectedId } ?: return@LaunchedEffect
        val zoom = maxOf(ready.cameraPosition.zoom, MapZoom.street)
        val update = CameraUpdateFactory.newLatLngZoom(LatLng(event.latitude, event.longitude), zoom)
        if (reducedMotion) ready.moveCamera(update) else ready.animateCamera(update, 420)
        gestured = false
    }

    Box(modifier.fillMaxSize()) {
        // Спільна мапа могла лишитись у попередньому контейнері.
        AndroidView(factory = { (view.parent as? ViewGroup)?.removeView(view); view }, modifier = Modifier.fillMaxSize())
    }
}

/**
 * Тап шукає спершу пін, потім кластер, і віддає всі події під пальцем: події одного закладу
 * стоять на одній точці й не розходяться за жодного зуму. Кластер, який зум не розділить,
 * розкриваємо списком.
 */
private fun tap(map: MapLibreMap, point: LatLng, selectStack: (List<String>) -> Unit): Boolean {
    val screen = map.projection.toScreenLocation(point)
    val target = RectF(screen.x - 28f, screen.y - 28f, screen.x + 28f, screen.y + 28f)

    val pins = map.queryRenderedFeatures(target, PinLayer)
    if (pins.isNotEmpty()) {
        val ids = pins.flatMap { it.idsProperty() }.distinct()
        PoruchLog.i("map") { "pin tapped: ${pins.size} place(s), ${ids.size} event(s)" }
        selectStack(ids); return true
    }

    val cluster = map.queryRenderedFeatures(target, ClusterLayer).firstOrNull() ?: return false
    val source = map.style?.getSourceAs<GeoJsonSource>(EventSource) ?: return false
    val geometry = cluster.geometry() as? Point ?: return false
    val zoom = runCatching { source.getClusterExpansionZoom(cluster).toDouble() }.getOrNull()
    val current = map.cameraPosition.zoom

    // Наближаємо лише якщо це справді змінює зум, інакше показуємо вміст.
    if (zoom == null || zoom <= current + 0.1 || zoom > 19.0) {
        val leaves = runCatching { source.getClusterLeaves(cluster, CLUSTER_LEAF_LIMIT, 0) }.getOrNull()
        val ids = leaves?.features().orEmpty().flatMap { it.idsProperty() }.distinct()
        if (ids.isNotEmpty()) {
            PoruchLog.i("map") { "cluster tapped, opening ${ids.size} events in place" }
            selectStack(ids); return true
        }
    }
    PoruchLog.i("map") { "cluster tapped, expanding to zoom ${zoom?.coerceAtMost(19.0)}" }
    map.animateCamera(
        CameraUpdateFactory.newLatLngZoom(
            LatLng(geometry.latitude(), geometry.longitude()),
            (zoom ?: current + 2).coerceAtMost(19.0)
        ), 400
    )
    return true
}

/** Максимум подій зі стосу для каруселі. */
private const val CLUSTER_LEAF_LIMIT = 60L

/** Події місця, як їх записав `VenuePin.toFeature`. */
private fun Feature.idsProperty(): List<String> =
    getStringProperty("ids")?.split(",")?.filter { it.isNotBlank() }
        ?: listOfNotNull(getStringProperty("id"))

/** Одна фіча — одне місце. Усі події місця їдуть у властивості `ids`, щоб тап читав готовий список. */
private fun VenuePin.toFeature(selectedId: String?): Feature {
    val selected = contains(selectedId)
    return Feature.fromGeometry(Point.fromLngLat(longitude, latitude)).apply {
        // `id` — конкретна подія, що підписує пін: решта мапи оперує подіями.
        addStringProperty("id", if (selected) selectedId else representative.id)
        addStringProperty("ids", eventIds.joinToString(","))
        addStringProperty("icon", iconName(representative.category, selected))
        addNumberProperty("count", count)
        addNumberProperty("sort", if (selected) 1 else 0)
    }
}

private fun iconName(category: String, selected: Boolean) = "poruch-pin-$category" + if (selected) "-on" else ""

/** Збірка може вказати інший сервер тайлів; порожньо — звичний. */
private fun tilesUrl() = BuildConfig.MAP_TILES_URL.ifBlank { MapEndpoints.TILES }
private fun glyphsUrl() = BuildConfig.MAP_GLYPHS_URL.ifBlank { MapEndpoints.GLYPHS }

/** Токени палітри для стилю мапи. MapLibre читає кольори як hex. */
private fun PoruchColors.mapTokens() = MapTokens(
    canvas = canvas.hex(), canvasTint = canvasTint.hex(), surface = surface.hex(),
    surfaceMuted = surfaceMuted.hex(), hairline = hairline.hex(), ink = ink.hex(),
    inkSecondary = inkSecondary.hex(), inkTertiary = inkTertiary.hex(), dark = dark
)

private fun androidx.compose.ui.graphics.Color.hex() = "#%06X".format(toArgb() and 0xFFFFFF)

private fun clusterHaloLayer(colors: PoruchColors) = CircleLayer(ClusterHaloLayer, EventSource).withProperties(
    PropertyFactory.circleColor(colors.brand.toArgb()),
    PropertyFactory.circleOpacity(if (colors.dark) 0.28f else 0.16f),
    PropertyFactory.circleRadius(
        Expression.interpolate(Expression.linear(), Expression.get("events"), Expression.stop(2, 26f), Expression.stop(60, 42f))
    )
).withFilter(Expression.has("point_count"))

private fun clusterLayer(colors: PoruchColors) = CircleLayer(ClusterLayer, EventSource).withProperties(
    PropertyFactory.circleColor(colors.brand.toArgb()),
    PropertyFactory.circleStrokeWidth(3f),
    PropertyFactory.circleStrokeColor(colors.surface.toArgb()),
    PropertyFactory.circleRadius(
        Expression.interpolate(Expression.linear(), Expression.get("events"), Expression.stop(2, 18f), Expression.stop(60, 30f))
    )
).withFilter(Expression.has("point_count"))

private fun clusterCountLayer(colors: PoruchColors) = SymbolLayer(ClusterCountLayer, EventSource).withProperties(
    PropertyFactory.textField(Expression.toString(Expression.get("events"))),
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

/** Підпис з кількістю подій біля піна: значок лишається впізнаваним, стос не прикидається однією подією. */
private fun pinCountLayer(colors: PoruchColors) = SymbolLayer(PinCountLayer, EventSource).withProperties(
    PropertyFactory.textField(Expression.toString(Expression.get("count"))),
    PropertyFactory.textFont(arrayOf("Noto Sans Bold")),
    PropertyFactory.textSize(11f),
    PropertyFactory.textColor(colors.onBrand.toArgb()),
    PropertyFactory.textHaloColor(colors.brand.toArgb()),
    PropertyFactory.textHaloWidth(9f),
    PropertyFactory.textOffset(arrayOf(1.05f, -2.05f)),
    PropertyFactory.textAllowOverlap(true),
    PropertyFactory.textIgnorePlacement(true)
).withFilter(
    Expression.all(
        Expression.not(Expression.has("point_count")),
        Expression.gt(Expression.get("count"), Expression.literal(1))
    )
)

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

/** Значок піна, один на категорію, кешується стилем: кільце на диску в спокої, інверсія у фокусі. */
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

/** Растеризує вектор для піна. Кожен підшлях малюємо як задумано: контурні гліфи заливати не можна. */
private fun VectorGroup.drawInto(canvas: Canvas, paint: Paint) {
    forEach { node: VectorNode ->
        when (node) {
            is VectorPath -> {
                if (node.stroke != null) {
                    paint.style = Paint.Style.STROKE
                    // Canvas уже масштабований під сітку гліфа, тож товщина лінії масштабується разом.
                    paint.strokeWidth = node.strokeLineWidth
                    paint.strokeCap = node.strokeLineCap.toAndroidCap()
                    paint.strokeJoin = node.strokeLineJoin.toAndroidJoin()
                } else {
                    paint.style = Paint.Style.FILL
                }
                val path = PathParser().addPathNodes(node.pathData).toPath().asAndroidPath()
                // Без even-odd внутрішні контури заливаються і гліф стає диском.
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
