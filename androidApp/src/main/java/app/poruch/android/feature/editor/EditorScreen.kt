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
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.R
import app.poruch.android.ui.*
import java.time.LocalDateTime

@Composable
fun EditorScreen(state: EditorState, onIntent: (EditorIntent) -> Unit, onClose: () -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
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

    state.picker?.let { request ->
        val startsAt = state.form.parse(state.form.starts)
        DateTimeSheet(
            initial = when (request) {
                PickerRequest.STARTS -> startsAt ?: LocalDateTime.now().plusDays(1).withMinute(0)
                PickerRequest.ENDS -> state.form.parse(state.form.ends) ?: startsAt?.plusHours(2) ?: LocalDateTime.now().plusDays(1).withMinute(0)
            },
            // An event cannot end before it starts, so the end picker starts where the start left off.
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
    val form = state.form
    LabelledField(stringResource(R.string.city), form.city, { value -> onIntent(EditorIntent.Edit { copy(city = value) }) })
    LabelledField(
        stringResource(R.string.address), form.address, { value -> onIntent(EditorIntent.Edit { copy(address = value) }) },
        hint = stringResource(R.string.point_help)
    )
    Box(Modifier.fillMaxWidth().height(260.dp).clip(Radius.md)) {
        EventMap(
            emptyList(), state.mapLatitude, state.mapLongitude,
            choosePoint = { lat, lon -> onIntent(EditorIntent.PickPoint(lat, lon)) }
        )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        LabelledField(
            stringResource(R.string.latitude), form.latitude, { value -> onIntent(EditorIntent.Edit { copy(latitude = value) }) },
            Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
        )
        LabelledField(
            stringResource(R.string.longitude), form.longitude, { value -> onIntent(EditorIntent.Edit { copy(longitude = value) }) },
            Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
        )
    }
}

@Composable
private fun ScheduleStep(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val form = state.form
    DateTimeField(stringResource(R.string.starts), form.starts) { onIntent(EditorIntent.ShowPicker(PickerRequest.STARTS)) }
    DateTimeField(stringResource(R.string.ends), form.ends) { onIntent(EditorIntent.ShowPicker(PickerRequest.ENDS)) }
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        LabelledField(
            stringResource(R.string.timezone), form.timeZone, { value -> onIntent(EditorIntent.Edit { copy(timeZone = value) }) },
            Modifier.weight(1f)
        )
        LabelledField(
            stringResource(R.string.capacity), form.capacity, { value -> onIntent(EditorIntent.Edit { copy(capacity = value.filter(Char::isDigit)) }) },
            Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
        )
    }
    Column(Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(
            stringResource(categoryLabel(form.category)).uppercase(), style = MaterialTheme.typography.labelSmall,
            color = categoryColor(form.category)
        )
        Text(form.title.ifBlank { stringResource(R.string.title) }, style = MaterialTheme.typography.titleLarge, color = colors.ink)
        MetaLine(PoruchIcons.pin, "${form.city} · ${form.address}")
        MetaLine(PoruchIcons.calendar, form.starts.ifBlank { stringResource(R.string.date_help) })
    }
    Text(stringResource(R.string.photo_after_publish), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
}

/** A date field looks like every other field on the form, but opens a picker instead of a keyboard. */
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
