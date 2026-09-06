package app.poruch.android.feature.mine

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
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
        Column(Modifier.background(colors.canvasTint).statusBarsPadding()) {
            PageHeader(stringResource(R.string.my_events), trailing = {
                IconPill(Icons.Outlined.Refresh, stringResource(R.string.refresh)) { onIntent(MyEventsIntent.Refresh) }
            })
            if (state.signedIn) Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.page, vertical = Spacing.sm),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                MyEventsTab.entries.forEach { tab ->
                    PoruchChip(stringResource(tab.label), state.tab == tab, { onIntent(MyEventsIntent.PickTab(tab)) })
                }
            }
            Spacer(Modifier.height(Spacing.md))
        }
        when {
            !state.signedIn -> EmptyState(
                PoruchIcons.lock, stringResource(R.string.guest_empty), stringResource(R.string.guest_description),
                Modifier.padding(top = Spacing.section), stringResource(R.string.login), { onIntent(MyEventsIntent.SignIn) }
            )

            state.visible.isEmpty() && state.loading -> Box(
                Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center
            ) { CircularProgressIndicator(color = colors.ink) }

            state.visible.isEmpty() -> EmptyState(
                PoruchIcons.calendar, stringResource(R.string.my_events_empty),
                stringResource(R.string.my_events_empty_hint), Modifier.padding(top = Spacing.section)
            )

            else -> LazyColumn(
                contentPadding = PaddingValues(start = Spacing.page, end = Spacing.page, top = Spacing.sm, bottom = 120.dp),
                verticalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                item {
                    BannerCard(
                        stringResource(R.string.create_banner_title), stringResource(R.string.create_banner_subtitle),
                        { onIntent(MyEventsIntent.CreateEvent) }
                    )
                }
                items(state.visible, key = { it.id }) { event ->
                    EventCard(event, saved = event.id in state.savedIds, waitlisted = event.id in state.waitlistedIds) {
                        onIntent(MyEventsIntent.OpenEvent(event.id))
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
    }
