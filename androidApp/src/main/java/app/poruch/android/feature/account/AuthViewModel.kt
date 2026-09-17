package app.poruch.android.feature.account

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.LegalLinks
import app.poruch.shared.AppMessage
import app.poruch.shared.AppNotice
import app.poruch.shared.PoruchApp

class AuthViewModel(private val app: PoruchApp) : MviViewModel<AuthState, AuthIntent, AuthEffect>(AuthState()) {
    init {
        observe(app) { shared ->
            // Лист відновлення веде на профіль: пароль треба задати, а не ввести.
            if (shared.signedIn && !signedIn && !shared.passwordRecovery) send(AuthEffect.Close)
            copy(
                mutating = shared.mutating, signedIn = shared.signedIn, awaitingConfirmation = shared.awaitingConfirmation,
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
