package app.poruch.android.feature.account

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Login
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.DeleteForever
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
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
        Modifier.fillMaxSize().background(colors.canvas).verticalScroll(rememberScrollState()).imePadding()
            .padding(bottom = 120.dp)
    ) {
        // Аватар і назва по центру, як картка акаунта в Apple Store.
        Column(
            Modifier.fillMaxWidth().statusBarsPadding()
                .padding(horizontal = Spacing.xxl).padding(top = Spacing.section, bottom = Spacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Box(Modifier.size(88.dp).background(colors.brandContainer, CircleShape), contentAlignment = Alignment.Center) {
                Icon(PoruchIcons.person, null, Modifier.size(36.dp), tint = colors.onBrandContainer)
            }
            Text(
                stringResource(if (state.signedIn) R.string.account_title else R.string.guest_title),
                style = MaterialTheme.typography.headlineMedium, color = colors.ink, textAlign = TextAlign.Center
            )
            Text(
                stringResource(if (state.signedIn) R.string.account_description else R.string.guest_description),
                style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary, textAlign = TextAlign.Center
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
                GroupedRows {
                    LinkRow(
                        PoruchIcons.sparkle, stringResource(R.string.tune_recommendations),
                        stringResource(R.string.tune_recommendations_hint), { onIntent(ProfileIntent.TuneRecommendations) }
                    )
                }
            }
            if (state.signedIn) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    SectionHeader(stringResource(R.string.settings))
                    GroupedRows {
                        Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) { ReminderSetting(state, onIntent) }
                        HairLine(Modifier.padding(start = Spacing.lg))
                        LinkRow(PoruchIcons.lock, stringResource(R.string.update_password), onClick = { onIntent(ProfileIntent.ShowChangePassword(true)) })
                    }
                }
                SecondaryButton(
                    stringResource(R.string.logout), { onIntent(ProfileIntent.SignOut) }, Modifier.fillMaxWidth(),
                    icon = Icons.AutoMirrored.Outlined.Logout, tone = colors.danger
                )
                // Видалення тихіше за вихід: сюди не тягнуться випадково, а знаходять навмисно.
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    GhostButton(
                        stringResource(R.string.delete_account), { onIntent(ProfileIntent.ShowDeleteAccount(true)) },
                        tone = colors.danger
                    )
                }
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
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SectionHeader(stringResource(R.string.about_app))
                Text(stringResource(R.string.about_app_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                GroupedRows {
                    Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) { AnalyticsSetting(state, onIntent) }
                }
                GroupedRows {
                    LinkRow(Icons.Outlined.Shield, stringResource(R.string.privacy_policy), onClick = { onIntent(ProfileIntent.OpenPrivacy) })
                    HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                    LinkRow(Icons.Outlined.Description, stringResource(R.string.terms_of_use), onClick = { onIntent(ProfileIntent.OpenTerms) })
                    HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                    LinkRow(Icons.Outlined.MailOutline, stringResource(R.string.contact_support), onClick = { onIntent(ProfileIntent.ContactSupport) })
                }
                Text(
                    stringResource(R.string.app_version, state.version),
                    style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
                )
            }
        }
    }
    if (state.pickingBirthDate) BirthDateSheet(
        null, { onIntent(ProfileIntent.ShowBirthDatePicker(false)) }
    ) { onIntent(ProfileIntent.SetBirthDate(it)) }
    if (state.deleting) DeleteAccountSheet(state, onIntent)
    if (state.changingPassword) ChangePasswordSheet(state, onIntent)
}

/** Зміна пароля: поточний доводить власника, помилка показується тут — банер лежить під шторкою. */
@Composable
private fun ChangePasswordSheet(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    PoruchSheet({ onIntent(ProfileIntent.ShowChangePassword(false)) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(stringResource(R.string.update_password), style = MaterialTheme.typography.titleLarge, color = colors.ink)
            LabelledField(
                stringResource(R.string.current_password_label), state.currentPassword,
                { onIntent(ProfileIntent.SetCurrentPassword(it)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = PasswordVisualTransformation()
            )
            LabelledField(
                stringResource(R.string.new_password), state.newPassword,
                { onIntent(ProfileIntent.SetNewPassword(it)) },
                hint = stringResource(R.string.password_hint),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = PasswordVisualTransformation()
            )
            state.changeError?.let { Text(it.text(), style = MaterialTheme.typography.bodySmall, color = colors.danger) }
            PrimaryButton(
                stringResource(R.string.update_password), { onIntent(ProfileIntent.ConfirmChangePassword) },
                Modifier.fillMaxWidth(), enabled = state.canChangePassword, loading = state.mutating
            )
            SecondaryButton(
                stringResource(R.string.delete_account_cancel), { sheet.close() }, Modifier.fillMaxWidth(),
                enabled = !state.mutating
            )
        }
    }
}

/**
 * Видалення акаунта: пароль замість «введіть DELETE» — він доводить, що телефон у руках власника.
 * Помилка показується тут: банер застосунку лежить під шторкою.
 */
@Composable
private fun DeleteAccountSheet(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    PoruchSheet({ onIntent(ProfileIntent.ShowDeleteAccount(false)) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(stringResource(R.string.delete_account_title), style = MaterialTheme.typography.titleLarge, color = colors.ink)
            Text(stringResource(R.string.delete_account_body), style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary)
            LabelledField(
                stringResource(R.string.password_label), state.deletePassword,
                { onIntent(ProfileIntent.SetDeletePassword(it)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = PasswordVisualTransformation()
            )
            state.deleteError?.let { Text(it.text(), style = MaterialTheme.typography.bodySmall, color = colors.danger) }
            PrimaryButton(
                stringResource(R.string.delete_account_confirm), { onIntent(ProfileIntent.ConfirmDeleteAccount) },
                Modifier.fillMaxWidth(), enabled = state.canDelete, loading = state.mutating,
                icon = Icons.Outlined.DeleteForever, tone = colors.danger
            )
            SecondaryButton(
                stringResource(R.string.delete_account_cancel), { sheet.close() }, Modifier.fillMaxWidth(),
                enabled = !state.mutating
            )
        }
    }
}

/** Перемикач нагадувань. Дозвіл системи запитує маршрут, тут лише стан і підпис. */
@Composable
private fun ReminderSetting(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            stringResource(R.string.reminders), Modifier.weight(1f).padding(end = 12.dp),
            style = MaterialTheme.typography.bodyLarge, color = colors.ink
        )
        PoruchSwitch(state.reminders, { onIntent(ProfileIntent.SetReminders(it)) })
    }
    Text(
        stringResource(if (state.remindersDenied) R.string.reminder_permission else R.string.reminder_note),
        style = MaterialTheme.typography.bodySmall, color = if (state.remindersDenied) colors.danger else colors.inkTertiary
    )
}

/** Перемикач аналітики. Вимикає і продуктові події, і звіти про збої: так обіцяє політика. */
@Composable
private fun AnalyticsSetting(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            stringResource(R.string.analytics), Modifier.weight(1f).padding(end = 12.dp),
            style = MaterialTheme.typography.bodyLarge, color = colors.ink
        )
        PoruchSwitch(state.analytics, { onIntent(ProfileIntent.SetAnalytics(it)) })
    }
    Text(stringResource(R.string.analytics_note), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
}
