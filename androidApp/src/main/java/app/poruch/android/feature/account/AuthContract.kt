package app.poruch.android.feature.account

import app.poruch.domain.AccountRules
import app.poruch.domain.SafetyRules
import java.time.LocalDate

data class AuthState(
    val signup: Boolean = false,
    val email: String = "",
    val name: String = "",
    val password: String = "",
    val passwordRevealed: Boolean = false,
    val mutating: Boolean = false,
    val signedIn: Boolean = false,
    /** ISO-8601, порожньо до вибору. Лише для реєстрації. */
    val birthDate: String = "",
    val pickingBirthDate: Boolean = false
) {
    val emailValid get() = AccountRules.isEmail(email)
    val birthDateValue: LocalDate? get() = runCatching { LocalDate.parse(birthDate) }.getOrNull()
    /** Мінімальний вік перевіряємо тут заради чесної кнопки; база перевірить ще раз. */
    val adult get() = birthDateValue?.let { it <= LocalDate.now().minusYears(SafetyRules.MIN_SIGNUP_AGE.toLong()) } == true
    val canSubmit get() = !mutating && emailValid && AccountRules.isPassword(password) &&
        (!signup || (AccountRules.isName(name) && adult))
}

sealed interface AuthIntent {
    data class SetEmail(val value: String) : AuthIntent
    data class SetName(val value: String) : AuthIntent
    data class SetPassword(val value: String) : AuthIntent
    data class SetBirthDate(val value: LocalDate) : AuthIntent
    data class ShowBirthDatePicker(val show: Boolean) : AuthIntent
    data object TogglePasswordReveal : AuthIntent
    data object ToggleMode : AuthIntent
    data object Submit : AuthIntent
    data object ResetPassword : AuthIntent
    data object Back : AuthIntent
}

sealed interface AuthEffect {
    /** Вхід вдався, екран закривається. */
    data object Close : AuthEffect
}
