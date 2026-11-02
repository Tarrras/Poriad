package app.poruch.android.feature.account

import app.poruch.android.navigation.AuthReason
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
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
import androidx.compose.ui.unit.sp
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.autofill.ContentType
import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import app.poruch.android.R
import app.poruch.android.ui.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction

/**
 * Вхід (рішення власника 02.11, docs/design-wow-1.5.md «Вхід кодом з пошти»): один шлях поштою — код з листа. Google, далі
 * пошта й «Надіслати код» на першому екрані; пароль — текстовим посиланням для наявних акаунтів, реєстрації з паролем
 * нема: новий профіль — кодом чи Google, і далі галочка 18+.
 */
@Composable
fun AuthScreen(state: AuthState, onIntent: (AuthIntent) -> Unit) {
    val colors = Poruch.colors
    // Системний «назад» — як стрілка: з «Забули пароль?» до пароля, з пароля чи коду — до пошти, далі — закрити.
    BackHandler { onIntent(AuthIntent.Back) }
    val confirming = state.awaitingConfirmation != null
    val coding = state.awaitingCode != null && !state.passwordMode && !state.askAdult
    Column(Modifier.fillMaxSize().background(colors.canvas).imePadding().verticalScroll(rememberScrollState())) {
        // Знак застосунку й назва по центру, як вхід в Apple ID; «назад» окремо в кутку.
        Column(
            Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = Spacing.page).padding(bottom = Spacing.sm),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Box(Modifier.fillMaxWidth().padding(top = Spacing.md)) {
                IconPill(PoruchIcons.arrowLeft, stringResource(R.string.back), size = 40.dp) { onIntent(AuthIntent.Back) }
            }
            Box(Modifier.size(64.dp).background(colors.brand, CircleShape), contentAlignment = Alignment.Center) {
                Icon(
                    when {
                        confirming -> PoruchIcons.checkCircle; state.resetting -> PoruchIcons.lock
                        state.askAdult -> PoruchIcons.shield; coding -> PoruchIcons.mail; else -> PoruchIcons.pin
                    },
                    null, Modifier.size(28.dp), tint = colors.onBrand
                )
            }
            Text(
                stringResource(
                    when {
                        confirming -> R.string.auth_check_email_title
                        state.resetting -> R.string.auth_reset_title
                        state.askAdult -> R.string.auth_birth_date_title
                        coding -> R.string.auth_code_field
                        else -> R.string.auth_welcome
                    }
                ),
                style = PoruchType.brandTitle1, color = colors.ink, textAlign = TextAlign.Center,
                modifier = Modifier.semantics { heading() }
            )
            Text(
                when {
                    confirming -> stringResource(R.string.auth_check_email_subtitle)
                    state.resetting -> stringResource(R.string.auth_reset_subtitle)
                    state.askAdult -> stringResource(R.string.auth_adult_subtitle)
                    coding -> stringResource(R.string.auth_code_sent, state.awaitingCode.orEmpty())
                    // Навіщо профіль саме зараз: гість прийшов з дією, і рядок під заголовком — про неї.
                    else -> stringResource(
                        when (state.reason) {
                            // Гість уже заповнив редактор і натиснув «Опублікувати».
                            AuthReason.CREATE -> R.string.auth_subtitle_publish
                            AuthReason.JOIN -> R.string.auth_reason_join
                            AuthReason.FOLLOW -> R.string.auth_reason_follow
                            AuthReason.COMPANY -> R.string.auth_reason_company
                            AuthReason.GENERAL -> R.string.auth_guest_note
                        }
                    )
                },
                style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary, textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = Spacing.lg)
            )
        }
        when {
            confirming -> ConfirmationStep(state.awaitingConfirmation.orEmpty(), onIntent)
            state.resetting -> ResetStep(state, onIntent)
            state.askAdult -> AdultStep(state, onIntent)
            state.passwordMode -> PasswordStep(state, onIntent)
            coding -> CodeStep(state, state.awaitingCode.orEmpty(), onIntent)
            else -> EmailStep(state, onIntent)
        }
    }
}

/**
 * Перший екран: Google, згода дрібним, «або поштою», пошта й «Надіслати код», «Увійти з паролем» посиланням. Згода —
 * одразу під Google: тап по ньому створює профіль, тож її видно до тапу на будь-якому екрані без прокрутки, і вона ж
 * стоїть над «Надіслати код».
 */
@Composable
private fun EmailStep(state: AuthState, onIntent: (AuthIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        if (state.googleAvailable) {
            ProviderButton(
                painterResource(R.drawable.ic_google), stringResource(R.string.continue_with_google),
                { onIntent(AuthIntent.SignInWithGoogle) }, enabled = !state.mutating
            )
            AdultCheck(state.adult, compact = true, missing = state.adultMissing) { onIntent(AuthIntent.SetAdult(it)) }
            ConsentNote(onIntent)
            OrDivider(stringResource(R.string.auth_or_email))
        }
        // Без автофокусу: клавіатура закрила б Google і згоду, а пошту людина обирає сама.
        LabelledField(
            stringResource(R.string.email), state.email, { onIntent(AuthIntent.SetEmail(it)) },
            placeholder = stringResource(R.string.email_placeholder),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false, imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { if (state.emailValid && !state.mutating) onIntent(AuthIntent.SendCode) })
        )
        if (!state.googleAvailable) AdultCheck(state.adult, compact = true, missing = state.adultMissing) { onIntent(AuthIntent.SetAdult(it)) }
        PrimaryButton(
            stringResource(R.string.auth_code_send), { onIntent(AuthIntent.SendCode) },
            Modifier.fillMaxWidth(), icon = PoruchIcons.mail, enabled = state.emailValid, loading = state.mutating
        )
        // Без Google згода — під кнопкою коду: дотик до неї вже створює профіль.
        if (!state.googleAvailable) ConsentNote(onIntent)
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            GhostButton(
                stringResource(R.string.auth_password_link), { onIntent(AuthIntent.ShowPassword(true)) },
                tone = colors.inkSecondary, enabled = !state.mutating
            )
        }
    }
}

/** «Увійти з паролем»: наявна форма входу — пошта, пароль, «Забули пароль?». Пошта переноситься з першого екрана. */
@Composable
private fun PasswordStep(state: AuthState, onIntent: (AuthIntent) -> Unit) {
    val colors = Poruch.colors
    val emailField = remember { FocusRequester() }
    val passwordField = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { if (state.emailValid) passwordField.requestFocus() else emailField.requestFocus() } }
    Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        LabelledField(
            stringResource(R.string.email), state.email, { onIntent(AuthIntent.SetEmail(it)) },
            focusRequester = emailField,
            placeholder = stringResource(R.string.email_placeholder),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false)
        )
        LabelledField(
            stringResource(R.string.password_label), state.password, { onIntent(AuthIntent.SetPassword(it)) },
            focusRequester = passwordField,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            visualTransformation = if (state.passwordRevealed) VisualTransformation.None else PasswordVisualTransformation(),
            trailing = { PasswordRevealIcon(state.passwordRevealed) { onIntent(AuthIntent.TogglePasswordReveal) } }
        )
        PrimaryButton(
            stringResource(R.string.login), { onIntent(AuthIntent.Submit) },
            Modifier.fillMaxWidth(), enabled = state.canSubmit, loading = state.mutating
        )
        // По центру, як «Видалити обліковий запис» у профілі: текстова кнопка з лівим відступом виглядала зсунутою.
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            GhostButton(
                stringResource(R.string.forgot_password), { onIntent(AuthIntent.ShowReset(true)) },
                tone = colors.inkSecondary, enabled = !state.mutating
            )
        }
    }
}

/** Кнопка входу через провайдера: знак провайдера в оригінальних кольорах, світла пігулка. */
@Composable
private fun ProviderButton(logo: Painter, text: String, onClick: () -> Unit, enabled: Boolean, tint: Color? = null) {
    val colors = Poruch.colors
    Row(
        // Великий шрифт переносить напис і робить кнопку вищою, а не обрізає «Продовжити з Goo…».
        Modifier.fillMaxWidth().heightIn(min = 52.dp).background(colors.surface, ButtonShape).border(1.dp, colors.hairline, ButtonShape)
            .clip(ButtonShape).pressable(enabled = enabled, onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md, Alignment.CenterHorizontally)
    ) {
        Image(logo, null, Modifier.size(20.dp), colorFilter = tint?.let { ColorFilter.tint(it) })
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
 * Після входу через Google чи кодом: провайдер вік не каже, а «Поряд» — для повнолітніх. Та сама галочка, що при
 * реєстрації; «назад» лишає людину в акаунті, і картка віку чекатиме в профілі.
 */
@Composable
private fun AdultStep(state: AuthState, onIntent: (AuthIntent) -> Unit) {
    Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        AdultCheck(state.adult) { onIntent(AuthIntent.SetAdult(it)) }
        PrimaryButton(
            stringResource(R.string.auth_birth_date_continue), { onIntent(AuthIntent.ConfirmAdult) },
            Modifier.fillMaxWidth(), enabled = state.adult, loading = state.mutating
        )
    }
}

/**
 * «Мені вже є 18» з підписом, навіщо: увесь рядок — одна ціль, і TalkBack читає підпис разом зі станом. [compact] — на
 * першому екрані входу: один тихий рядок без картки й підпису, як згода під ним (власник 02.11: окремий крок про вік
 * лякає). [missing] — її пропустили й натиснули вхід: колір помилки, віддача й рядок, який TalkBack читає сам.
 */
@Composable
internal fun AdultCheck(checked: Boolean, compact: Boolean = false, missing: Boolean = false, onChange: (Boolean) -> Unit) {
    val colors = Poruch.colors
    val view = LocalView.current
    LaunchedEffect(missing) {
        if (missing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) view.performHapticFeedback(HapticFeedbackConstants.REJECT)
    }
    Row(
        Modifier.fillMaxWidth().then(if (compact) Modifier.heightIn(min = 48.dp) else Modifier.cardSurface())
            .toggleable(checked, role = Role.Checkbox, onValueChange = onChange)
            .then(if (compact) Modifier else Modifier.padding(Spacing.lg)),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (compact) Spacing.sm else Spacing.md)
    ) {
        Checkbox(
            checked, null,
            colors = CheckboxDefaults.colors(
                checkedColor = colors.brand, checkmarkColor = colors.onBrand, uncheckedColor = if (missing) colors.danger else colors.inkTertiary
            )
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                stringResource(R.string.adult_confirm),
                style = if (compact) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.titleSmall,
                color = if (missing) colors.danger else if (compact) colors.inkSecondary else colors.ink
            )
            if (!compact) Text(stringResource(R.string.adult_confirm_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
            else if (missing) Text(
                stringResource(R.string.adult_confirm_needed), Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                style = MaterialTheme.typography.bodySmall, color = colors.danger
            )
        }
    }
}

/**
 * Крок 2: код з листа. Цифри — голосом корінця (Sofia Sans Extra Condensed, табличні, розрідка 6), поле одразу у фокусі,
 * а система пропонує код сама. «Надіслати ще раз» — після хвилини, як дозволяє Supabase; поруч «Інша пошта».
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CodeStep(state: AuthState, email: String, onIntent: (AuthIntent) -> Unit) {
    val colors = Poruch.colors
    val codeField = remember { FocusRequester() }
    LaunchedEffect(email) { runCatching { codeField.requestFocus() } }
    Column(Modifier.padding(Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        LabelledField(
            stringResource(R.string.auth_code_field), state.code, { onIntent(AuthIntent.SetCode(it)) },
            focusRequester = codeField,
            // Number, а не NumberPassword: код приходить листом, і Gboard у полі пароля не пропонує вставку з буфера.
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { if (state.canVerify && !state.mutating) onIntent(AuthIntent.VerifyCode) }),
            textStyle = PoruchType.numeral.copy(fontSize = 28.sp, lineHeight = 32.sp, letterSpacing = 6.sp),
            contentType = ContentType.SmsOtpCode
        )
        PrimaryButton(
            stringResource(R.string.login), { onIntent(AuthIntent.VerifyCode) },
            Modifier.fillMaxWidth(), enabled = state.canVerify, loading = state.mutating
        )
        FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            GhostButton(
                if (state.resendIn > 0) stringResource(R.string.auth_code_resend_in, state.resendIn) else stringResource(R.string.auth_code_resend),
                { onIntent(AuthIntent.SendCode) }, tone = colors.inkSecondary, enabled = state.resendIn == 0 && !state.mutating
            )
            GhostButton(stringResource(R.string.auth_code_other_email), { onIntent(AuthIntent.OtherEmail) }, tone = colors.inkSecondary)
        }
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


@Preview(widthDp = 360, heightDp = 800)
@Composable
private fun AuthEmailPreview() = PoruchTheme(dark = false) {
    AuthScreen(AuthState(reason = AuthReason.CREATE, googleAvailable = true)) {}
}

@Preview(widthDp = 360, heightDp = 800)
@Composable
private fun AuthCodePreview() = PoruchTheme(dark = true) {
    AuthScreen(AuthState(awaitingCode = "you@example.com", code = "482915", resendIn = 42)) {}
}
