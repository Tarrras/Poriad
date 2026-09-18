package app.poruch.android.feature.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
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
    Column(Modifier.fillMaxSize().background(colors.canvas).verticalScroll(rememberScrollState()).imePadding()) {
        // Знак застосунку й назва по центру, як вхід в Apple ID; «назад» окремо в кутку.
        Column(
            Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = Spacing.page).padding(bottom = Spacing.sm),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            val confirming = state.awaitingConfirmation != null
            Box(Modifier.fillMaxWidth().padding(top = Spacing.md)) {
                IconPill(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back), size = 40.dp) { onIntent(AuthIntent.Back) }
            }
            Box(Modifier.size(72.dp).background(colors.brand, CircleShape), contentAlignment = Alignment.Center) {
                Icon(
                    when { confirming -> PoruchIcons.checkCircle; state.resetting -> PoruchIcons.lock; else -> PoruchIcons.pin },
                    null, Modifier.size(32.dp), tint = colors.onBrand
                )
            }
            Text(
                stringResource(
                    when {
                        confirming -> R.string.auth_check_email_title
                        state.resetting -> R.string.auth_reset_title
                        state.signup -> R.string.auth_create
                        else -> R.string.auth_welcome
                    }
                ),
                style = MaterialTheme.typography.headlineMedium, color = colors.ink, textAlign = TextAlign.Center
            )
            Text(
                stringResource(
                    when {
                        confirming -> R.string.auth_check_email_subtitle
                        state.resetting -> R.string.auth_reset_subtitle
                        state.signup -> R.string.auth_subtitle_signup
                        else -> R.string.auth_description
                    }
                ),
                style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary, textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = Spacing.lg)
            )
        }
        if (state.awaitingConfirmation != null) {
            ConfirmationStep(state.awaitingConfirmation, onIntent)
            return@Column
        }
        if (state.resetting) {
            ResetStep(state, onIntent)
            return@Column
        }
        // Фокус на перше поле: імʼя при реєстрації, пошта при вході.
        val emailField = remember { FocusRequester() }
        val nameField = remember { FocusRequester() }
        LaunchedEffect(state.signup) {
            runCatching { if (state.signup) nameField.requestFocus() else emailField.requestFocus() }
        }
        Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
            // Вхід і реєстрація — два рівноправні режими, тож перемикач угорі, а не кнопка під формою.
            SegmentedPill(
                listOf(stringResource(R.string.auth_tab_login), stringResource(R.string.auth_tab_signup)),
                if (state.signup) 1 else 0, { onIntent(AuthIntent.ToggleMode) }
            )
            if (state.signup) LabelledField(
                stringResource(R.string.name), state.name, { onIntent(AuthIntent.SetName(it)) },
                focusRequester = nameField,
                placeholder = stringResource(R.string.name_placeholder)
            )
            // Питаємо раз, при реєстрації, і нікому не показуємо: на це спираються вікові межі й модерація.
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
                focusRequester = emailField,
                placeholder = stringResource(R.string.email_placeholder),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false)
            )
            LabelledField(
                stringResource(R.string.password_label), state.password, { onIntent(AuthIntent.SetPassword(it)) },
                // Вимогу до пароля кажемо лише тому, хто його вигадує.
                hint = if (state.signup) stringResource(R.string.password_hint) else null,
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
            // Згода — під кнопкою, а не чекбокс: натискання на «Створити» і є згодою, посилання ведуть на текст.
            if (state.signup) ConsentNote(onIntent)
            // По центру, як «Видалити обліковий запис» у профілі: текстова кнопка з лівим відступом виглядала зсунутою.
            if (!state.signup) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                GhostButton(
                    stringResource(R.string.forgot_password), { onIntent(AuthIntent.ShowReset(true)) },
                    tone = colors.inkSecondary, enabled = !state.mutating
                )
            }
        }
    }
    if (state.pickingBirthDate) BirthDateSheet(
        state.birthDateValue, { onIntent(AuthIntent.ShowBirthDatePicker(false)) }
    ) { onIntent(AuthIntent.SetBirthDate(it)) }
}

/** Підпис про згоду: дві назви документів — посилання в тексті, решта — тихий підпис. */
@Composable
private fun ConsentNote(onIntent: (AuthIntent) -> Unit) {
    val colors = Poruch.colors
    val terms = stringResource(R.string.auth_consent_terms)
    val privacy = stringResource(R.string.auth_consent_privacy)
    val sentence = stringResource(R.string.auth_consent, terms, privacy)
    val linkStyle = TextLinkStyles(
        SpanStyle(color = colors.ink, fontWeight = FontWeight.SemiBold, textDecoration = TextDecoration.Underline)
    )
    val text = buildAnnotatedString {
        var cursor = 0
        // Назви шукаємо у вже відформатованому реченні, щоб порядок слів належав перекладу.
        listOf(terms to AuthIntent.OpenTerms, privacy to AuthIntent.OpenPrivacy)
            .map { (label, intent) -> Triple(sentence.indexOf(label, cursor), label, intent) }
            .filter { it.first >= 0 }.sortedBy { it.first }
            .forEach { (start, label, intent) ->
                append(sentence.substring(cursor, start))
                withLink(LinkAnnotation.Clickable(label, linkStyle) { onIntent(intent) }) { append(label) }
                cursor = start + label.length
            }
        append(sentence.substring(cursor))
    }
    Text(text, style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
}

/**
 * Наступний крок після реєстрації без сесії: куди пішов лист і що з ним робити. Той самий екран,
 * а не банер: людина має побачити адресу й зрозуміти, що профіль ще не працює.
 */
@Composable
private fun ConfirmationStep(email: String, onIntent: (AuthIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        Column(
            Modifier.fillMaxWidth().cardSurface(Radius.lg).padding(Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Box(
                Modifier.size(48.dp).background(colors.brandContainer, CircleShape),
                contentAlignment = Alignment.Center
            ) { Icon(Icons.Outlined.MailOutline, null, Modifier.size(22.dp), tint = colors.onBrandContainer) }
            Text(
                stringResource(R.string.auth_check_email_body, email),
                style = MaterialTheme.typography.bodyLarge, color = colors.ink
            )
            Text(
                stringResource(R.string.auth_check_email_hint),
                style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
            )
        }
        PrimaryButton(
            stringResource(R.string.auth_open_mail), { onIntent(AuthIntent.OpenMail) },
            Modifier.fillMaxWidth(), icon = Icons.Outlined.MailOutline
        )
        SecondaryButton(
            stringResource(R.string.auth_confirmed_login), { onIntent(AuthIntent.ConfirmedGoLogin) },
            Modifier.fillMaxWidth()
        )
    }
}

/** Скидання пароля: лише пошта, вже вписана переноситься з форми входу. Лист веде назад у застосунок. */
@Composable
private fun ResetStep(state: AuthState, onIntent: (AuthIntent) -> Unit) {
    val emailField = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { emailField.requestFocus() } }
    Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        LabelledField(
            stringResource(R.string.email), state.email, { onIntent(AuthIntent.SetEmail(it)) },
            focusRequester = emailField,
            placeholder = stringResource(R.string.email_placeholder),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false)
        )
        PrimaryButton(
            stringResource(R.string.auth_reset_send), { onIntent(AuthIntent.ResetPassword) },
            Modifier.fillMaxWidth(), icon = Icons.Outlined.MailOutline,
            enabled = state.emailValid, loading = state.mutating
        )
        SecondaryButton(stringResource(R.string.auth_reset_back), { onIntent(AuthIntent.ShowReset(false)) }, Modifier.fillMaxWidth())
    }
}

/** Дата народження показується так, як її пишуть люди. */
private val BIRTH_DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("dd.MM.yyyy")
