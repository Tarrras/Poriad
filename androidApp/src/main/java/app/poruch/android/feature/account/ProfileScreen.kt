package app.poruch.android.feature.account

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.automirrored.outlined.Login
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.android.feature.editor.BirthDateSheet

/** Екран акаунта: хто ви, що вам цікаво, як з вами зв'язатися. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileScreen(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.fillMaxSize().background(colors.canvas).verticalScroll(rememberScrollState())
            .padding(bottom = 120.dp)
    ) {
        Column(
            Modifier.fillMaxWidth().background(heroGradient()).statusBarsPadding()
                .padding(horizontal = Spacing.page, vertical = Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Box(Modifier.size(64.dp).background(colors.brandContainer, CircleShape), contentAlignment = Alignment.Center) {
                Icon(PoruchIcons.person, null, Modifier.size(30.dp), tint = colors.onBrandContainer)
            }
            Text(
                stringResource(if (state.signedIn) R.string.account_title else R.string.guest_title),
                style = MaterialTheme.typography.headlineMedium, color = colors.ink
            )
            Text(
                stringResource(if (state.signedIn) R.string.account_description else R.string.guest_description),
                style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary
            )
            if (!state.signedIn) PrimaryButton(
                stringResource(R.string.profile_guest_cta), { onIntent(ProfileIntent.SignIn) },
                Modifier.fillMaxWidth(), icon = Icons.AutoMirrored.Outlined.Login
            )
        }
        Column(Modifier.padding(horizontal = Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.xxl)) {
            if (state.passwordRecovery) Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SectionHeader(stringResource(R.string.new_password))
                LabelledField(
                    stringResource(R.string.password_label), state.newPassword,
                    { onIntent(ProfileIntent.SetNewPassword(it)) },
                    hint = stringResource(R.string.password_hint),
                    visualTransformation = PasswordVisualTransformation()
                )
                PrimaryButton(
                    stringResource(R.string.update_password), { onIntent(ProfileIntent.SavePassword) },
                    Modifier.fillMaxWidth(), enabled = state.canSavePassword
                )
            }
            // Старий акаунт без віку питаємо тут, раз, і кажемо чому.
            if (state.needsAge) Column(
                Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                Text(stringResource(R.string.confirm_age_title), style = MaterialTheme.typography.titleSmall, color = colors.ink)
                Text(stringResource(R.string.confirm_age_body), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                PrimaryButton(
                    stringResource(R.string.confirm_age_action),
                    { onIntent(ProfileIntent.ShowBirthDatePicker(true)) }, Modifier.fillMaxWidth()
                )
            }
            // Інтереси належать пристрою, тож гість теж їх редагує.
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SectionHeader(stringResource(R.string.interests))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm)
                ) {
                    categories.forEach { category ->
                        PoruchChip(
                            stringResource(categoryLabel(category)), category in state.interests,
                            { onIntent(ProfileIntent.ToggleInterest(category)) }, dot = category
                        )
                    }
                }
                Row(
                    Modifier.fillMaxWidth().cardSurface().pressable { onIntent(ProfileIntent.TuneRecommendations) }
                        .padding(Spacing.lg),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                ) {
                    Icon(PoruchIcons.sparkle, null, Modifier.size(20.dp), tint = colors.brand)
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(R.string.tune_recommendations),
                            style = MaterialTheme.typography.titleSmall, color = colors.ink
                        )
                        Text(
                            stringResource(R.string.tune_recommendations_hint),
                            style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary
                        )
                    }
                    Icon(Icons.AutoMirrored.Outlined.ArrowForward, null, Modifier.size(18.dp), tint = colors.inkTertiary)
                }
            }
            if (state.signedIn) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    SectionHeader(stringResource(R.string.settings))
                    Column(
                        Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
                        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
                    ) { ReminderSetting(state, onIntent) }
                }
                SecondaryButton(
                    stringResource(R.string.logout), { onIntent(ProfileIntent.SignOut) }, Modifier.fillMaxWidth(),
                    icon = Icons.AutoMirrored.Outlined.Logout, tone = colors.danger
                )
            }
            // Блок, який не можна скасувати, не використовуватимуть: список з іменами.
            if (state.blocked.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SectionHeader(stringResource(R.string.blocked_section))
                state.blocked.forEach { person ->
                    Row(
                        Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                    ) {
                        Text(
                            person.name.ifBlank { stringResource(R.string.organizer_short) },
                            style = MaterialTheme.typography.titleSmall, color = colors.ink, modifier = Modifier.weight(1f)
                        )
                        GhostButton(stringResource(R.string.unblock), { onIntent(ProfileIntent.Unblock(person.userId)) })
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                SectionHeader(stringResource(R.string.about_app))
                Text(stringResource(R.string.about_app_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            }
        }
    }
    if (state.pickingBirthDate) BirthDateSheet(
        null, { onIntent(ProfileIntent.ShowBirthDatePicker(false)) }
    ) { onIntent(ProfileIntent.SetBirthDate(it)) }
}

/** Перемикач нагадувань. Дозвіл системи запитує маршрут, тут лише стан і підпис. */
@Composable
private fun ReminderSetting(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            stringResource(R.string.reminders), Modifier.weight(1f).padding(end = 12.dp),
            style = MaterialTheme.typography.bodyLarge, color = colors.ink
        )
        Switch(
            state.reminders, { onIntent(ProfileIntent.SetReminders(it)) },
            colors = SwitchDefaults.colors(checkedTrackColor = colors.brand, checkedThumbColor = colors.onBrand)
        )
    }
    Text(
        stringResource(if (state.remindersDenied) R.string.reminder_permission else R.string.reminder_note),
        style = MaterialTheme.typography.bodySmall, color = if (state.remindersDenied) colors.danger else colors.inkTertiary
    )
}
