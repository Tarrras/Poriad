package app.poruch.android.feature.artist

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*

/**
 * Екран артиста: шапка з іменем і «Стежити», під нею найближчі події тими самими рядками, що видача пошуку. Порожньо —
 * «Поки нічого не заплановано»: підписка якраз для цього.
 */
@Composable
fun ArtistScreen(state: ArtistUiState, onIntent: (ArtistIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.page, vertical = Spacing.sm)) {
            Box(
                Modifier.minimumInteractiveComponentSize().size(40.dp).cardSurface(CircleShape, Elevation.card)
                    .pressable(onClick = { onIntent(ArtistIntent.Back) }),
                contentAlignment = Alignment.Center
            ) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back), Modifier.size(18.dp), tint = colors.ink) }
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding()
                .padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(state.name, style = PoruchType.serifDisplay, color = colors.ink)
                artistKindLabel(state.kind)?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary) }
                FollowPill(state.following, { onIntent(ArtistIntent.ToggleFollow) })
                Text(stringResource(R.string.follow_artist_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
            }
            when {
                state.loading && state.events.isEmpty() -> Box(Modifier.fillMaxWidth().padding(vertical = Spacing.section), Alignment.Center) { PoruchLoader() }
                state.events.isEmpty() -> EmptyState(
                    Icons.Outlined.EventBusy, stringResource(R.string.artist_empty_title), stringResource(R.string.artist_empty_hint)
                )
                else -> Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    SectionHeader(stringResource(R.string.artist_events_title))
                    GroupedRows {
                        state.events.forEachIndexed { position, event ->
                            if (position > 0) HairLine(Modifier.padding(start = ResultRowInset))
                            EventResultRow(event, waitlisted = event.id in state.waitlistedIds, withCity = true) {
                                onIntent(ArtistIntent.OpenEvent(event.id))
                            }
                        }
                    }
                }
            }
        }
    }
}
