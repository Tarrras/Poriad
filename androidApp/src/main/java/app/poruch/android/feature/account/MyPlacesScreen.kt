package app.poruch.android.feature.account

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.poruch.android.EventMap
import app.poruch.android.MapController
import app.poruch.android.R
import app.poruch.android.feature.editor.ZoomButton
import app.poruch.android.ui.*
import app.poruch.domain.District
import app.poruch.domain.DistrictHit
import app.poruch.domain.Zone
import app.poruch.domain.ZoneRules

/**
 * «Мої місця» (docs/my-places.md): райони й кола, де людина буває. Нова зустріч від людей у них — пуш «Біля вас»,
 * афіша поруч — у дайджесті. Рядок нікуди не веде: зону лише прибирають, а додають кнопками під списком.
 */
@Composable
fun MyPlacesScreen(state: MyPlacesState, onIntent: (MyPlacesIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
        Column {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = Spacing.page, vertical = Spacing.sm),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                Box(
                    Modifier.minimumInteractiveComponentSize().size(40.dp).cardSurface(CircleShape, Elevation.card)
                        .pressable(onClick = { onIntent(MyPlacesIntent.Back) }),
                    contentAlignment = Alignment.Center
                ) { Icon(PoruchIcons.arrowLeft, stringResource(R.string.back), Modifier.size(18.dp), tint = colors.ink) }
                Column(Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.places_title), style = MaterialTheme.typography.titleMedium, color = colors.ink,
                        modifier = Modifier.semantics { heading() }
                    )
                    Text(stringResource(R.string.places_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                }
            }
            HorizontalDivider(color = colors.hairline)
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding()
                .padding(horizontal = Spacing.page, vertical = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Text(stringResource(R.string.places_intro), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            if (state.zones.isEmpty()) EmptyState(
                PoruchIcons.pin, stringResource(R.string.places_empty_title), stringResource(R.string.places_empty_hint)
            ) else GroupedRows {
                // Новіші — останніми, як у списку на телефоні: понад десять іде найстаріше, тобто верхнє.
                state.zones.forEachIndexed { index, zone ->
                    if (index > 0) HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                    ZoneRow(zone, state.districts, state.city) { onIntent(MyPlacesIntent.Remove(zone.key)) }
                }
            }
            if (state.full) Text(
                stringResource(R.string.places_full, ZoneRules.MAX), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary
            )
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                // Місто без районів — лише коло.
                if (state.districts.isNotEmpty()) SecondaryButton(
                    stringResource(R.string.places_add_district), { onIntent(MyPlacesIntent.ShowDistricts(true)) },
                    Modifier.fillMaxWidth(), icon = PoruchIcons.district
                )
                SecondaryButton(
                    stringResource(R.string.places_add_circle), { onIntent(MyPlacesIntent.ShowCircle(true)) },
                    Modifier.fillMaxWidth(), icon = PoruchIcons.pin
                )
            }
        }
    }
    if (state.addingDistrict) DistrictPickerSheet(state, onIntent)
    if (state.pickingCircle) CirclePicker(state, onIntent)
}

/** Район: назва й «Район» чи «Місцевість»; коло: «Коло 2 км» і район центру. Праворуч — «×», що прибирає зону. */
@Composable
private fun ZoneRow(zone: Zone, districts: List<District>, city: String, onRemove: () -> Unit) {
    val colors = Poruch.colors
    val title: String
    val subtitle: String
    when (zone) {
        is Zone.Area -> {
            title = zone.name
            val locality = districts.firstOrNull { it.id == zone.districtId }?.isLocality == true
            // Зона з іншого міста — з назвою міста: район «Центральний» є не в одному.
            subtitle = listOfNotNull(
                stringResource(if (locality) R.string.places_locality else R.string.places_district),
                zone.city.takeIf { it.isNotBlank() && it != city }
            ).joinToString(" · ")
        }
        is Zone.Circle -> {
            title = stringResource(R.string.places_circle, stringResource(R.string.places_radius, zone.radiusM / 1000))
            subtitle = zone.label ?: stringResource(R.string.places_point)
        }
    }
    Row(
        Modifier.fillMaxWidth().padding(start = Spacing.lg, top = Spacing.md, bottom = Spacing.md, end = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Row(
            Modifier.weight(1f).semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Box(Modifier.size(40.dp).background(colors.surfaceMuted, Radius.xs), contentAlignment = Alignment.Center) {
                Icon(if (zone is Zone.Circle) PoruchIcons.pin else PoruchIcons.district, null, Modifier.size(20.dp), tint = colors.ink)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = PoruchType.brandTitle3, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        val remove = stringResource(R.string.places_remove, title)
        Box(
            Modifier.size(48.dp).clip(CircleShape).pressable(onClick = onRemove).semantics { contentDescription = remove },
            contentAlignment = Alignment.Center
        ) { Icon(PoruchIcons.close, null, Modifier.size(18.dp), tint = colors.inkSecondary) }
    }
}

/** Райони й місцевості міста з дзвінками: тап по рядку чи дзвінку — стежити чи перестати, шторка лишається. */
@Composable
private fun DistrictPickerSheet(state: MyPlacesState, onIntent: (MyPlacesIntent) -> Unit) {
    val colors = Poruch.colors
    val followed = state.followed
    val toggle = { hit: DistrictHit -> onIntent(MyPlacesIntent.ToggleDistrict(hit.district)) }
    PoruchSheet({ onIntent(MyPlacesIntent.ShowDistricts(false)) }) {
        Column(Modifier.padding(bottom = Spacing.section)) {
            Column(Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.lg)) {
                Text(
                    stringResource(R.string.places_add_district), style = PoruchType.brandTitle2, color = colors.ink,
                    modifier = Modifier.semantics { heading() }
                )
                Text(state.city, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
            }
            Column(
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
                verticalArrangement = Arrangement.spacedBy(Spacing.lg)
            ) {
                val (localities, districts) = state.hits.partition { it.district.isLocality }
                if (districts.isNotEmpty()) DistrictsGroup(districts, followed = followed, onFollow = toggle, onOpen = toggle)
                // Усі місцевості, а не лише з подіями, як на мапі: стежать і за тихим районом, де живуть.
                if (localities.isNotEmpty()) DistrictsGroup(
                    localities, title = stringResource(R.string.search_localities_group),
                    followed = followed, onFollow = toggle, onOpen = toggle
                )
            }
        }
    }
}

/**
 * Коло навколо точки: мапа рухається під шпилькою в центрі, коло поверх неї росте й меншає з масштабом. Радіус — 1, 2
 * чи 3 км, як приймає сервер. Як вибір точки в редакторі, але без адреси: точніше за ~100 м сервер і не зберігає.
 */
@Composable
private fun CirclePicker(state: MyPlacesState, onIntent: (MyPlacesIntent) -> Unit) {
    val colors = Poruch.colors
    var center by remember { mutableStateOf(state.latitude to state.longitude) }
    var radius by rememberSaveable { mutableIntStateOf(ZoneRules.RADIUS) }
    /** Метрів на dp у центрі; 0 — мапа ще не сказала. */
    var metersPerDp by remember { mutableDoubleStateOf(0.0) }
    val controller = remember { MapController() }
    val close = { onIntent(MyPlacesIntent.ShowCircle(false)) }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(colors.canvas)) {
            EventMap(
                emptyList(), state.latitude, state.longitude,
                modifier = Modifier.fillMaxSize(), centerZoom = CIRCLE_ZOOM, controller = controller,
                onCenterChanged = { latitude, longitude -> center = latitude to longitude },
                onScaleChanged = { metersPerDp = it }
            )
            // Коло й шпилька не приймають дотиків: мапа під ними має тягтися.
            val fill = colors.brand.copy(alpha = 0.12f)
            val edge = colors.brand.copy(alpha = 0.7f)
            if (metersPerDp > 0) Canvas(Modifier.fillMaxSize().clearAndSetSemantics { }) {
                val r = (radius / metersPerDp).dp.toPx()
                drawCircle(fill, r)
                drawCircle(edge, r, style = Stroke(2.dp.toPx()))
            }
            Icon(
                PoruchIcons.pin, null,
                Modifier.align(Alignment.Center).size(36.dp).offset(y = (-18).dp),
                tint = colors.brand
            )
            Column(Modifier.fillMaxWidth().statusBarsPadding()) {
                PageHeader(
                    stringResource(R.string.places_circle_title),
                    trailing = { GhostButton(stringResource(R.string.cancel), close, tone = colors.inkSecondary) }
                )
            }
            Column(
                Modifier.align(Alignment.CenterEnd).padding(Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                ZoomButton(PoruchIcons.plus, R.string.zoom_in) { controller.zoomIn() }
                ZoomButton(PoruchIcons.minus, R.string.zoom_out) { controller.zoomOut() }
            }
            Column(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(colors.surface)
                    .navigationBarsPadding().padding(Spacing.page),
                verticalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                // Той самий підпис, що ляже в список: район центру або «Точка на мапі».
                val label = state.districts.firstOrNull { !it.isLocality && it.contains(center.first, center.second) }?.name
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                    Icon(PoruchIcons.pin, null, Modifier.size(18.dp), tint = colors.inkSecondary)
                    Column(Modifier.weight(1f)) {
                        Text(
                            label ?: stringResource(R.string.places_point), style = MaterialTheme.typography.bodyLarge,
                            color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis
                        )
                        Text(stringResource(R.string.places_circle_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
                    }
                }
                SegmentedPill(
                    ZoneRules.RADII.map { stringResource(R.string.places_radius, it / 1000) },
                    ZoneRules.RADII.indexOf(radius).coerceAtLeast(0), { radius = ZoneRules.RADII[it] }
                )
                PrimaryButton(
                    stringResource(R.string.places_circle_save),
                    { onIntent(MyPlacesIntent.SaveCircle(center.first, center.second, radius)) },
                    Modifier.fillMaxWidth(), icon = PoruchIcons.bell
                )
            }
        }
    }
}

/** Коло 2 км видно цілим і з містом навколо. */
private const val CIRCLE_ZOOM = 11.5
