package app.poruch.android.feature.account

import app.poruch.android.mvi.MviViewModel
import app.poruch.android.platform.googleSignInAvailable
import app.poruch.domain.IdProvider
import app.poruch.domain.LegalLinks
import app.poruch.shared.AppMessage
import app.poruch.shared.AppNotice
import app.poruch.shared.PoruchApp

/** [creating] — гість тапнув «Створити»: реєстрація за замовчуванням (найімовірніше новачок) і слова про подію. */
class AuthViewModel(private val app: PoruchApp, creating: Boolean = false) :
    MviViewModel<AuthState, AuthIntent, AuthEffect>(
        AuthState(signup = creating, creating = creating, googleAvailable = googleSignInAvailable)
    ) {
    init {
        observe(app) { shared ->
            // Закриваємось, коли вхід доїхав до кінця: після Google спільний шар ще питає, чи є дата
            // народження, і без неї екран лишається на кроці дати. Лист відновлення веде на профіль.
            val done = shared.signedIn && !shared.mutating && !shared.session.askBirthDate && !shared.session.passwordRecovery
            if (done && !finished) send(AuthEffect.SignedIn)
            copy(
                mutating = shared.mutating, finished = finished || done, askBirthDate = shared.session.askBirthDate,
                awaitingConfirmation = shared.session.awaitingConfirmation,
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
            is AuthIntent.SetBirthDate -> reduce { copy(birthDate = intent.value.toString(), pickingBirthDate = false) }
            is AuthIntent.ShowBirthDatePicker -> reduce { copy(pickingBirthDate = intent.show) }
            AuthIntent.TogglePasswordReveal -> reduce { copy(passwordRevealed = !passwordRevealed) }
            // Пароль не переживає зміну режиму.
            AuthIntent.ToggleMode -> reduce { copy(signup = !signup, password = "") }
            AuthIntent.Submit -> state.value.let {
                if (it.signup) app.signUp(it.email.trim(), it.password, it.name.trim(), it.birthDate)
                else app.signIn(it.email.trim(), it.password)
            }
            AuthIntent.SignInWithGoogle -> send(AuthEffect.RequestGoogleToken(app.idTokenNonce()))
            is AuthIntent.GoogleToken -> app.signInWithIdToken(IdProvider.GOOGLE, intent.idToken)
            AuthIntent.DeclareBirthDate -> app.declareBirthDate(state.value.birthDate)
            is AuthIntent.ShowReset -> reduce { copy(resetting = intent.show) }
            AuthIntent.ResetPassword -> app.requestPasswordReset(state.value.email.trim())
            // Лист підтверджено: пошта вже в полі, лишається пароль.
            AuthIntent.ConfirmedGoLogin -> { app.dismissConfirmationStep(); reduce { copy(signup = false, password = "") } }
            AuthIntent.OpenMail -> send(AuthEffect.OpenMail)
            AuthIntent.OpenTerms -> send(AuthEffect.OpenLink(LegalLinks.TERMS))
            AuthIntent.OpenPrivacy -> send(AuthEffect.OpenLink(LegalLinks.PRIVACY))
            AuthIntent.Back ->
                if (state.value.resetting) reduce { copy(resetting = false) }
                else { app.dismissConfirmationStep(); send(AuthEffect.Close) }
        }
    }
}
