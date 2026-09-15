package app.poruch.android.feature.home

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.Event

/** Головна: плани, сьогодні і все поруч з даних, які вже завантажила мапа. Малює [HomeState], шле [HomeIntent]. */
@Composable
fun HomeScreen(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        // Без statusBarsPadding: відступ бере хедер, інакше над градієнтом холодна смуга.
        Modifier.fillMaxSize().background(colors.canvas).verticalScroll(rememberScrollState())
            .padding(bottom = 120.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.xxl)
    ) {
        Header(state, onIntent)

        // Поки шукають, дайджест сховано.
        if (!state.searching) {
            if (!state.signedIn) BannerCard(
                stringResource(R.string.guest_title), stringResource(R.string.guest_home_hint),
                { onIntent(HomeIntent.OpenProfile) }, Modifier.padding(horizontal = Spacing.page), PoruchIcons.lock
            ) else {
                // Запити вище за плани: на них чекає інша людина.
                if (state.requests.isNotEmpty()) RequestsSection(state.requests, onIntent)
                PlansSection(state.plans, onIntent)
            }
        }

        when {
            state.isEmpty && state.loading -> Box(
                Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center
            ) { CircularProgressIndicator(color = colors.ink) }

            // Порожній пошук і порожня околиця ведуть до різних дій.
            state.isEmpty -> EmptyState(
                if (state.searching) PoruchIcons.search else Icons.Outlined.Explore,
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
                // Каталог живе на мапі, головна лише каже, який він завбільшки.
                if (state.rest.isNotEmpty()) AllEventsRow(state.totalFound) { onIntent(HomeIntent.OpenMap) }
            }
        }

        if (!state.searching) BannerCard(
            stringResource(R.string.create_banner_title), stringResource(R.string.create_banner_subtitle),
            { onIntent(HomeIntent.CreateEvent) }, Modifier.padding(horizontal = Spacing.page)
        )
    }
}

// Головна — дайджест, а не каталог: далі краще на мапу.
private const val TODAY_LIMIT = 5
private const val PLANS_LIMIT = 8
/** Скільки результатів пошуку показує головна. */
private const val RESULTS_LIMIT = 12

@Composable
private fun Header(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        // Фон перед відступом: градієнт під смугою статусу, текст під нею.
        Modifier.fillMaxWidth().background(heroGradient()).statusBarsPadding()
            .padding(horizontal = Spacing.page, vertical = Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(stringResource(R.string.home_title), style = MaterialTheme.typography.displaySmall, color = colors.ink)
                // Що означає «поруч»: місто зі списку чи область на мапі.
                Text(
                    if (state.customArea) stringResource(R.string.home_subtitle_area)
                    else stringResource(R.string.home_subtitle, state.cityName),
                    style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary
                )
            }
            IconPill(PoruchIcons.person, stringResource(R.string.profile)) { onIntent(HomeIntent.OpenProfile) }
        }
        PoruchSearchField(
            state.searchText, { onIntent(HomeIntent.Search(it)) }, stringResource(R.string.search_placeholder)
        )
        // Поки шукають, ці дії сховано.
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

/** Мої події, де хтось проситься. Тап веде на подію: відповідають там, дивлячись на неї. */
@Composable
private fun RequestsSection(requests: List<PendingRequests>, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.padding(horizontal = Spacing.page).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            SectionHeader(stringResource(R.string.requests_home_section))
            Text(stringResource(R.string.requests_home_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        requests.forEach { (event, count) ->
            val label = pluralStringResource(R.plurals.requests_count, count, count)
            Row(
                Modifier.fillMaxWidth()
                    .semantics(mergeDescendants = true) { contentDescription = "${event.title}, $label"; role = Role.Button }
                    .pressable { onIntent(HomeIntent.OpenEvent(event.id)) }.cardSurface().padding(Spacing.lg),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        event.title, style = MaterialTheme.typography.titleSmall, color = colors.ink,
                        maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                    Text(label, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                }
                StatusBadge(count.toString(), BadgeTone.Accent)
                Icon(Icons.AutoMirrored.Outlined.ArrowForward, null, Modifier.size(16.dp), tint = colors.inkSecondary)
            }
        }
    }
}

/** Кількість подій в області і перехід до каталогу. */
@Composable
private fun AllEventsRow(totalFound: Int, onClick: () -> Unit) {
    val colors = Poruch.colors
    val label = stringResource(R.string.all_events_row_a11y, totalFound)
    Row(
        Modifier.padding(horizontal = Spacing.page).fillMaxWidth()
            .semantics(mergeDescendants = true) { contentDescription = label; role = Role.Button }
            .pressable(onClick = onClick).cardSurface().padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.all_events_section), style = MaterialTheme.typography.titleSmall, color = colors.ink)
            Text(stringResource(R.string.all_events_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        Text(totalFound.toString(), style = MaterialTheme.typography.titleLarge, color = colors.ink)
        Icon(Icons.AutoMirrored.Outlined.ArrowForward, null, Modifier.size(16.dp), tint = colors.inkSecondary)
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
            // Рекомендація каже, чому вона рекомендація.
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
