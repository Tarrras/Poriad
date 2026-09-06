package app.poruch.android.feature.editor

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.DialogProperties
import app.poruch.android.R
import app.poruch.android.ui.*
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneOffset

/**
 * Date then time, in one flow, painted from our own tokens.
 *
 * The platform `DatePickerDialog` renders in the system accent and system language, which put a
 * green English dialog in the middle of a Ukrainian paper-and-ink app. Material 3's composable
 * picker takes our colour scheme, and the app's locale gives it Ukrainian month names.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateTimeSheet(initial: LocalDateTime, minimum: LocalDateTime?, onDismiss: () -> Unit, onPicked: (LocalDateTime) -> Unit) {
    val colors = Poruch.colors
    var date by remember { mutableStateOf<LocalDate?>(null) }

    if (date == null) {
        val dateState = rememberDatePickerState(
            initialSelectedDateMillis = initial.toLocalDate().atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli(),
            selectableDates = object : SelectableDates {
                // A past date is never valid for an event, and the server rejects it anyway.
                override fun isSelectableDate(utcTimeMillis: Long) =
                    utcTimeMillis >= (minimum ?: LocalDateTime.now()).toLocalDate().atStartOfDay()
                        .toInstant(ZoneOffset.UTC).toEpochMilli()
            }
        )
        DatePickerDialog(
            onDismissRequest = onDismiss,
            properties = DialogProperties(usePlatformDefaultWidth = true),
            colors = DatePickerDefaults.colors(containerColor = colors.surface),
            shape = Radius.lg,
            confirmButton = {
                GhostButton(stringResource(R.string.next), {
                    date = dateState.selectedDateMillis?.let {
                        Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                    } ?: initial.toLocalDate()
                })
            },
            dismissButton = { GhostButton(stringResource(R.string.close), onDismiss, tone = colors.inkSecondary) }
        ) {
            DatePicker(dateState, colors = poruchDatePickerColors(), showModeToggle = false)
        }
    } else {
        val timeState = rememberTimePickerState(initialHour = initial.hour, initialMinute = initial.minute, is24Hour = true)
        AlertDialog(
            onDismissRequest = onDismiss,
            containerColor = colors.surface,
            shape = Radius.lg,
            title = { Text(stringResource(R.string.date), style = MaterialTheme.typography.titleLarge, color = colors.ink) },
            text = {
                Box(Modifier.fillMaxWidth(), contentAlignment = androidx.compose.ui.Alignment.Center) {
                    TimePicker(timeState, colors = poruchTimePickerColors())
                }
            },
            confirmButton = {
                GhostButton(stringResource(R.string.apply), {
                    onPicked(LocalDateTime.of(date, LocalTime.of(timeState.hour, timeState.minute)))
                })
            },
            dismissButton = { GhostButton(stringResource(R.string.close), onDismiss, tone = colors.inkSecondary) }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun poruchDatePickerColors() = Poruch.colors.let { colors ->
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
