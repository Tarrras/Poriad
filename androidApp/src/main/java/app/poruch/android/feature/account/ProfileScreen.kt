package app.poruch.android.feature.account

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Login
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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

/**
 * The account screen. [reminders] is passed in because notification scheduling is an Android
 * concern with its own permission dance — the profile shows it, the route owns it.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileScreen(state: ProfileState, onIntent: (ProfileIntent) -> Unit, reminders: @Composable () -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.fillMaxSize().background(colors.canvas).verticalScroll(rememberScrollState())
            .statusBarsPadding().padding(bottom = 120.dp)
    ) {
        Column(
            Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(colors.canvasTint, colors.canvas)))
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
            if (state.signedIn) {
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
                }
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    SectionHeader(stringResource(R.string.settings))
                    Column(
                        Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
                        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
                    ) { reminders() }
                }
                SecondaryButton(
                    stringResource(R.string.logout), { onIntent(ProfileIntent.SignOut) }, Modifier.fillMaxWidth(),
                    icon = Icons.AutoMirrored.Outlined.Logout, tone = colors.danger
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                SectionHeader(stringResource(R.string.about_app))
                Text(stringResource(R.string.about_app_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            }
        }
    }
}
