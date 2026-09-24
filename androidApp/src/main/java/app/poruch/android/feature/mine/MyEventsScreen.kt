package app.poruch.android.feature.mine

import androidx.compose.foundation.background
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*

@Composable
fun MyEventsScreen(state: MyEventsState, onIntent: (MyEventsIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas)) {
        Column(
            Modifier.statusBarsPadding().padding(top = Spacing.xl, bottom = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Row(Modifier.padding(horizontal = Spacing.page), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Text(stringResource(R.string.my_events), style = MaterialTheme.typography.displaySmall, color = colors.ink)
                    Text(
                        stringResource(if (state.signedIn) R.string.my_events_subtitle else R.string.guest_empty),
                        style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary
                    )
                }
                // Гостю оновлювати нічого: списки належать акаунту.
                if (state.signedIn) IconPill(Icons.Outlined.Refresh, stringResource(R.string.refresh)) { onIntent(MyEventsIntent.Refresh) }
            }
            if (state.signedIn) Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                MyEventsTab.entries.forEach { tab ->
                    // Обраний чип завжди на виду: і після тапу по напівсхованому, і коли вкладку
                    // відкрили знову, а прокрутка рядка почалася з нуля.
                    val reveal = remember { BringIntoViewRequester() }
                    if (state.tab == tab) LaunchedEffect(Unit) { reveal.bringIntoView() }
                    Box(Modifier.bringIntoViewRequester(reveal)) {
                        PoruchChip(
                            stringResource(tab.label), state.tab == tab, { onIntent(MyEventsIntent.PickTab(tab)) },
                            badge = state.unreadByTab[tab] ?: 0
                        )
                    }
                }
            }
        }
        // Гостю оновлювати нічого, тож і потягу нема.
        if (!state.signedIn) EmptyState(
            PoruchIcons.lock, stringResource(R.string.guest_empty), stringResource(R.string.guest_description),
            Modifier.padding(top = Spacing.section), stringResource(R.string.login), { onIntent(MyEventsIntent.SignIn) }
        ) else PullToRefresh(state.refreshing, { onIntent(MyEventsIntent.Refresh) }, Modifier.fillMaxSize()) {
            when {
                // Порожній стан теж прокручується: інакше потяг не має за що зачепитись.
                state.visible.isEmpty() -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    if (state.loading) Box(
                        Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center
                    ) { CircularProgressIndicator(color = colors.ink) }
                    else EmptyState(
                        PoruchIcons.calendar, stringResource(R.string.my_events_empty),
                        stringResource(R.string.my_events_empty_hint), Modifier.padding(top = Spacing.section)
                    )
                }

                // Один груповий список компактних рядків: тут переглядають своє, а не обирають чуже.
                else -> Column(
                    Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                        .tabBarClearance().padding(start = Spacing.page, end = Spacing.page, top = Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.xxl)
                ) {
                    GroupedRows {
                        state.visible.forEachIndexed { index, event ->
                            EventRow(event, unread = state.unread[event.id] ?: 0) { onIntent(MyEventsIntent.OpenEvent(event.id)) }
                            if (index < state.visible.lastIndex) HairLine(Modifier.padding(start = Spacing.lg + 60.dp + Spacing.md))
                        }
                    }
                    GroupedRows {
                        LinkRow(
                            PoruchIcons.sparkle, stringResource(R.string.create_banner_title),
                            stringResource(R.string.create_banner_subtitle), { onIntent(MyEventsIntent.CreateEvent) }
                        )
                    }
                }
            }
        }
    }
}

private val MyEventsTab.label: Int
    get() = when (this) {
        MyEventsTab.ATTENDING -> R.string.attending
        MyEventsTab.ORGANIZING -> R.string.organizing
        MyEventsTab.SAVED -> R.string.saved
        MyEventsTab.ENDED -> R.string.ended
    }
