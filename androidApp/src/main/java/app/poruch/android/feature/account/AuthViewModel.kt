package app.poruch.android.feature.account

import app.poruch.android.mvi.MviViewModel
import app.poruch.shared.PoruchApp

class AuthViewModel(private val app: PoruchApp) : MviViewModel<AuthState, AuthIntent, AuthEffect>(AuthState()) {
    init {
        observe(app) { shared ->
            // A recovery link lands on the profile instead: the reader has a password to set, not to enter.
            if (shared.signedIn && !signedIn && !shared.passwordRecovery) send(AuthEffect.Close)
            copy(mutating = shared.mutating, signedIn = shared.signedIn)
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
            // The password never survives a mode switch: it belongs to the attempt, not the screen.
            AuthIntent.ToggleMode -> reduce { copy(signup = !signup, password = "") }
            AuthIntent.Submit -> state.value.let {
                if (it.signup) app.signUp(it.email.trim(), it.password, it.name.trim(), it.birthDate)
                else app.signIn(it.email.trim(), it.password)
            }
            AuthIntent.ResetPassword -> app.requestPasswordReset(state.value.email.trim())
            AuthIntent.Back -> send(AuthEffect.Close)
        }
    }
}
