package app.poruch.android.feature.account

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.android.feature.editor.BirthDateSheet
import java.time.format.DateTimeFormatter

@Composable
fun AuthScreen(state: AuthState, onIntent: (AuthIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).verticalScroll(rememberScrollState())) {
        // The same paper band every other screen opens with, so sign-in belongs to the app.
        Column(
            Modifier.fillMaxWidth().background(heroGradient()).statusBarsPadding()
                .padding(horizontal = Spacing.page).padding(bottom = Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Box(
                Modifier.padding(top = Spacing.md).size(40.dp).background(colors.surface, CircleShape)
                    .border(1.dp, colors.hairline, CircleShape).clip(CircleShape)
                    .clickable { onIntent(AuthIntent.Back) },
                contentAlignment = Alignment.Center
            ) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back), Modifier.size(18.dp), tint = colors.ink) }
            Text(
                stringResource(if (state.signup) R.string.auth_create else R.string.auth_welcome),
                style = MaterialTheme.typography.displaySmall, color = colors.ink
            )
            Text(
                stringResource(if (state.signup) R.string.auth_subtitle_signup else R.string.auth_description),
                style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary
            )
        }
        Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
            if (state.signup) LabelledField(
                stringResource(R.string.name), state.name, { onIntent(AuthIntent.SetName(it)) },
                placeholder = stringResource(R.string.name_placeholder)
            )
            // Asked once, at sign-up, and never shown to anybody else: it is what an age limit on
            // an event has to rest on, and what a moderation decision later refers back to.
            if (state.signup) PickerField(
                stringResource(R.string.birth_date),
                state.birthDateValue?.format(BIRTH_DATE_FORMAT).orEmpty(),
                { onIntent(AuthIntent.ShowBirthDatePicker(true)) },
                placeholder = stringResource(R.string.birth_date_placeholder),
                hint = stringResource(R.string.birth_date_hint),
                icon = PoruchIcons.calendar
            )
            LabelledField(
                stringResource(R.string.email), state.email, { onIntent(AuthIntent.SetEmail(it)) },
                placeholder = stringResource(R.string.email_placeholder),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false)
            )
            LabelledField(
                stringResource(R.string.password_label), state.password, { onIntent(AuthIntent.SetPassword(it)) },
                hint = stringResource(R.string.password_hint),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = if (state.passwordRevealed) VisualTransformation.None else PasswordVisualTransformation(),
                trailing = {
                    Icon(
                        if (state.passwordRevealed) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                        stringResource(if (state.passwordRevealed) R.string.hide_password else R.string.show_password),
                        Modifier.minimumInteractiveComponentSize().size(20.dp).clip(CircleShape)
                            .clickable { onIntent(AuthIntent.TogglePasswordReveal) },
                        tint = colors.inkSecondary
                    )
                }
            )
            PrimaryButton(
                stringResource(if (state.signup) R.string.signup else R.string.login),
                { onIntent(AuthIntent.Submit) },
                Modifier.fillMaxWidth(), enabled = state.canSubmit, loading = state.mutating
            )
            if (!state.signup) GhostButton(
                stringResource(R.string.forgot_password), { onIntent(AuthIntent.ResetPassword) },
                tone = colors.inkSecondary, enabled = state.emailValid && !state.mutating
            )
            // Registration is the other half of this screen, not a footnote: everyone arriving
            // without an account has to reach it, so it gets a real button under a divider.
            Row(
                Modifier.padding(top = Spacing.sm), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                HairLine(Modifier.weight(1f))
                Text(
                    stringResource(if (state.signup) R.string.already_registered else R.string.no_account_yet),
                    style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
                )
                HairLine(Modifier.weight(1f))
            }
            SecondaryButton(
                stringResource(if (state.signup) R.string.login else R.string.signup),
                { onIntent(AuthIntent.ToggleMode) }, Modifier.fillMaxWidth()
            )
        }
    }
    if (state.pickingBirthDate) BirthDateSheet(
        state.birthDateValue, { onIntent(AuthIntent.ShowBirthDatePicker(false)) }
    ) { onIntent(AuthIntent.SetBirthDate(it)) }
}

/** A birth date is read, not calculated with, so it is shown the way people write one. */
private val BIRTH_DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("dd.MM.yyyy")
