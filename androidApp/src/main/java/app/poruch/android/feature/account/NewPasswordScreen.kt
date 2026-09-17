package app.poruch.android.feature.account

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.ui.draw.clip
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*

/** Новий пароль після листа відновлення: один крок, без вкладок, та сама шапка, що на вході. */
@Composable
fun NewPasswordScreen(state: ProfileState, onIntent: (ProfileIntent) -> Unit) {
    val colors = Poruch.colors
    val field = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { field.requestFocus() } }
    Column(Modifier.fillMaxSize().background(colors.canvas).verticalScroll(rememberScrollState()).imePadding()) {
        Column(
            Modifier.fillMaxWidth().background(heroGradient()).statusBarsPadding()
                .padding(horizontal = Spacing.page).padding(top = Spacing.xxl, bottom = Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(stringResource(R.string.new_password), style = MaterialTheme.typography.displaySmall, color = colors.ink)
            Text(stringResource(R.string.new_password_subtitle), style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary)
        }
        // Один перемикач на обидва поля: показує або ховає пароль разом із повтором.
        val transformation = if (state.newPasswordRevealed) VisualTransformation.None else PasswordVisualTransformation()
        Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
            LabelledField(
                stringResource(R.string.password_label), state.newPassword,
                { onIntent(ProfileIntent.SetNewPassword(it)) },
                focusRequester = field,
                hint = stringResource(R.string.password_hint),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = transformation,
                trailing = {
                    Icon(
                        if (state.newPasswordRevealed) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                        stringResource(if (state.newPasswordRevealed) R.string.hide_password else R.string.show_password),
                        Modifier.minimumInteractiveComponentSize().size(20.dp).clip(CircleShape)
                            .clickable { onIntent(ProfileIntent.ToggleNewPasswordReveal) },
                        tint = colors.inkSecondary
                    )
                }
            )
            LabelledField(
                stringResource(R.string.password_confirm_label), state.newPasswordConfirm,
                { onIntent(ProfileIntent.SetNewPasswordConfirm(it)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = transformation
            )
            if (state.passwordsMismatch) Text(
                stringResource(R.string.err_passwords_mismatch),
                style = MaterialTheme.typography.bodySmall, color = colors.danger
            )
            PrimaryButton(
                stringResource(R.string.save_password), { onIntent(ProfileIntent.SavePassword) },
                Modifier.fillMaxWidth(), enabled = state.canSetNewPassword, loading = state.mutating
            )
        }
    }
}
