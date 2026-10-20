package app.poruch.android.feature.account

import app.poruch.android.navigation.AuthReason
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.res.painterResource
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
    // Системний «назад» — як стрілка: з «Забули пароль?» до форми, з кроку листа — з його скиданням.
    BackHandler { onIntent(AuthIntent.Back) }
    Column(Modifier.fillMaxSize().background(colors.canvas).imePadding().verticalScroll(rememberScrollState())) {
        // Знак застосунку й назва по центру, як вхід в Apple ID; «назад» окремо в кутку.
        Column(
            Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = Spacing.page).padding(bottom = Spacing.sm),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            val confirming = state.awaitingConfirmation != null
            Box(Modifier.fillMaxWidth().padding(top = Spacing.md)) {
                IconPill(PoruchIcons.arrowLeft, stringResource(R.string.back), size = 40.dp) { onIntent(AuthIntent.Back) }
            }
            Box(Modifier.size(72.dp).background(colors.brand, CircleShape), contentAlignment = Alignment.Center) {
                Icon(
                    when {
                        confirming -> PoruchIcons.checkCircle; state.resetting -> PoruchIcons.lock
                        state.askBirthDate -> PoruchIcons.calendar; else -> PoruchIcons.pin
                    },
                    null, Modifier.size(32.dp), tint = colors.onBrand
                )
            }
            Text(
                stringResource(
                    when {
                        confirming -> R.string.auth_check_email_title
                        state.resetting -> R.string.auth_reset_title
                        state.askBirthDate -> R.string.auth_birth_date_title
                        state.signup -> R.string.auth_create
                        else -> R.string.auth_welcome
                    }
                ),
                style = PoruchType.brandTitle1, color = colors.ink, textAlign = TextAlign.Center
            )
            Text(
                stringResource(
                    when {
                        confirming -> R.string.auth_check_email_subtitle
                        state.resetting -> R.string.auth_reset_subtitle
                        state.askBirthDate -> R.string.auth_birth_date_subtitle
                        // Навіщо профіль саме зараз: гість прийшов з дією, і рядок під заголовком — про неї.
                        else -> when (state.reason) {
                            AuthReason.CREATE -> if (state.signup) R.string.auth_subtitle_create_signup else R.string.auth_subtitle_create_signin
                            AuthReason.JOIN -> R.string.auth_reason_join
                            AuthReason.FOLLOW -> R.string.auth_reason_follow
                            AuthReason.COMPANY -> R.string.auth_reason_company
                            AuthReason.GENERAL -> if (state.signup) R.string.auth_subtitle_signup else R.string.auth_guest_note
                        }
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
        if (state.askBirthDate) {
            BirthDateStep(state, onIntent)
            return@Column
        }
        // Фокус на перше поле: імʼя при реєстрації, пошта при вході.
        val emailField = remember { FocusRequester() }
        val nameField = remember { FocusRequester() }
        LaunchedEffect(state.signup) {
            runCatching { if (state.signup) nameField.requestFocus() else emailField.requestFocus() }
        }
        Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
            // Google — найкоротший шлях, тож над формою; для нього вхід і реєстрація — одне й те саме.
            if (state.googleAvailable) {
                ProviderButton(
                    painterResource(R.drawable.ic_google), stringResource(R.string.continue_with_google),
                    { onIntent(AuthIntent.SignInWithGoogle) }, enabled = !state.mutating
                )
                // Згода одразу під Google: дотик до нього вже створює профіль, а форма з кнопкою — нижче.
                ConsentNote(onIntent)
                OrDivider(stringResource(R.string.auth_or_email))
            }
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
                trailing = { PasswordRevealIcon(state.passwordRevealed) { onIntent(AuthIntent.TogglePasswordReveal) } }
            )
            PrimaryButton(
                stringResource(if (state.signup) R.string.register else R.string.login),
                { onIntent(AuthIntent.Submit) },
                Modifier.fillMaxWidth(), enabled = state.canSubmit, loading = state.mutating
            )
            // Згода — підписом, а не чекбоксом: натискання на «Зареєструватися» і є згодою. З Google вона вже стоїть над формою.
            if (state.signup && !state.googleAvailable) ConsentNote(onIntent)
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

/** Кнопка входу через провайдера: знак провайдера в оригінальних кольорах, світла пігулка. */
@Composable
private fun ProviderButton(logo: Painter, text: String, onClick: () -> Unit, enabled: Boolean) {
    val colors = Poruch.colors
    Row(
        // Великий шрифт переносить напис і робить кнопку вищою, а не обрізає «Продовжити з Goo…».
        Modifier.fillMaxWidth().heightIn(min = 52.dp).background(colors.surface, ButtonShape).border(1.dp, colors.hairline, ButtonShape)
            .clip(ButtonShape).pressable(enabled = enabled, onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md, Alignment.CenterHorizontally)
    ) {
        Image(logo, null, Modifier.size(20.dp))
        Text(
            text, style = MaterialTheme.typography.titleSmall, color = if (enabled) colors.ink else colors.inkTertiary,
            maxLines = 2, textAlign = TextAlign.Center
        )
    }
}

/** Лінія з підписом посередині: «або поштою». */
@Composable
private fun OrDivider(text: String) {
    val colors = Poruch.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        HairLine(Modifier.weight(1f))
        Text(text, style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        HairLine(Modifier.weight(1f))
    }
}

/**
 * Після входу через Google: провайдер вік не каже, а «Поряд» — для повнолітніх. Та сама дата, що
 * при реєстрації поштою; «назад» лишає людину в акаунті, і картка віку чекатиме в профілі.
 */
@Composable
private fun BirthDateStep(state: AuthState, onIntent: (AuthIntent) -> Unit) {
    Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        PickerField(
            stringResource(R.string.birth_date),
            state.birthDateValue?.format(BIRTH_DATE_FORMAT).orEmpty(),
            { onIntent(AuthIntent.ShowBirthDatePicker(true)) },
            placeholder = stringResource(R.string.birth_date_placeholder),
            hint = stringResource(R.string.birth_date_hint),
            icon = PoruchIcons.calendar
        )
        PrimaryButton(
            stringResource(R.string.auth_birth_date_continue), { onIntent(AuthIntent.DeclareBirthDate) },
            Modifier.fillMaxWidth(), enabled = state.canDeclareBirthDate, loading = state.mutating
        )
    }
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
            ) { Icon(PoruchIcons.mail, null, Modifier.size(22.dp), tint = colors.onBrandContainer) }
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
            Modifier.fillMaxWidth(), icon = PoruchIcons.mail
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
            Modifier.fillMaxWidth(), icon = PoruchIcons.mail,
            enabled = state.emailValid, loading = state.mutating
        )
        SecondaryButton(stringResource(R.string.auth_reset_back), { onIntent(AuthIntent.ShowReset(false)) }, Modifier.fillMaxWidth())
    }
}

/** Дата народження показується так, як її пишуть люди. */
private val BIRTH_DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("dd.MM.yyyy")
