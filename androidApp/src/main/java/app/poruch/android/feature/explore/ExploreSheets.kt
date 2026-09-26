package app.poruch.android.feature.explore

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.CityResult
import app.poruch.domain.HomeLocation
import app.poruch.shared.ALL_CATEGORIES
import app.poruch.shared.DateFilter

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FilterSheet(state: ExploreState, onIntent: (ExploreIntent) -> Unit, onDone: () -> Unit) {
    val colors = Poruch.colors
    // Вибір накопичується і летить на сервер один раз по «Застосувати»: проміжних результатів за шторкою не видно.
    var date by remember(state.dateFilter) { mutableStateOf(state.dateFilter) }
    var category by remember(state.category) { mutableStateOf(state.category) }
    var available by remember(state.onlyAvailable) { mutableStateOf(state.onlyAvailable) }
    val apply = {
        if (date != state.dateFilter) onIntent(ExploreIntent.PickDate(date))
        if (category != state.category) onIntent(ExploreIntent.PickCategory(category))
        if (available != state.onlyAvailable) onIntent(ExploreIntent.OnlyAvailable(available))
        onDone()
    }
    Column(
        Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        // Заголовок шторки — заголовок, а не надрядок: інакше він менший за секції під ним.
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.filters), style = MaterialTheme.typography.titleLarge,
                color = colors.ink, modifier = Modifier.weight(1f)
            )
            GhostButton(
                stringResource(R.string.reset_filters),
                { date = DateFilter.ANY; category = ALL_CATEGORIES; available = false },
                tone = colors.inkSecondary
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            SectionHeader(stringResource(R.string.date))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                dateFilters.forEach { (key, label) ->
                    PoruchChip(stringResource(label), date == key, { date = if (date == key) DateFilter.ANY else key })
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            SectionHeader(stringResource(R.string.categories))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                PoruchChip(stringResource(R.string.all), category == ALL_CATEGORIES, { category = ALL_CATEGORIES })
                categories.forEach { value ->
                    PoruchChip(
                        stringResource(categoryLabel(value)), category == value,
                        { category = if (category == value) ALL_CATEGORIES else value }, dot = value
                    )
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                // Перемикачу потрібне ціле речення, а не текст чипа.
                stringResource(R.string.only_available), style = MaterialTheme.typography.bodyLarge,
                color = colors.ink, modifier = Modifier.weight(1f)
            )
            PoruchSwitch(available, { available = it })
        }
        PrimaryButton(stringResource(R.string.apply), apply, Modifier.fillMaxWidth())
    }
}

/** Вибір міста: спільний для мапи й головної. [suggestions] — відповідь геопошуку на набране в [onQuery]. */
@Composable
internal fun CitySearchSheet(
    current: String, suggestions: List<CityResult>,
    onQuery: (String) -> Unit, onPick: (CityResult) -> Unit, onClose: () -> Unit
) {
    val colors = Poruch.colors
    var query by rememberSaveable { mutableStateOf("") }
    // Шторка існує заради одного поля, тож фокусує його одразу.
    val field = remember { FocusRequester() }
    LaunchedEffect(Unit) { field.requestFocus() }
    LaunchedEffect(query) { onQuery(query) }
    PoruchSheet(onClose) { sheet ->
        Column(
            // Поле піднімає клавіатуру, шторка стає на неї.
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.city_search), style = MaterialTheme.typography.titleLarge,
                    color = colors.ink, modifier = Modifier.weight(1f)
                )
                GhostButton(stringResource(R.string.close), { sheet.close() }, tone = colors.inkSecondary)
            }
            PoruchField(query, { query = it }, stringResource(R.string.city), focusRequester = field)
            // Поки нічого не набрано, пропонуємо міста, де події справді є.
            if (query.isBlank()) FlowRow(
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                HomeLocation.covered.forEach { place ->
                    PoruchChip(place.city, place.city == current, {
                        sheet.close { onPick(CityResult(place.city, place.latitude, place.longitude)) }
                    })
                }
            }
            // Гортаються лише підказки, щоб остання не ховалась під клавіатурою.
            Column(Modifier.heightIn(max = SUGGESTION_BAND).verticalScroll(rememberScrollState())) {
                suggestions.take(CITY_SUGGESTIONS).forEach { city ->
                    Row(
                        Modifier.fillMaxWidth().clip(Radius.sm)
                            .clickable { sheet.close { onPick(city) } }
                            .padding(vertical = Spacing.md, horizontal = Spacing.sm),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(PoruchIcons.pin, null, Modifier.size(18.dp), tint = colors.brand)
                        Text(city.name, style = MaterialTheme.typography.bodyLarge, color = colors.ink)
                    }
                }
            }
        }
    }
}

/** Скільки підказок міст показуємо. */
private const val CITY_SUGGESTIONS = 6

/** Смуга підказок над клавіатурою; довший список гортається всередині. */
private val SUGGESTION_BAND = 300.dp
