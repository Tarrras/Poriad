package app.poruch.android.feature.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.Follow
import app.poruch.domain.FollowKind

/**
 * Підписки окремим екраном: список може бути довгим, і в профілі йому не місце. Рядок відкриває заклад на мапі чи
 * картку організатора, «Не стежити» — відписка.
 */
@Composable
fun FollowsScreen(state: FollowsState, onIntent: (FollowsIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
        Column {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = Spacing.page, vertical = Spacing.sm),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                Box(
                    Modifier.minimumInteractiveComponentSize().size(40.dp).cardSurface(CircleShape, Elevation.card)
                        .pressable(onClick = { onIntent(FollowsIntent.Back) }),
                    contentAlignment = Alignment.Center
                ) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back), Modifier.size(18.dp), tint = colors.ink) }
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.follows_title), style = MaterialTheme.typography.titleMedium, color = colors.ink)
                    Text(stringResource(R.string.follows_subtitle), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                }
            }
            HorizontalDivider(color = colors.hairline)
        }
        if (state.follows.isEmpty()) EmptyState(
            Icons.Outlined.NotificationsNone, stringResource(R.string.follows_empty_title), stringResource(R.string.follows_empty_hint),
            Modifier.padding(top = Spacing.section)
        ) else Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding()
                .padding(horizontal = Spacing.page, vertical = Spacing.lg)
        ) {
            GroupedRows {
                state.follows.forEachIndexed { index, follow ->
                    if (index > 0) HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                    FollowRow(follow, { onIntent(FollowsIntent.Open(follow)) }, { onIntent(FollowsIntent.Unfollow(follow)) })
                }
            }
        }
    }
    // Картка організатора з підписки: лише «Стежити», решту дій дає картка в самій події.
    state.person?.let { person ->
        PersonSheet(
            person, isMe = false, onDismiss = { onIntent(FollowsIntent.ClosePerson) }, onBlock = null,
            follow = FollowAction(state.follows.any { it.kind == FollowKind.ORGANIZER && it.targetId == person.userId }) {
                onIntent(FollowsIntent.ToggleFollowPerson(person.userId, person.profile?.name.orEmpty()))
            }
        )
    }
}

@Composable
private fun FollowRow(follow: Follow, onOpen: () -> Unit, onUnfollow: () -> Unit) {
    val colors = Poruch.colors
    val count = pluralStringResource(R.plurals.place_upcoming, follow.upcoming, follow.upcoming)
    val caption = when (follow.kind) {
        FollowKind.PLACE -> if (follow.city.isBlank()) count else stringResource(R.string.follows_place_caption, follow.city, count)
        FollowKind.ORGANIZER -> stringResource(R.string.follows_organizer_caption, count)
    }
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onOpen)
            .padding(start = Spacing.lg, top = Spacing.md, bottom = Spacing.md, end = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        when (follow.kind) {
            FollowKind.PLACE -> Box(Modifier.size(40.dp).background(colors.surfaceMuted, Radius.xs), contentAlignment = Alignment.Center) {
                Icon(PoruchIcons.pin, null, Modifier.size(20.dp), tint = colors.ink)
            }
            FollowKind.ORGANIZER -> Avatar(follow.name, follow.avatarUrl, 40.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(follow.name, style = MaterialTheme.typography.titleSmall, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(caption, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        GhostButton(stringResource(R.string.unfollow), onUnfollow, tone = colors.inkSecondary)
    }
}
