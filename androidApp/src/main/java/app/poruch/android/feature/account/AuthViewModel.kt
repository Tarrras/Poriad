package app.poruch.android.feature.account

import androidx.lifecycle.viewModelScope
import app.poruch.android.navigation.AuthReason
import app.poruch.android.mvi.MviViewModel
import app.poruch.android.platform.googleSignInAvailable
import app.poruch.domain.IdProvider
import app.poruch.domain.LegalLinks
import app.poruch.shared.AppMessage
import app.poruch.shared.AppNotice
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** [reason] — з чим прийшов гість: підзаголовок каже, навіщо профіль саме зараз. */
class AuthViewModel(private val app: PoruchApp, reason: AuthReason = AuthReason.GENERAL) :
    MviViewModel<AuthState, AuthIntent, AuthEffect>(
        AuthState(reason = reason, googleAvailable = googleSignInAvailable)
    ) {
    /**
     * Кроки «перевірте пошту» й «код з листа», з яких людина повернулась до форми. Ховаємо їх тут, а не
     * `dismissConfirmationStep()`: той скасовує й відкладену публікацію гостя, а людина ще входить.
     */
    private var dismissedConfirmation: String? = null
    private var dismissedCode: String? = null
    private var countdown: Job? = null

    init {
        reason.wall?.let(app::authWall)
        observe(app) { shared ->
            // Закриваємось, коли вхід доїхав до кінця: після Google чи коду спільний шар ще питає, чи є вік, і без нього
            // екран лишається на галочці. Так само тримає вхід і гостьова публікація (`publishAfterSignIn`). Лист
            // відновлення веде на профіль.
            val done = shared.signedIn && !shared.mutating && !shared.session.askBirthDate && !shared.session.passwordRecovery
            if (done && !finished) send(AuthEffect.SignedIn)
            copy(
                mutating = shared.mutating, finished = finished || done, askAdult = shared.session.askBirthDate,
                awaitingConfirmation = shared.session.awaitingConfirmation?.takeIf { it != dismissedConfirmation },
                awaitingCode = shared.session.awaitingCode?.takeIf { it != dismissedCode },
                // Лист пішов — повертаємось до входу, банер скаже решту.
                resetting = resetting && shared.notice != AppNotice.Told(AppMessage.RECOVERY_SENT)
            )
        }
    }

    override fun onIntent(intent: AuthIntent) {
        when (intent) {
            is AuthIntent.SetEmail -> reduce { copy(email = intent.value) }
            is AuthIntent.SetName -> reduce { copy(name = intent.value) }
            is AuthIntent.SetPassword -> reduce { copy(password = intent.value) }
            is AuthIntent.SetAdult -> reduce { copy(adult = intent.value) }
            AuthIntent.TogglePasswordReveal -> reduce { copy(passwordRevealed = !passwordRevealed) }
            // Пароль не переживає зміну режиму.
            AuthIntent.ToggleMode -> reduce { copy(signup = !signup, password = "") }
            AuthIntent.Submit -> state.value.let {
                dismissedConfirmation = null
                if (it.signup) app.signUp(it.email.trim(), it.password, it.name.trim())
                else app.signIn(it.email.trim(), it.password)
            }
            AuthIntent.SignInWithGoogle -> send(AuthEffect.RequestGoogleToken(app.idTokenNonce()))
            is AuthIntent.GoogleToken -> app.signInWithIdToken(IdProvider.GOOGLE, intent.idToken)
            AuthIntent.ConfirmAdult -> app.confirmAdult()
            is AuthIntent.ShowCode -> reduce { copy(codeMode = intent.show, code = "") }
            // Лише цифри: вставлений з листа код буває з пробілами.
            is AuthIntent.SetCode -> reduce { copy(code = intent.value.filter(Char::isDigit).take(AuthState.CODE_LENGTH.last)) }
            AuthIntent.SendCode -> {
                dismissedCode = null
                app.sendSignInCode(state.value.email.trim())
                startCountdown()
            }
            AuthIntent.VerifyCode -> state.value.let { app.verifySignInCode(it.awaitingCode ?: it.email.trim(), it.code) }
            AuthIntent.OtherEmail -> {
                dismissedCode = state.value.awaitingCode
                reduce { copy(awaitingCode = null, code = "") }
            }
            is AuthIntent.ShowReset -> reduce { copy(resetting = intent.show) }
            AuthIntent.ResetPassword -> app.requestPasswordReset(state.value.email.trim())
            // Лист підтверджено: пошта вже в полі, лишається пароль.
            AuthIntent.ConfirmedGoLogin -> {
                dismissedConfirmation = state.value.awaitingConfirmation
                reduce { copy(awaitingConfirmation = null, signup = false, password = "") }
            }
            AuthIntent.OpenMail -> send(AuthEffect.OpenMail)
            AuthIntent.OpenTerms -> send(AuthEffect.OpenLink(LegalLinks.TERMS))
            AuthIntent.OpenPrivacy -> send(AuthEffect.OpenLink(LegalLinks.PRIVACY))
            AuthIntent.Back -> state.value.let {
                when {
                    it.resetting -> reduce { copy(resetting = false) }
                    it.codeMode && it.awaitingCode != null && !it.askAdult -> onIntent(AuthIntent.OtherEmail)
                    it.codeMode && !it.askAdult -> reduce { copy(codeMode = false) }
                    // Закрили вхід: гість лишається в редакторі з чернеткою, а сама публікація скасована (спільний шар).
                    else -> { app.dismissConfirmationStep(); send(AuthEffect.Close) }
                }
            }
        }
    }

    private fun startCountdown() {
        countdown?.cancel()
        countdown = viewModelScope.launch {
            for (left in RESEND_SECONDS downTo 0) {
                reduce { copy(resendIn = left) }
                if (left > 0) delay(1_000)
            }
        }
    }

    private companion object {
        const val RESEND_SECONDS = 60
    }
}
