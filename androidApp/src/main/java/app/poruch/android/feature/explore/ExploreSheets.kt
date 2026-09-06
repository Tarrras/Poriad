package app.poruch.android.feature.explore

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
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
internal fun FilterSheet(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        SectionHeader(
            stringResource(R.string.filters),
            actionLabel = stringResource(R.string.reset_filters),
            onAction = { onIntent(ExploreIntent.ResetFilters) }
        )
        Text(stringResource(R.string.date), style = MaterialTheme.typography.titleSmall, color = colors.inkSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            dateFilters.forEach { (key, label) ->
                PoruchChip(stringResource(label), state.dateFilter == key, { onIntent(ExploreIntent.PickDate(key)) })
            }
        }
        Text(stringResource(R.string.categories), style = MaterialTheme.typography.titleSmall, color = colors.inkSecondary)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            PoruchChip(stringResource(R.string.all), state.category == ALL_CATEGORIES, { onIntent(ExploreIntent.PickCategory(ALL_CATEGORIES)) })
            categories.forEach { category ->
                PoruchChip(
                    stringResource(categoryLabel(category)), state.category == category,
                    { onIntent(ExploreIntent.PickCategory(category)) }, dot = category
                )
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.available), style = MaterialTheme.typography.bodyLarge,
                color = colors.ink, modifier = Modifier.weight(1f)
            )
            Switch(
                state.onlyAvailable, { onIntent(ExploreIntent.OnlyAvailable(it)) },
                colors = SwitchDefaults.colors(checkedTrackColor = colors.brand, checkedThumbColor = colors.onBrand)
            )
        }
        PrimaryButton(
            stringResource(R.string.apply), { onIntent(ExploreIntent.ShowSheet(ExploreSheet.NONE)) }, Modifier.fillMaxWidth()
        )
    }
}

@Composable
internal fun CitySearchDialog(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    var query by rememberSaveable { mutableStateOf("") }
    val close = { onIntent(ExploreIntent.ShowSheet(ExploreSheet.NONE)) }
    LaunchedEffect(query) { onIntent(ExploreIntent.SearchCity(query)) }
    AlertDialog(
        onDismissRequest = close, containerColor = colors.surface, shape = Radius.lg,
        title = { Text(stringResource(R.string.city_search), style = MaterialTheme.typography.titleLarge, color = colors.ink) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                PoruchField(query, { query = it }, stringResource(R.string.city))
                state.cities.take(CITY_SUGGESTIONS).forEach { city ->
                    Row(
                        Modifier.fillMaxWidth().clip(Radius.sm).clickable { onIntent(ExploreIntent.SelectCity(city)) }.padding(Spacing.md),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(PoruchIcons.pin, null, Modifier.size(18.dp), tint = colors.brand)
                        Text(city.name, style = MaterialTheme.typography.bodyLarge, color = colors.ink)
                    }
                }
            }
        },
        confirmButton = { GhostButton(stringResource(R.string.close), close) }
    )
}

/** More than this and the dialog outgrows the keyboard-free part of the screen. */
private const val CITY_SUGGESTIONS = 6
