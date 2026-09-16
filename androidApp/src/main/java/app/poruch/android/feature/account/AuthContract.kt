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
    val pickingBirthDate: Boolean = false,
    /** Пошта, на яку пішов лист після реєстрації. Поки є — замість форми показуємо наступний крок. */
    val awaitingConfirmation: String? = null
) {
    val emailValid get() = AccountRules.isEmail(email)
    val birthDateValue: LocalDate? get() = runCatching { LocalDate.parse(birthDate) }.getOrNull()
    /** Мінімальний вік перевіряємо тут заради чесної кнопки; база перевірить ще раз. */
    val adult get() = birthDateValue?.let { it <= LocalDate.now().minusYears(SafetyRules.MIN_SIGNUP_AGE.toLong()) } == true
    /** Без `mutating`: під час запиту кнопка лишається кольоровою зі спінером, а не сірою. */
    val canSubmit get() = emailValid && AccountRules.isPassword(password) &&
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
    /** З кроку «перевірте пошту» назад до форми входу з тією ж поштою. */
    data object ConfirmedGoLogin : AuthIntent
    data object OpenMail : AuthIntent
    /** Умови й політика з підпису під кнопкою реєстрації. */
    data object OpenTerms : AuthIntent
    data object OpenPrivacy : AuthIntent
    data object Back : AuthIntent
}

sealed interface AuthEffect {
    /** Вхід вдався, екран закривається. */
    data object Close : AuthEffect
    /** Відкрити поштовий застосунок, якщо він є. */
    data object OpenMail : AuthEffect
    /** Відкрити сторінку в браузері. */
    data class OpenLink(val url: String) : AuthEffect
}
