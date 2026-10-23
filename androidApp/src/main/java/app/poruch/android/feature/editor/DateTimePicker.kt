package app.poruch.android.feature.editor

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.SafetyRules
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneOffset

/**
 * День або година події в шторці на наших токенах — що саме, вирішує частина квитка, яку торкнули; [title] називає
 * поле, бо шторка його закриває. Системний `DatePickerDialog` був би зеленим і англійським.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateTimeSheet(
    initial: LocalDateTime, minimum: LocalDateTime?, title: String, time: Boolean, onDismiss: () -> Unit, onPicked: (LocalDateTime) -> Unit
) {
    val colors = Poruch.colors
    PoruchSheet(onDismiss) { sheet ->
        // Календар вищий за телефон у ландшафті й на великому шрифті: кнопки підтвердження мають бути досяжні.
        // Поля — лише в заголовку й кнопок: календарю Material потрібні всі 360 dp, інакше неділю обрізало краєм.
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(bottom = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(title, style = PoruchType.brandTitle2, color = colors.ink, modifier = Gutter.semantics { heading() })
            // Друга половина значення лишається як була: день не чіпає годину, і навпаки.
            val keptTime = LocalTime.of(initial.hour, initial.minute)
            if (!time) {
                val dateState = rememberDatePickerState(
                    initialSelectedDateMillis = initial.toLocalDate().atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli(),
                    selectableDates = object : SelectableDates {
                        // Минула дата для події недійсна; сервер її теж відхилить.
                        override fun isSelectableDate(utcTimeMillis: Long) =
                            utcTimeMillis >= (minimum ?: LocalDateTime.now()).toLocalDate().atStartOfDay()
                                .toInstant(ZoneOffset.UTC).toEpochMilli()
                    }
                )
                // Заголовок уже в шторці.
                // Перемикач на введення цифрами: гортати календар до весни довше, ніж набрати дату.
                DatePicker(dateState, title = null, showModeToggle = true, colors = poruchDatePickerColors())
                SheetActions(
                    confirm = stringResource(R.string.apply),
                    onConfirm = {
                        val date = dateState.selectedDateMillis?.let {
                            Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                        } ?: initial.toLocalDate()
                        sheet.close { onPicked(LocalDateTime.of(date, keptTime)) }
                    },
                    onDismiss = { sheet.close() }
                )
            } else {
                // 12 чи 24 години — як на телефоні людини, а не як у нас.
                val is24Hour = android.text.format.DateFormat.is24HourFormat(androidx.compose.ui.platform.LocalContext.current)
                val timeState = rememberTimePickerState(initialHour = keptTime.hour, initialMinute = keptTime.minute, is24Hour = is24Hour)
                Box(Modifier.fillMaxWidth().padding(vertical = Spacing.sm), contentAlignment = Alignment.Center) {
                    TimePicker(timeState, colors = poruchTimePickerColors())
                }
                SheetActions(
                    confirm = stringResource(R.string.apply),
                    onConfirm = { sheet.close { onPicked(LocalDateTime.of(initial.toLocalDate(), LocalTime.of(timeState.hour, timeState.minute))) } },
                    onDismiss = { sheet.close() }
                )
            }
        }
    }
}

/** Підвал кроку: далі — кнопка, назад — тихий підпис поруч. */
@Composable
private fun SheetActions(confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    Row(Gutter, verticalAlignment = Alignment.CenterVertically) {
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

/** Дата народження. Відкривається на році, коли народився той, кому щойно 18, і пізніше не дає обрати. Сервер перевіряє ще раз. */
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
        // Календар вищий за телефон у ландшафті й на великому шрифті: кнопки підтвердження мають бути досяжні.
        // Поля — лише в заголовку й кнопок: календарю Material потрібні всі 360 dp, інакше неділю обрізало краєм.
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(bottom = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(stringResource(R.string.birth_date), style = PoruchType.brandTitle2, color = colors.ink, modifier = Gutter)
            DatePicker(state, title = null, showModeToggle = false, colors = poruchDatePickerColors())
            Row(Gutter, verticalAlignment = Alignment.CenterVertically) {
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

/** Поля шторки для заголовка й кнопок; календар іде від краю до краю. */
private val Gutter = Modifier.padding(horizontal = Spacing.page)
