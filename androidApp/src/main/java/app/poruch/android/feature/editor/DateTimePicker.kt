package app.poruch.android.feature.editor

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.SafetyRules
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneOffset

/**
 * Date then time, in one sheet, painted from our own tokens.
 *
 * The platform `DatePickerDialog` renders in the system accent and system language, which put a
 * green English dialog in the middle of a Ukrainian paper-and-ink app. Material 3's composable
 * picker takes our colour scheme, and the app's locale gives it Ukrainian month names — and it
 * arrives the way every other question in the app does, from the bottom edge.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateTimeSheet(initial: LocalDateTime, minimum: LocalDateTime?, onDismiss: () -> Unit, onPicked: (LocalDateTime) -> Unit) {
    val colors = Poruch.colors
    // One sheet, two steps: the date is kept here, so picking it swaps the contents rather than
    // dismissing one dialog and opening another over the same screen.
    var date by remember { mutableStateOf<LocalDate?>(null) }
    PoruchSheet(onDismiss) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            val chosen = date
            Text(
                stringResource(if (chosen == null) R.string.pick_date else R.string.pick_time),
                style = MaterialTheme.typography.titleLarge, color = colors.ink
            )
            if (chosen == null) {
                val dateState = rememberDatePickerState(
                    initialSelectedDateMillis = initial.toLocalDate().atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli(),
                    selectableDates = object : SelectableDates {
                        // A past date is never valid for an event, and the server rejects it anyway.
                        override fun isSelectableDate(utcTimeMillis: Long) =
                            utcTimeMillis >= (minimum ?: LocalDateTime.now()).toLocalDate().atStartOfDay()
                                .toInstant(ZoneOffset.UTC).toEpochMilli()
                    }
                )
                // The sheet already carries the title, so the picker's own is switched off.
                DatePicker(dateState, title = null, showModeToggle = false, colors = poruchDatePickerColors())
                SheetActions(
                    confirm = stringResource(R.string.next),
                    onConfirm = {
                        date = dateState.selectedDateMillis?.let {
                            Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                        } ?: initial.toLocalDate()
                    },
                    onDismiss = { sheet.close() }
                )
            } else {
                val timeState = rememberTimePickerState(initialHour = initial.hour, initialMinute = initial.minute, is24Hour = true)
                Box(Modifier.fillMaxWidth().padding(vertical = Spacing.sm), contentAlignment = Alignment.Center) {
                    TimePicker(timeState, colors = poruchTimePickerColors())
                }
                SheetActions(
                    confirm = stringResource(R.string.apply),
                    onConfirm = { sheet.close { onPicked(LocalDateTime.of(chosen, LocalTime.of(timeState.hour, timeState.minute))) } },
                    onDismiss = { sheet.close() }
                )
            }
        }
    }
}

/** The step's own footer: the way on is the button, the way out stays a quiet label beside it. */
@Composable
private fun SheetActions(confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        GhostButton(stringResource(R.string.close), onDismiss, tone = Poruch.colors.inkSecondary)
        Spacer(Modifier.weight(1f))
        PrimaryButton(confirm, onConfirm)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun poruchDatePickerColors() = Poruch.colors.let { colors ->
    DatePickerDefaults.colors(
        containerColor = colors.surface, titleContentColor = colors.inkSecondary,
        headlineContentColor = colors.ink, weekdayContentColor = colors.inkTertiary,
        dayContentColor = colors.ink, disabledDayContentColor = colors.inkTertiary,
        selectedDayContainerColor = colors.brand, selectedDayContentColor = colors.onBrand,
        todayContentColor = colors.brand, todayDateBorderColor = colors.brand,
        navigationContentColor = colors.ink, yearContentColor = colors.ink,
        selectedYearContainerColor = colors.brand, selectedYearContentColor = colors.onBrand,
        currentYearContentColor = colors.brand, dividerColor = colors.hairline
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun poruchTimePickerColors() = Poruch.colors.let { colors ->
    TimePickerDefaults.colors(
        clockDialColor = colors.surfaceMuted, clockDialSelectedContentColor = colors.onBrand,
        clockDialUnselectedContentColor = colors.ink, selectorColor = colors.brand,
        periodSelectorBorderColor = colors.hairline,
        timeSelectorSelectedContainerColor = colors.brandContainer,
        timeSelectorSelectedContentColor = colors.onBrandContainer,
        timeSelectorUnselectedContainerColor = colors.surfaceMuted,
        timeSelectorUnselectedContentColor = colors.inkSecondary
    )
}

/**
 * The one date the app asks for that is not an event: a birth date.
 *
 * It opens on the year a person who just turned eighteen was born, because that is the nearest
 * plausible answer, and it refuses anything later — the floor is stated by the control itself
 * rather than by an error after the fact. The server checks it again regardless.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BirthDateSheet(initial: LocalDate?, onDismiss: () -> Unit, onPicked: (LocalDate) -> Unit) {
    val colors = Poruch.colors
    val zone = ZoneOffset.UTC
    val latest = LocalDate.now().minusYears(SafetyRules.MIN_SIGNUP_AGE.toLong())
    val state = rememberDatePickerState(
        initialSelectedDateMillis = (initial ?: latest).atStartOfDay().toInstant(zone).toEpochMilli(),
        initialDisplayedMonthMillis = (initial ?: latest).withDayOfMonth(1).atStartOfDay().toInstant(zone).toEpochMilli(),
        yearRange = latest.year - 100..latest.year,
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long) =
                utcTimeMillis <= latest.atStartOfDay().toInstant(zone).toEpochMilli()
            override fun isSelectableYear(year: Int) = year <= latest.year
        }
    )
    PoruchSheet(onDismiss) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(stringResource(R.string.birth_date), style = MaterialTheme.typography.titleLarge, color = colors.ink)
            DatePicker(state, title = null, showModeToggle = false, colors = poruchDatePickerColors())
            Row(verticalAlignment = Alignment.CenterVertically) {
                GhostButton(stringResource(R.string.close), { sheet.close() }, tone = colors.inkSecondary)
                Spacer(Modifier.weight(1f))
                PrimaryButton(stringResource(R.string.apply), {
                    val picked = state.selectedDateMillis?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalDate() }
                    if (picked != null) sheet.close { onPicked(picked) } else sheet.close()
                })
            }
        }
    }
}
