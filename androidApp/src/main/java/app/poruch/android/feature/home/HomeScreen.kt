package app.poruch.android.feature.home

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.Event

/**
 * Home answers «what is on this week» from data the map already loaded: the plans you joined,
 * what starts today, and everything else nearby. It renders [HomeState] and emits [HomeIntent];
 * it neither knows the store nor where its taps navigate to.
 */
@Composable
fun HomeScreen(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        // Без statusBarsPadding: відступ під смугу статусу бере на себе хедер, інакше вона
        // лишається кольором полотна, і над теплим градієнтом з'являється холодна смуга.
        Modifier.fillMaxSize().background(colors.canvas).verticalScroll(rememberScrollState())
            .padding(bottom = 120.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.xxl)
    ) {
        Header(state, onIntent)

        // Поки шукають, дайджест мовчить: план на тиждень і добірка «для вас» — відповіді на інше
        // питання, ніж те, що людина щойно набрала.
        if (!state.searching) {
            if (!state.signedIn) BannerCard(
                stringResource(R.string.guest_title), stringResource(R.string.guest_home_hint),
                { onIntent(HomeIntent.OpenProfile) }, Modifier.padding(horizontal = Spacing.page), PoruchIcons.lock
            ) else PlansSection(state.plans, onIntent)

            CategoryRail(state.category, onIntent)
        }

        when {
            state.isEmpty && state.loading -> Box(
                Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center
            ) { CircularProgressIndicator(color = colors.ink) }

            state.isEmpty -> EmptyState(
                PoruchIcons.search,
                stringResource(if (state.searching) R.string.nothing_found else R.string.nothing_here),
                stringResource(if (state.searching) R.string.nothing_found_hint else R.string.nothing_here_hint),
                actionLabel = stringResource(R.string.find_on_map), onAction = { onIntent(HomeIntent.OpenMap) }
            )

            state.searching -> EventSection(
                stringResource(R.string.events_found, state.results.size),
                state.results.take(RESULTS_LIMIT), state, onIntent,
                actionLabel = if (state.results.size > RESULTS_LIMIT) stringResource(R.string.see_all_short) else null
            )

            else -> {
                if (state.suggested.isNotEmpty()) EventSection(
                    stringResource(R.string.picked_for_you), state.suggested, state, onIntent,
                    subtitle = stringResource(R.string.picked_for_you_hint)
                )
                if (state.today.isNotEmpty()) EventSection(
                    stringResource(R.string.today_in_city), state.today.take(TODAY_LIMIT), state, onIntent,
                    actionLabel = if (state.today.size > TODAY_LIMIT) stringResource(R.string.see_all_short) else null
                )
                if (state.rest.isNotEmpty()) EventSection(
                    stringResource(R.string.all_events_section), state.rest.take(REST_LIMIT), state, onIntent,
                    actionLabel = stringResource(R.string.see_all_short)
                )
            }
        }

        if (!state.searching) BannerCard(
            stringResource(R.string.create_banner_title), stringResource(R.string.create_banner_subtitle),
            { onIntent(HomeIntent.CreateEvent) }, Modifier.padding(horizontal = Spacing.page)
        )
    }
}

// Home is a digest, not a catalogue: past these counts the map is the better place to look.
private const val TODAY_LIMIT = 5
private const val REST_LIMIT = 8
private const val PLANS_LIMIT = 8
/** Скільки результатів показує головна. Далі краще на мапу: там область і фільтри. */
private const val RESULTS_LIMIT = 12

@Composable
private fun Header(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        // Фон перед відступом: тоді градієнт малюється й під смугою статусу, а текст лишається
        // під нею. Порядок тут — і є вся різниця.
        Modifier.fillMaxWidth().background(heroGradient()).statusBarsPadding()
            .padding(horizontal = Spacing.page, vertical = Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(stringResource(R.string.home_title), style = MaterialTheme.typography.displaySmall, color = colors.ink)
                Text(
                    stringResource(R.string.home_subtitle, state.cityName),
                    style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary
                )
            }
            IconPill(PoruchIcons.person, stringResource(R.string.profile)) { onIntent(HomeIntent.OpenProfile) }
        }
        PoruchSearchField(
            state.searchText, { onIntent(HomeIntent.Search(it)) }, stringResource(R.string.search_placeholder)
        )
        // Поки шукають, ці дві дії — не про це. Хрестик у полі повертає їх на місце.
        if (!state.searching) Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            PoruchChip(stringResource(R.string.create), true, { onIntent(HomeIntent.CreateEvent) }, PoruchIcons.plus)
            PoruchChip(stringResource(R.string.find_on_map), false, { onIntent(HomeIntent.OpenMap) }, PoruchIcons.map)
        }
    }
}

@Composable
private fun PlansSection(plans: List<Event>, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.padding(horizontal = Spacing.page).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        SectionHeader(stringResource(R.string.upcoming_for_you))
        if (plans.isEmpty()) Column(
            Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            Text(stringResource(R.string.no_plans_title), style = MaterialTheme.typography.titleSmall, color = colors.ink)
            Text(stringResource(R.string.no_plans_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        } else Row(
            Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            plans.take(PLANS_LIMIT).forEach { event ->
                EventTile(event, Modifier.width(220.dp)) { onIntent(HomeIntent.OpenEvent(event.id)) }
            }
        }
    }
}

@Composable
private fun CategoryRail(selected: String, onIntent: (HomeIntent) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.browse_categories), Modifier.padding(horizontal = Spacing.page))
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.md),
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            categories.forEach { category ->
                CategoryTile(category, selected == category) { onIntent(HomeIntent.PickCategory(category)) }
            }
        }
    }
}

@Composable
private fun EventSection(
    title: String, events: List<Event>, state: HomeState, onIntent: (HomeIntent) -> Unit,
    actionLabel: String? = null, subtitle: String? = null
) {
    val colors = Poruch.colors
    Column(
        Modifier.padding(horizontal = Spacing.page).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            SectionHeader(title, actionLabel = actionLabel, onAction = { onIntent(HomeIntent.OpenMap) })
            // A recommendation says why it is one; a list titled «для вас» with no reason is a
            // claim the reader has to take on trust.
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        events.forEach { event ->
            EventCard(
                event, saved = event.id in state.savedIds, waitlisted = event.id in state.waitlistedIds,
                onSave = { onIntent(HomeIntent.ToggleSaved(event.id)) }
            ) { onIntent(HomeIntent.OpenEvent(event.id)) }
        }
    }
}
