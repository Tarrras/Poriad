package app.poruch.android.feature.account

import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.Image
import android.graphics.BitmapFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.android.feature.editor.BirthDateSheet
import app.poruch.android.feature.detail.rememberImagePicker
import app.poruch.domain.AccountRules
import app.poruch.domain.Profile
import app.poruch.domain.ProfileRules

/**
 * Екран профілю: хто ви, що вам цікаво, що й коли вам писати. Порядок — від людини до пристрою:
 * шапка, підписки, інтереси, сповіщення, приватність, про застосунок; вихід і видалення — в самому низу.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileScreen(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    Box(Modifier.fillMaxSize().background(colors.canvas)) {
        Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).tabBarClearance()) {
            ProfileHeader(state, onIntent)
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
                        stringResource(R.string.save_password), { onIntent(ProfileIntent.SavePassword) },
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
                // Ні організованих, ні відвіданих: замість двох нулів у шапці — перша дія.
                if (state.signedIn && state.profile?.let { it.organized == 0 && it.attended == 0 } == true) CreateEventCard(
                    stringResource(R.string.home_create_title), stringResource(R.string.home_create_subtitle),
                    { onIntent(ProfileIntent.CreateEvent) }
                )
                // Список підписок — окремий екран: тут лише рядок, що каже, що вони є й де. Порожнім його не показуємо.
                if (state.signedIn && state.follows.isNotEmpty()) GroupedRows {
                    LinkRow(
                        PoruchIcons.bellActive, stringResource(R.string.follows_title), stringResource(R.string.follows_hint),
                        { onIntent(ProfileIntent.OpenFollows) }, value = state.follows.size.toString(),
                        badge = if (state.newFollows > 0) pluralStringResource(R.plurals.follows_new, state.newFollows, state.newFollows) else null
                    )
                }
                // Інтереси належать пристрою, тож гість теж їх редагує. Опитування — дія заголовка, а не ще одна картка під чипами.
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    SectionHeader(
                        stringResource(R.string.interests), actionLabel = stringResource(R.string.retake_quiz),
                        onAction = { onIntent(ProfileIntent.TuneRecommendations) }
                    )
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
                }
                // Усе, що приходить пушем, в одному місці. Дайджест про місто, а не про акаунт: гість його теж отримує.
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    SectionHeader(stringResource(R.string.notifications_section))
                    GroupedRows {
                        Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) { DigestSetting(state, onIntent) }
                        if (state.signedIn) {
                            HairLine(Modifier.padding(start = Spacing.lg))
                            Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) { ReminderSetting(state, onIntent) }
                        }
                    }
                }
                PrivacySection(state, onIntent)
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    SectionHeader(stringResource(R.string.about_app))
                    Text(stringResource(R.string.about_app_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                    GroupedRows {
                        LinkRow(PoruchIcons.shield, stringResource(R.string.privacy_policy), onClick = { onIntent(ProfileIntent.OpenPrivacy) })
                        HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                        LinkRow(PoruchIcons.doc, stringResource(R.string.terms_of_use), onClick = { onIntent(ProfileIntent.OpenTerms) })
                        HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                        LinkRow(PoruchIcons.mail, stringResource(R.string.contact_support), onClick = { onIntent(ProfileIntent.ContactSupport) })
                    }
                    GroupedRows {
                        LinkRow(PoruchIcons.share, stringResource(R.string.share_app), onClick = { onIntent(ProfileIntent.ShareApp) })
                        HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                        LinkRow(PoruchIcons.star, stringResource(R.string.rate_app), stringResource(R.string.rate_app_subtitle), onClick = { onIntent(ProfileIntent.RateApp) })
                    }
                }
                // Вихід — звичайна дія, не небезпечна: нейтральна кнопка. Видалення тихіше й червоне: сюди не тягнуться
                // випадково, а знаходять навмисно; підтвердження — паролем у шторці.
                if (state.signedIn) Column(
                    Modifier.padding(top = Spacing.lg), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(Spacing.sm)
                ) {
                    SecondaryButton(
                        stringResource(R.string.logout), { onIntent(ProfileIntent.SignOut) }, Modifier.fillMaxWidth(),
                        icon = PoruchIcons.signOut
                    )
                    GhostButton(stringResource(R.string.delete_account), { onIntent(ProfileIntent.ShowDeleteAccount(true)) }, tone = colors.danger)
                }
                Text(
                    stringResource(R.string.app_version, state.version), Modifier.fillMaxWidth(),
                    style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary, textAlign = TextAlign.Center
                )
            }
        }
        StatusBarBand()
    }
    if (state.pickingBirthDate) BirthDateSheet(
        null, { onIntent(ProfileIntent.ShowBirthDatePicker(false)) }
    ) { onIntent(ProfileIntent.SetBirthDate(it)) }
    if (state.deleting) DeleteAccountSheet(state, onIntent)
    if (state.changingPassword) ChangePasswordSheet(state, onIntent)
    if (state.editing) state.profile?.let { EditProfileSheet(it, state, onIntent) }
}

/** Аватар і назва по центру, як картка акаунта в Apple Store. Гостю — загальна шапка й вхід. */
@Composable
private fun ProfileHeader(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.fillMaxWidth().statusBarsPadding()
            .padding(horizontal = Spacing.xxl).padding(top = Spacing.section, bottom = Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        val profile = state.profile
        if (state.signedIn && profile != null) {
            ProfileSummary(profile)
            profile.bio?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = colors.ink, textAlign = TextAlign.Center) }
            SecondaryButton(
                stringResource(R.string.profile_edit), { onIntent(ProfileIntent.ShowEdit(true)) },
                Modifier.fillMaxWidth(), icon = PoruchIcons.edit
            )
        } else {
            Box(Modifier.size(88.dp).background(colors.brandContainer, CircleShape), contentAlignment = Alignment.Center) {
                Icon(PoruchIcons.person, null, Modifier.size(36.dp), tint = colors.onBrandContainer)
            }
            Text(
                stringResource(if (state.signedIn) R.string.account_title else R.string.guest_title),
                style = PoruchType.brandTitle1, color = colors.ink, textAlign = TextAlign.Center
            )
            Text(
                stringResource(if (state.signedIn) R.string.profile_events_hint else R.string.guest_description),
                style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary, textAlign = TextAlign.Center
            )
        }
        if (!state.signedIn) PrimaryButton(
            stringResource(R.string.profile_guest_cta), { onIntent(ProfileIntent.SignIn) },
            Modifier.fillMaxWidth(), icon = PoruchIcons.signIn
        )
    }
}

/** Згода належить пристрою, тож аналітика є і в гостя; пароль і заблоковані — лише з акаунтом. */
@Composable
private fun PrivacySection(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.privacy_section))
        GroupedRows {
            Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) { AnalyticsSetting(state, onIntent) }
            // Акаунт Google/Apple пароля не має — і міняти нічого.
            if (state.signedIn && !state.passwordless) {
                HairLine(Modifier.padding(start = Spacing.lg))
                LinkRow(PoruchIcons.lock, stringResource(R.string.update_password), onClick = { onIntent(ProfileIntent.ShowChangePassword(true)) })
            }
        }
        // Блок, який не можна скасувати, не використовуватимуть: список з іменами.
        if (state.blocked.isNotEmpty()) {
            Text(
                stringResource(R.string.blocked_section), Modifier.padding(top = Spacing.sm),
                style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary
            )
            GroupedRows {
                state.blocked.forEachIndexed { position, person ->
                    if (position > 0) HairLine(Modifier.padding(start = Spacing.lg))
                    Row(
                        Modifier.fillMaxWidth().padding(start = Spacing.lg, end = Spacing.sm, top = Spacing.xs, bottom = Spacing.xs),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                    ) {
                        Text(
                            person.name.ifBlank { stringResource(R.string.chat_member) },
                            style = MaterialTheme.typography.titleSmall, color = colors.ink, modifier = Modifier.weight(1f)
                        )
                        GhostButton(stringResource(R.string.unblock), { onIntent(ProfileIntent.Unblock(person.userId)) })
                    }
                }
            }
        }
    }
}

/**
 * Редагування профілю: фото, імʼя, «Про себе» — все зберігається разом кнопкою. Нове фото й «Видалити фото»
 * до «Зберегти» лише позначені, тож «Скасувати» справді нічого не міняє. Помилку збереження показуємо тут: банер лежить під шторкою.
 */
@Composable
private fun EditProfileSheet(profile: Profile, state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    var name by remember { mutableStateOf(profile.name) }
    var bio by remember { mutableStateOf(profile.bio.orEmpty()) }
    var newPhoto by remember { mutableStateOf<Pair<ByteArray, String>?>(null) }
    var removingPhoto by remember { mutableStateOf(false) }
    val preview = remember(newPhoto) { newPhoto?.first?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    val picker = rememberImagePicker(ProfileRules.AVATAR_SIDE) { bytes, mime -> newPhoto = bytes to mime; removingPhoto = false }
    val hasPhoto = preview != null || (profile.avatarUrl != null && !removingPhoto)
    PoruchSheet({ onIntent(ProfileIntent.ShowEdit(false)) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(stringResource(R.string.profile_edit), style = PoruchType.brandTitle2, color = colors.ink)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.lg)) {
                Box(contentAlignment = Alignment.Center) {
                    if (preview != null) Image(preview, null, Modifier.size(72.dp).clip(CircleShape), contentScale = ContentScale.Crop)
                    else Avatar(name, profile.avatarUrl.takeUnless { removingPhoto }, 72.dp)
                    if (picker.reading || state.mutating) CircularProgressIndicator(Modifier.size(72.dp), color = colors.brand)
                }
                Column {
                    GhostButton(
                        stringResource(if (hasPhoto) R.string.profile_photo_change else R.string.profile_photo_add),
                        picker.open, enabled = !state.mutating && !picker.reading
                    )
                    if (removingPhoto) GhostButton(stringResource(R.string.undo), { removingPhoto = false }, enabled = !state.mutating)
                    else if (hasPhoto) GhostButton(
                        stringResource(R.string.profile_photo_remove),
                        { if (newPhoto != null) newPhoto = null else removingPhoto = true },
                        tone = colors.danger, enabled = !state.mutating
                    )
                }
            }
            if (picker.failed) Text(stringResource(R.string.photo_error), style = MaterialTheme.typography.bodySmall, color = colors.danger)
            Text(
                stringResource(if (removingPhoto) R.string.remove_photo_undo else R.string.profile_photo_hint),
                style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
            )
            LabelledField(
                stringResource(R.string.profile_name), name, { name = it.take(AccountRules.nameLength.last) },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words)
            )
            LabelledField(
                stringResource(R.string.profile_bio), bio, { bio = it.take(ProfileRules.BIO_MAX) },
                hint = stringResource(R.string.profile_bio_hint), singleLine = false, minLines = 3,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
            )
            state.editError?.let { Text(it.text(), style = MaterialTheme.typography.bodySmall, color = colors.danger) }
            PrimaryButton(
                stringResource(R.string.profile_save),
                { onIntent(ProfileIntent.SaveProfile(name, bio, newPhoto?.first, newPhoto?.second, removingPhoto)) },
                Modifier.fillMaxWidth(), enabled = AccountRules.isName(name) && !state.mutating && !picker.reading, loading = state.mutating
            )
            SecondaryButton(stringResource(R.string.delete_account_cancel), { sheet.close() }, Modifier.fillMaxWidth(), enabled = !state.mutating)
        }
    }
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
            Text(stringResource(R.string.update_password), style = PoruchType.brandTitle2, color = colors.ink)
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
            Text(stringResource(R.string.delete_account_title), style = PoruchType.brandTitle2, color = colors.ink)
            Text(stringResource(R.string.delete_account_body), style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary)
            // Google чи Apple з тією ж поштою привʼязуються до наявного акаунта: людина має бачити, що видаляє саме його.
            DeleteAccountWho(state)
            // Пароль доводить, що телефон у руках власника; в акаунта Google/Apple його нема — підтверджує кнопка.
            if (!state.passwordless) LabelledField(
                stringResource(R.string.password_label), state.deletePassword,
                { onIntent(ProfileIntent.SetDeletePassword(it)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = PasswordVisualTransformation()
            )
            state.deleteError?.let { Text(it.text(), style = MaterialTheme.typography.bodySmall, color = colors.danger) }
            PrimaryButton(
                stringResource(R.string.delete_account_confirm), { onIntent(ProfileIntent.ConfirmDeleteAccount) },
                Modifier.fillMaxWidth(), enabled = state.canDelete, loading = state.mutating,
                icon = PoruchIcons.trash, tone = colors.danger
            )
            SecondaryButton(
                stringResource(R.string.delete_account_cancel), { sheet.close() }, Modifier.fillMaxWidth(),
                enabled = !state.mutating
            )
        }
    }
}

/** Який акаунт зникне: пошта й усі способи входу в нього. */
@Composable
private fun DeleteAccountWho(state: ProfileState) {
    val colors = Poruch.colors
    val email = state.profile?.email ?: return
    val methods = state.providers.mapNotNull {
        when (it) { "email" -> stringResource(R.string.sign_in_method_email); "google" -> "Google"; "apple" -> "Apple"; else -> null }
    }
    Column(
        Modifier.fillMaxWidth().background(LocalFieldSurface.current ?: colors.surface, Radius.sm).padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        Text(stringResource(R.string.delete_account_who), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
        Text(email, style = MaterialTheme.typography.titleSmall, color = colors.ink)
        if (methods.size > 1) Text(
            stringResource(R.string.delete_account_methods, methods.joinToString(" · ")),
            style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary
        )
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
    if (state.remindersDenied) NotificationsDenied(onIntent)
    else Text(stringResource(R.string.reminder_note), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
    if (state.reminders && !state.remindersExact) {
        Text(stringResource(R.string.reminder_exact), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        GhostButton(stringResource(R.string.reminder_exact_allow), { onIntent(ProfileIntent.OpenAlarmSettings) }, Modifier.offset(x = -Spacing.lg))
    }
}

/** Перемикач дайджесту вихідних. Дозвіл системи запитує маршрут, як і для нагадувань. */
@Composable
private fun DigestSetting(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            stringResource(R.string.digest), Modifier.weight(1f).padding(end = 12.dp),
            style = MaterialTheme.typography.bodyLarge, color = colors.ink
        )
        PoruchSwitch(state.digest, { onIntent(ProfileIntent.SetDigest(it)) })
    }
    if (state.digestDenied) NotificationsDenied(onIntent)
    else Text(stringResource(R.string.digest_note), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
}

/** Сповіщення заборонено в системі: каже це й веде туди, де дозволяють. */
@Composable
private fun NotificationsDenied(onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    Text(stringResource(R.string.reminder_permission), style = MaterialTheme.typography.bodySmall, color = colors.danger)
    GhostButton(
        stringResource(R.string.open_settings), { onIntent(ProfileIntent.OpenNotificationSettings) },
        Modifier.offset(x = -Spacing.lg)
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
