package app.poruch.android.feature.editor

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.MapController
import app.poruch.android.MapZoom
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.ContactRules
import app.poruch.domain.SafetyRules
import java.time.LocalDateTime

@Composable
fun EditorScreen(state: EditorState, onIntent: (EditorIntent) -> Unit, onClose: () -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding().imePadding()) {
        PageHeader(stringResource(if (state.editing) R.string.edit else R.string.create), back = onClose)
        StepBar(state.step)
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(Spacing.page),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            when (state.step) {
                EditorStep.ABOUT -> AboutStep(state.form, onIntent)
                EditorStep.PLACE -> PlaceStep(state, onIntent)
                EditorStep.SCHEDULE -> ScheduleStep(state, onIntent)
            }
        }
        Row(
            Modifier.fillMaxWidth().background(colors.surface).navigationBarsPadding().padding(Spacing.page),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            if (state.step != EditorStep.ABOUT) SecondaryButton(
                stringResource(R.string.back), { onIntent(EditorIntent.Back) }, Modifier.weight(1f)
            )
            PrimaryButton(
                stringResource(if (!state.step.isLast) R.string.next else if (state.editing) R.string.apply else R.string.publish),
                { onIntent(if (state.step.isLast) EditorIntent.Submit else EditorIntent.Next) },
                Modifier.weight(if (state.step != EditorStep.ABOUT) 1f else 2f),
                enabled = state.canAdvance && !state.mutating, loading = state.mutating
            )
        }
    }

    if (state.pickingPoint) PointPicker(state, onIntent)

    state.picker?.let { request ->
        val startsAt = state.form.parse(state.form.starts)
        DateTimeSheet(
            initial = when (request) {
                PickerRequest.STARTS -> startsAt ?: LocalDateTime.now().plusDays(1).withMinute(0)
                PickerRequest.ENDS -> state.form.parse(state.form.ends) ?: startsAt?.plusHours(2) ?: LocalDateTime.now().plusDays(1).withMinute(0)
            },
            // Кінець не раніше початку.
            minimum = if (request == PickerRequest.ENDS) startsAt else null,
            onDismiss = { onIntent(EditorIntent.ShowPicker(null)) },
            onPicked = { onIntent(EditorIntent.SetDateTime(request, it)) }
        )
    }
}

private fun EditorForm.parse(value: String) =
    runCatching { LocalDateTime.parse(value, EditorForm.LOCAL_FORMAT) }.getOrNull()

@Composable
private fun StepBar(step: EditorStep) {
    val colors = Poruch.colors
    Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.page), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        EditorStep.entries.forEach { entry ->
            val reached = entry.ordinal <= step.ordinal
            val tint by animateColorAsState(
                if (reached) colors.brand else colors.hairline,
                animationSpec = tween(if (Poruch.reducedMotion) 0 else 220), label = "step"
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Box(Modifier.fillMaxWidth().height(4.dp).background(tint, Radius.pill))
                Text(
                    stringResource(entry.label), style = MaterialTheme.typography.labelSmall,
                    color = if (reached) colors.ink else colors.inkTertiary
                )
            }
        }
    }
}

@Composable
private fun AboutStep(form: EditorForm, onIntent: (EditorIntent) -> Unit) {
    LabelledField(
        stringResource(R.string.title), form.title, { value -> onIntent(EditorIntent.Edit { copy(title = value) }) },
        placeholder = stringResource(R.string.title_placeholder)
    )
    LabelledField(
        stringResource(R.string.description), form.description, { value -> onIntent(EditorIntent.Edit { copy(description = value) }) },
        placeholder = stringResource(R.string.description_placeholder), singleLine = false
    )
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(
            stringResource(R.string.categories).uppercase(), style = MaterialTheme.typography.labelSmall,
            color = Poruch.colors.inkTertiary
        )
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            categories.forEach { key ->
                CategoryTile(key, form.category == key) { onIntent(EditorIntent.Edit { copy(category = key) }) }
            }
        }
    }
}

@Composable
private fun PlaceStep(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val form = state.form
    LabelledField(stringResource(R.string.city), form.city, { value -> onIntent(EditorIntent.Edit { copy(city = value) }) })
    LabelledField(
        stringResource(R.string.address), form.address, { value -> onIntent(EditorIntent.Edit { copy(address = value) }) },
        placeholder = stringResource(R.string.address_placeholder),
        hint = stringResource(R.string.address_hint)
    )
    // Підказки одразу під полем, як продовження набору.
    if (state.addressSuggestions.isNotEmpty()) Column(
        Modifier.fillMaxWidth().cardSurface(), verticalArrangement = Arrangement.spacedBy(0.dp)
    ) {
        state.addressSuggestions.forEachIndexed { index, place ->
            if (index > 0) HairLine()
            Row(
                Modifier.fillMaxWidth().clickable { onIntent(EditorIntent.PickAddress(place)) }
                    .padding(Spacing.lg),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                Icon(PoruchIcons.pin, null, Modifier.size(18.dp), tint = colors.inkSecondary)
                Column(Modifier.weight(1f)) {
                    Text(place.label, style = MaterialTheme.typography.bodyLarge, color = colors.ink)
                    if (place.detail.isNotBlank()) Text(
                        place.detail, style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary,
                        maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
    Text(
        stringResource(if (state.pointChosen) R.string.address_point_set else R.string.address_or_map),
        style = MaterialTheme.typography.bodySmall,
        color = if (state.pointChosen) colors.success else colors.inkTertiary
    )
    // Мапа лише показує вибране: жести на 260 dp коштували б точності.
    Box(Modifier.fillMaxWidth().height(260.dp).clip(Radius.md)) {
        EventMap(
            emptyList(), state.mapLatitude, state.mapLongitude,
            chosenPoint = state.point, interactive = false,
            // Є крапка — показуємо будинок, а не місто.
            centerZoom = if (state.pointChosen) MapZoom.street else MapZoom.city
        )
    }
    SecondaryButton(
        stringResource(if (state.pointChosen) R.string.change_point else R.string.choose_point),
        { onIntent(EditorIntent.ShowPointPicker(true)) },
        Modifier.fillMaxWidth()
    )
}

/** Кругла кнопка масштабу поверх мапи. */
@Composable
private fun ZoomButton(icon: ImageVector, label: Int, onClick: () -> Unit) {
    val colors = Poruch.colors
    Box(
        Modifier.size(44.dp).background(colors.surface, androidx.compose.foundation.shape.CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, stringResource(label), Modifier.size(20.dp), tint = colors.ink)
    }
}

/** Повноекранна мапа з ціллю в центрі: рухається світ під нею, крапку не затуляє палець. */
@Composable
private fun PointPicker(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val start = state.point ?: (state.mapLatitude to state.mapLongitude)
    var center by remember { mutableStateOf(start) }
    val controller = remember { MapController() }
    Dialog(
        onDismissRequest = { onIntent(EditorIntent.ShowPointPicker(false)) },
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(Modifier.fillMaxSize().background(colors.canvas)) {
            EventMap(
                emptyList(), start.first, start.second,
                modifier = Modifier.fillMaxSize(),
                centerZoom = if (state.pointChosen) MapZoom.street else MapZoom.city,
                controller = controller,
                // Камера повідомляє про зупинку, а не про кожен кадр.
                onCenterChanged = { latitude, longitude ->
                    center = latitude to longitude
                    onIntent(EditorIntent.AimAt(latitude, longitude))
                }
            )
            // Ціль не приймає дотиків: мапа під нею має тягтися.
            Icon(
                PoruchIcons.pin, null,
                Modifier.align(Alignment.Center).size(36.dp).offset(y = (-18).dp),
                tint = colors.brand
            )
            Column(Modifier.fillMaxWidth().statusBarsPadding()) {
                PageHeader(
                    stringResource(R.string.choose_point_title),
                    back = { onIntent(EditorIntent.ShowPointPicker(false)) }
                )
            }
            Column(
                Modifier.align(Alignment.CenterEnd).padding(Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                ZoomButton(Icons.Outlined.Add, R.string.zoom_in) { controller.zoomIn() }
                ZoomButton(Icons.Outlined.Remove, R.string.zoom_out) { controller.zoomOut() }
            }
            Column(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(colors.surface)
                    .navigationBarsPadding().padding(Spacing.page),
                verticalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                // Адреса тут головна, тож і виглядає як головна.
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                    Icon(PoruchIcons.pin, null, Modifier.size(18.dp), tint = colors.inkSecondary)
                    Column(Modifier.weight(1f)) {
                        Text(
                            state.aimAddress.ifBlank { stringResource(R.string.point_searching) },
                            style = MaterialTheme.typography.bodyLarge,
                            color = if (state.aimAddress.isBlank()) colors.inkTertiary else colors.ink,
                            maxLines = 2, overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            stringResource(R.string.choose_point_hint),
                            style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
                        )
                    }
                }
                PrimaryButton(
                    stringResource(R.string.apply),
                    { onIntent(EditorIntent.PickPoint(center.first, center.second)) },
                    Modifier.fillMaxWidth()
                )
            }
        }
    }
}

/** Пояс визначає місце події, але показуємо його: мовчки підставлений неправильний гірший за видимий. */
@Composable
private fun TimeZoneNote(zone: String, fromPlace: Boolean) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(PoruchIcons.clock, null, Modifier.size(20.dp), tint = colors.inkSecondary)
        Column(Modifier.weight(1f)) {
            Text(
                stringResource(R.string.timezone).uppercase(),
                style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary
            )
            Text(zone, style = MaterialTheme.typography.bodyLarge, color = colors.ink)
            Text(
                stringResource(if (fromPlace) R.string.timezone_from_place else R.string.timezone_from_device),
                style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
            )
        }
    }
}

@Composable
private fun ScheduleStep(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val form = state.form
    DateTimeField(stringResource(R.string.starts), form.starts) { onIntent(EditorIntent.ShowPicker(PickerRequest.STARTS)) }
    DateTimeField(stringResource(R.string.ends), form.ends) { onIntent(EditorIntent.ShowPicker(PickerRequest.ENDS)) }
    LabelledField(
        stringResource(R.string.capacity), form.capacity, { value -> onIntent(EditorIntent.Edit { copy(capacity = value.filter(Char::isDigit)) }) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
    )
    TimeZoneNote(form.timeZone, state.timeZoneFromPlace)
    // Хто може прийти — частина публікації, а не сховане налаштування.
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.who_can_come))
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
            LabelledField(
                stringResource(R.string.age_from), form.minAge,
                { value -> onIntent(EditorIntent.Edit { copy(minAge = value.filter(Char::isDigit).take(3)) }) },
                Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
            )
            LabelledField(
                stringResource(R.string.age_to), form.maxAge,
                { value -> onIntent(EditorIntent.Edit { copy(maxAge = value.filter(Char::isDigit).take(3)) }) },
                Modifier.weight(1f), placeholder = stringResource(R.string.age_to_placeholder),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
            )
        }
        Text(
            stringResource(R.string.age_limit_hint, SafetyRules.MIN_SIGNUP_AGE),
            style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
        )
        Row(
            Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.approval_label), style = MaterialTheme.typography.titleSmall, color = colors.ink)
                Text(stringResource(R.string.approval_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
            }
            Switch(
                form.approvalRequired, { value -> onIntent(EditorIntent.Edit { copy(approvalRequired = value) }) },
                colors = SwitchDefaults.colors(checkedTrackColor = colors.brand, checkedThumbColor = colors.onBrand)
            )
        }
        // Чат — єдиний канал до учасників. Лише https: решту відкидає і чернетка, і сервер.
        LabelledField(
            stringResource(R.string.contact_label), form.contactUrl,
            { value -> onIntent(EditorIntent.Edit { copy(contactUrl = value.take(ContactRules.MAX_URL_LENGTH)) }) },
            placeholder = stringResource(R.string.contact_placeholder),
            hint = stringResource(R.string.contact_editor_hint),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
        )
        if (form.contactUrl.isNotBlank() && !ContactRules.isContactUrl(form.contactUrl)) Text(
            stringResource(R.string.field_contact_url), style = MaterialTheme.typography.bodySmall, color = colors.danger
        )
    }
    Column(Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(
            stringResource(categoryLabel(form.category)).uppercase(), style = MaterialTheme.typography.labelSmall,
            color = categoryInk(form.category)
        )
        Text(form.title.ifBlank { stringResource(R.string.title) }, style = MaterialTheme.typography.titleLarge, color = colors.ink)
        MetaLine(PoruchIcons.pin, "${form.city} · ${form.address}")
        MetaLine(PoruchIcons.calendar, form.starts.ifBlank { stringResource(R.string.date_help) })
    }
    Text(stringResource(R.string.photo_after_publish), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
}

/** Поле дати виглядає як решта полів, але відкриває пікер замість клавіатури. */
@Composable
private fun DateTimeField(label: String, value: String, onOpen: () -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp).background(colors.surface, Radius.sm)
                .border(1.dp, colors.hairline, Radius.sm).clip(Radius.sm).clickable(onClick = onOpen).padding(horizontal = Spacing.lg),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(PoruchIcons.clock, null, Modifier.size(20.dp), tint = colors.inkSecondary)
            Text(
                value.ifBlank { stringResource(R.string.date_help) }, style = MaterialTheme.typography.bodyLarge,
                color = if (value.isBlank()) colors.inkTertiary else colors.ink, modifier = Modifier.weight(1f)
            )
            Icon(Icons.Outlined.ChevronRight, null, Modifier.size(20.dp), tint = colors.inkTertiary)
        }
    }
}

private val EditorStep.label: Int
    get() = when (this) {
        EditorStep.ABOUT -> R.string.step_one
        EditorStep.PLACE -> R.string.step_two
        EditorStep.SCHEDULE -> R.string.step_three
    }
