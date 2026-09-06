package app.poruch.android.feature.account

import app.poruch.domain.AccountRules

data class AuthState(
    val signup: Boolean = false,
    val email: String = "",
    val name: String = "",
    val password: String = "",
    val passwordRevealed: Boolean = false,
    val mutating: Boolean = false,
    val signedIn: Boolean = false
) {
    val emailValid get() = AccountRules.isEmail(email)
    val canSubmit get() = !mutating && emailValid && AccountRules.isPassword(password) &&
        (!signup || AccountRules.isName(name))
}

sealed interface AuthIntent {
    data class SetEmail(val value: String) : AuthIntent
    data class SetName(val value: String) : AuthIntent
    data class SetPassword(val value: String) : AuthIntent
    data object TogglePasswordReveal : AuthIntent
    data object ToggleMode : AuthIntent
    data object Submit : AuthIntent
    data object ResetPassword : AuthIntent
    data object Back : AuthIntent
}

sealed interface AuthEffect {
    /** Sign-in succeeded and the screen has done its job. */
    data object Close : AuthEffect
}
