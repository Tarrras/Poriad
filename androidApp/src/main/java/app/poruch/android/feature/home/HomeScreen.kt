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
import app.poruch.domain.ChatUnread
import app.poruch.domain.Event

/** Головна: плани, сьогодні і все поруч з даних, які вже завантажила мапа. Малює [HomeState], шле [HomeIntent]. */
@Composable
fun HomeScreen(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    PullToRefresh(state.refreshing, { onIntent(HomeIntent.Refresh) }, Modifier.fillMaxSize().background(colors.canvas)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(Spacing.section)
        ) {
            Header(state, onIntent)
            if (state.searching) SearchResults(state, onIntent) else {
                QuickActions(onIntent)
                if (!state.signedIn) BannerCard(
                    stringResource(R.string.guest_title), stringResource(R.string.guest_home_hint),
                    { onIntent(HomeIntent.OpenProfile) }, Modifier.padding(horizontal = Spacing.page), PoruchIcons.lock
                ) else {
                    // Запити й нові повідомлення вище за плани: на них чекає інша людина.
                    if (state.requests.isNotEmpty()) RequestsSection(state.requests, onIntent)
                    if (state.unread.isNotEmpty()) UnreadSection(state.unread, onIntent)
                    if (state.plans.isNotEmpty()) PlansSection(state.plans, onIntent)
                }
                when {
                    state.isEmpty && state.loading -> Box(
                        Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center
                    ) { CircularProgressIndicator(color = colors.ink) }
                    state.isEmpty -> EmptyState(
                        Icons.Outlined.Explore, stringResource(R.string.nothing_here), stringResource(R.string.nothing_here_hint),
                        actionLabel = stringResource(R.string.find_on_map), onAction = { onIntent(HomeIntent.OpenMap) }
                    )
                    else -> Digest(state, onIntent)
                }
                // Категорії нижче за дайджест: спершу що є, потім чим звузити. Тап відкриває мапу з фільтром.
                CategoryRail(onIntent)
                MoreRows(state, onIntent)
            }
        }
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
        Modifier.fillMaxWidth().padding(horizontal = Spacing.page).padding(top = Spacing.xl),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(stringResource(R.string.home_title), style = MaterialTheme.typography.displaySmall, color = colors.ink)
                // Що означає «поруч»: завжди ціле місто. «Шукати тут» на мапі головну не звужує.
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
    }
}

/** Плитки категорій від краю до краю, як ряд продуктів в Apple Store. */
@Composable
private fun CategoryRail(onIntent: (HomeIntent) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.browse_categories), Modifier.padding(horizontal = Spacing.page))
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            categories.forEach { key -> CategoryTile(key, selected = false) { onIntent(HomeIntent.OpenCategory(key)) } }
        }
    }
}

/** Дві дії на пів ширини: створити й дослідити. */
@Composable
private fun QuickActions(onIntent: (HomeIntent) -> Unit) {
    Row(Modifier.padding(horizontal = Spacing.page), horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        QuickActionCard(
            stringResource(R.string.home_organize), stringResource(R.string.create), PoruchIcons.plus,
            { onIntent(HomeIntent.CreateEvent) }, Modifier.weight(1f), filled = true
        )
        QuickActionCard(
            stringResource(R.string.home_explore), stringResource(R.string.on_map), PoruchIcons.map,
            { onIntent(HomeIntent.OpenMap) }, Modifier.weight(1f)
        )
    }
}

/** Дайджест: перша рекомендація — велика афіша, решта — горизонтальні стрічки. */
@Composable
private fun Digest(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val featured = state.suggested.firstOrNull() ?: state.today.firstOrNull()
    val suggested = state.suggested.filter { it.id != featured?.id }
    val today = state.today.filter { it.id != featured?.id }.take(TODAY_LIMIT)
    if (featured != null) Column(
        Modifier.padding(horizontal = Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        SectionHeader(stringResource(if (state.suggested.isEmpty()) R.string.today_in_city else R.string.picked_for_you))
        EventHeroCard(
            featured, stringResource(if (state.suggested.isEmpty()) R.string.today_eyebrow else R.string.picked_for_you_hint),
            saved = featured.id in state.savedIds, onSave = { onIntent(HomeIntent.ToggleSaved(featured.id)) }
        ) { onIntent(HomeIntent.OpenEvent(featured.id)) }
    }
    if (suggested.isNotEmpty()) Rail(stringResource(R.string.more_for_you), suggested, state, onIntent)
    if (today.isNotEmpty()) Rail(stringResource(R.string.today_in_city), today, state, onIntent, actionLabel = stringResource(R.string.see_all_short))
}

/** Горизонтальна стрічка широких карток; сусідня визирає з-за краю. */
@Composable
private fun Rail(title: String, events: List<Event>, state: HomeState, onIntent: (HomeIntent) -> Unit, actionLabel: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(title, Modifier.padding(horizontal = Spacing.page), actionLabel = actionLabel, onAction = { onIntent(HomeIntent.OpenMap) })
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            events.forEach { event ->
                EventRailCard(
                    event, saved = event.id in state.savedIds, onSave = { onIntent(HomeIntent.ToggleSaved(event.id)) }
                ) { onIntent(HomeIntent.OpenEvent(event.id)) }
            }
        }
    }
}

/** Результати пошуку одним списком. */
@Composable
private fun SearchResults(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    state.cityMatch?.let { city ->
        BannerCard(
            stringResource(R.string.home_switch_city, city.city),
            stringResource(R.string.home_switch_city_hint, state.cityName),
            onClick = { onIntent(HomeIntent.SwitchCity(city)) },
            modifier = Modifier.padding(horizontal = Spacing.page), icon = PoruchIcons.pin
        )
    }
    when {
        state.isEmpty && state.busy -> Box(
            Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center
        ) { CircularProgressIndicator(color = colors.ink) }
        state.isEmpty -> EmptyState(
            PoruchIcons.search, stringResource(R.string.nothing_found), stringResource(R.string.nothing_found_hint),
            actionLabel = stringResource(R.string.find_on_map), onAction = { onIntent(HomeIntent.OpenMap) }
        )
        else -> Column(
            Modifier.padding(horizontal = Spacing.page).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            SectionHeader(
                stringResource(R.string.events_found, maxOf(state.resultsTotal, state.results.size)),
                actionLabel = if (state.resultsTotal > RESULTS_LIMIT) stringResource(R.string.see_all_short) else null,
                onAction = { onIntent(HomeIntent.ShowResultsOnMap) }
            )
            state.results.take(RESULTS_LIMIT).forEach { event ->
                EventCard(
                    event, saved = event.id in state.savedIds, waitlisted = event.id in state.waitlistedIds,
                    onSave = { onIntent(HomeIntent.ToggleSaved(event.id)) }
                ) { onIntent(HomeIntent.OpenEvent(event.id)) }
            }
        }
    }
}

/** Каталог і створення одним груповим списком: головна лише каже, куди далі. */
@Composable
private fun MoreRows(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    Column(Modifier.padding(horizontal = Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.home_next))
        GroupedRows {
            LinkRow(
                PoruchIcons.map, stringResource(R.string.all_events_section), stringResource(R.string.all_events_hint),
                { onIntent(HomeIntent.OpenMap) }, value = state.totalFound.takeIf { it > 0 }?.toString()
            )
            HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
            LinkRow(
                PoruchIcons.sparkle, stringResource(R.string.create_banner_title), stringResource(R.string.create_banner_subtitle),
                { onIntent(HomeIntent.CreateEvent) }
            )
        }
    }
}

@Composable
private fun PlansSection(plans: List<Event>, onIntent: (HomeIntent) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.upcoming_for_you), Modifier.padding(horizontal = Spacing.page))
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md)
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

/** Чати з непрочитаним: назва події, хто й що написав останнім. Тап веде одразу в чат. */
@Composable
private fun UnreadSection(unread: List<ChatUnread>, onIntent: (HomeIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.padding(horizontal = Spacing.page).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            SectionHeader(stringResource(R.string.chat_home_section))
            Text(stringResource(R.string.chat_home_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        unread.forEach { chat ->
            val count = pluralStringResource(R.plurals.chat_unread_count, chat.unread, chat.unread)
            val preview = stringResource(R.string.chat_preview, chat.lastAuthorName.ifBlank { stringResource(R.string.chat_member) }, chat.lastBody)
            Row(
                Modifier.fillMaxWidth()
                    .semantics(mergeDescendants = true) { contentDescription = "${chat.eventTitle}, $count. $preview"; role = Role.Button }
                    .pressable { onIntent(HomeIntent.OpenChat(chat.eventId)) }.cardSurface().padding(Spacing.lg),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(chat.eventTitle, style = MaterialTheme.typography.titleSmall, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(preview, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                StatusBadge(chat.unread.toString(), BadgeTone.Accent)
            }
        }
    }
}
