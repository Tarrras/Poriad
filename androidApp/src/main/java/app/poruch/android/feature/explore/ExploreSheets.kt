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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.shared.ALL_CATEGORIES
import app.poruch.shared.DateFilter

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FilterSheet(state: ExploreState, onIntent: (ExploreIntent) -> Unit, onDone: () -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        // The sheet's own title is a title, not an overline: at label size it was smaller than the
        // section headings underneath it, which inverted the hierarchy of the whole sheet.
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.filters), style = MaterialTheme.typography.titleLarge,
                color = colors.ink, modifier = Modifier.weight(1f)
            )
            GhostButton(
                stringResource(R.string.reset_filters), { onIntent(ExploreIntent.ResetFilters) },
                tone = colors.inkSecondary
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            SectionHeader(stringResource(R.string.date))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                dateFilters.forEach { (key, label) ->
                    PoruchChip(stringResource(label), state.dateFilter == key, { onIntent(ExploreIntent.PickDate(key)) })
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            SectionHeader(stringResource(R.string.categories))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                PoruchChip(stringResource(R.string.all), state.category == ALL_CATEGORIES, { onIntent(ExploreIntent.PickCategory(ALL_CATEGORIES)) })
                categories.forEach { category ->
                    PoruchChip(
                        stringResource(categoryLabel(category)), state.category == category,
                        { onIntent(ExploreIntent.PickCategory(category)) }, dot = category
                    )
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                // The chip beside the map says «Є місця»; a switch needs the whole sentence.
                stringResource(R.string.only_available), style = MaterialTheme.typography.bodyLarge,
                color = colors.ink, modifier = Modifier.weight(1f)
            )
            Switch(
                state.onlyAvailable, { onIntent(ExploreIntent.OnlyAvailable(it)) },
                colors = SwitchDefaults.colors(checkedTrackColor = colors.brand, checkedThumbColor = colors.onBrand)
            )
        }
        PrimaryButton(stringResource(R.string.apply), onDone, Modifier.fillMaxWidth())
    }
}

@Composable
internal fun CitySearchSheet(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    var query by rememberSaveable { mutableStateOf("") }
    val close = { onIntent(ExploreIntent.ShowSheet(ExploreSheet.NONE)) }
    LaunchedEffect(query) { onIntent(ExploreIntent.SearchCity(query)) }
    PoruchSheet(close) { sheet ->
        Column(
            // The field pulls the keyboard up over the sheet, so the sheet stands on it.
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
            PoruchField(query, { query = it }, stringResource(R.string.city))
            // The title and the field stay put; only the answers scroll, so the last suggestion is
            // never stranded under the keyboard the field itself brought up.
            Column(Modifier.heightIn(max = SUGGESTION_BAND).verticalScroll(rememberScrollState())) {
                state.cities.take(CITY_SUGGESTIONS).forEach { city ->
                    Row(
                        Modifier.fillMaxWidth().clip(Radius.sm)
                            .clickable { sheet.close { onIntent(ExploreIntent.SelectCity(city)) } }
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

/** A geocoder answers with everything named after a city; six is as far as anyone reads. */
private const val CITY_SUGGESTIONS = 6

/** The band the suggestions occupy above the keyboard; a longer answer scrolls inside it. */
private val SUGGESTION_BAND = 300.dp
