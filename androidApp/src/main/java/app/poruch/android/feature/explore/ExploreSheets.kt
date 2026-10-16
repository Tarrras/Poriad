package app.poruch.android.feature.explore

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.domain.EventCategory
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.CityResult
import app.poruch.domain.HomeLocation
import app.poruch.shared.DateFilter

/**
 * Кожен вибір діє одразу, як чипи над мапою: за шторкою видно, що змінилось, а кнопка каже, скільки знайдеться.
 * Скасування не треба — вибір знімається тим самим тапом, «Скинути» прибирає все.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FilterSheet(state: ExploreState, onIntent: (ExploreIntent) -> Unit, onDone: () -> Unit) {
    val colors = Poruch.colors
    val screen = state.screen
    // «Показати» прикріплене під прокруткою, як на iOS: з плитками категорій вміст вищий за екран, і кнопка йшла за край.
    Column(Modifier.padding(bottom = Spacing.section)) {
    Column(
        Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        // Заголовок шторки — заголовок, а не надрядок: інакше він менший за секції під ним.
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.filters), style = PoruchType.brandTitle2,
                color = colors.ink, modifier = Modifier.weight(1f)
            )
            if (screen.activeFilters > 0) GhostButton(
                stringResource(R.string.reset_filters),
                {
                    if (screen.dateFilter != DateFilter.ANY) onIntent(ExploreIntent.PickDate(DateFilter.ANY))
                    if (screen.category != null) onIntent(ExploreIntent.PickCategory(null))
                    if (screen.onlyAvailable) onIntent(ExploreIntent.OnlyAvailable(false))
                },
                tone = colors.inkSecondary
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            SectionHeader(stringResource(R.string.date))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                dateFilters.forEach { (key, label) ->
                    PoruchChip(stringResource(label), screen.dateFilter == key, {
                        onIntent(ExploreIntent.PickDate(if (screen.dateFilter == key) DateFilter.ANY else key))
                    })
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            SectionHeader(stringResource(R.string.categories))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                // Ті самі плитки, що в шторці мапи й у редакторі: жанр обирають однаково скрізь. Повторний тап знімає вибір.
                categories.forEach { value ->
                    CategoryTile(value, screen.category == value) { onIntent(ExploreIntent.ToggleCategory(value)) }
                }
            }
        }
        // Та сама назва, що в чипа над мапою: один фільтр — одне ім'я, а що він робить — підписом.
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.from_people), style = MaterialTheme.typography.bodyLarge, color = colors.ink)
                Text(stringResource(R.string.from_people_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
            }
            PoruchSwitch(screen.onlyAvailable, { onIntent(ExploreIntent.OnlyAvailable(it)) })
        }
    }
        // Кнопка каже, що вийде: «Показати 23 події», а не «Готово» навмання.
        val result = when {
            screen.loading -> stringResource(R.string.searching)
            screen.listCount == 0 -> stringResource(R.string.show_nothing)
            else -> pluralStringResource(R.plurals.show_events, screen.listCount, screen.listCount)
        }
        PrimaryButton(
            result, onDone,
            Modifier.fillMaxWidth().padding(horizontal = Spacing.page).padding(top = Spacing.lg),
            loading = screen.loading
        )
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
                    stringResource(R.string.city_search), style = PoruchType.brandTitle2,
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
