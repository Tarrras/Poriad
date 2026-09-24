package app.poruch.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.domain.Profile
import app.poruch.shared.PersonState
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Фото, імʼя, дата приходу й лічильники по центру. Спільне для власної шапки й картки людини. */
@Composable
fun ProfileSummary(profile: Profile, modifier: Modifier = Modifier, avatarSize: androidx.compose.ui.unit.Dp = 88.dp) {
    val colors = Poruch.colors
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Avatar(profile.name, profile.avatarUrl, avatarSize)
        Text(profile.name, style = MaterialTheme.typography.headlineMedium, color = colors.ink, textAlign = TextAlign.Center)
        profile.email?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary) }
        memberSince(profile.memberSince)?.let {
            Text(stringResource(R.string.profile_member_since, it), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        }
        Row(Modifier.padding(top = Spacing.xs), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Stat(profile.organized, stringResource(R.string.profile_organized), Modifier.weight(1f))
            Stat(profile.attended, stringResource(R.string.profile_attended), Modifier.weight(1f))
        }
    }
}

@Composable
private fun Stat(value: Int, label: String, modifier: Modifier) {
    val colors = Poruch.colors
    Column(modifier.cardSurface().padding(Spacing.md), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value.toString(), style = MaterialTheme.typography.titleLarge, color = colors.ink)
        Text(label, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
    }
}

/** «вересня 2026»: родовий відмінок, бо стоїть після «з». */
@Composable
private fun memberSince(iso: String?): String? = remember(iso) {
    iso?.let { runCatching { Instant.parse(it) }.getOrNull() }?.atZone(ZoneId.systemDefault())
        ?.format(DateTimeFormatter.ofPattern("MMMM yyyy", Locale.forLanguageTag("uk")))
}

/**
 * Картка людини. [actions] — дії контексту (прийняти запит); скарга й блокування — для всіх, крім себе.
 * Блокування в два кроки прямо в шторці: друга шторка поверх цієї губила б контекст.
 */
@Composable
fun PersonSheet(
    person: PersonState,
    isMe: Boolean,
    onDismiss: () -> Unit,
    onBlock: (() -> Unit)?,
    onReport: (() -> Unit)? = null,
    actions: @Composable ColumnScope.(PoruchSheetScope) -> Unit = {}
) {
    val colors = Poruch.colors
    var confirmBlock by remember(person.userId) { mutableStateOf(false) }
    PoruchSheet(onDismiss) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            val profile = person.profile
            when {
                person.loading -> Box(Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center) {
                    PoruchLoader()
                }
                profile == null -> Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Text(stringResource(R.string.person_unavailable), style = MaterialTheme.typography.titleLarge, color = colors.ink)
                    Text(stringResource(R.string.person_unavailable_hint), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary, textAlign = TextAlign.Center)
                }
                else -> {
                    ProfileSummary(profile)
                    profile.bio?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = colors.ink, modifier = Modifier.fillMaxWidth()) }
                    if (isMe) Text(
                        stringResource(R.string.person_you), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary,
                        modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center
                    )
                }
            }
            if (!person.loading) actions(sheet)
            if (!isMe && !person.loading) {
                if (confirmBlock && onBlock != null) {
                    Text(stringResource(R.string.block_user_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                    PrimaryButton(stringResource(R.string.person_block_confirm), { sheet.close(onBlock) }, Modifier.fillMaxWidth(), tone = colors.danger)
                    SecondaryButton(stringResource(R.string.delete_account_cancel), { confirmBlock = false }, Modifier.fillMaxWidth())
                } else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    if (onReport != null) GhostButton(stringResource(R.string.report), { sheet.close(onReport) }, tone = colors.inkSecondary)
                    if (onBlock != null) GhostButton(stringResource(R.string.person_block), { confirmBlock = true }, tone = colors.danger)
                }
            }
        }
    }
}
