package app.poruch.android.feature.account

import app.poruch.android.navigation.AuthReason
import app.poruch.domain.AccountRules

data class AuthState(
    val signup: Boolean = false,
    /** З якою дією прийшов гість: підзаголовок каже, навіщо профіль саме зараз. */
    val reason: AuthReason = AuthReason.GENERAL,
    val email: String = "",
    val name: String = "",
    val password: String = "",
    val passwordRevealed: Boolean = false,
    val mutating: Boolean = false,
    /** Вхід завершено, екран закривається: ефект [AuthEffect.SignedIn] уже пішов. */
    val finished: Boolean = false,
    /** Кнопка «Продовжити з Google»: є, коли збірка знає Web client ID. */
    val googleAvailable: Boolean = false,
    /** Увійшли через Google чи кодом, а віку в акаунта нема: замість форми — галочка «Мені вже є 18». */
    val askAdult: Boolean = false,
    /** Галочка «Мені вже є 18»: при реєстрації й на кроці після входу. */
    val adult: Boolean = false,
    /** Пошта, на яку пішов лист після реєстрації. Поки є — замість форми показуємо наступний крок. */
    val awaitingConfirmation: String? = null,
    /** Крок «Забули пароль?»: та сама пошта, окремий екран, щоб кнопка не залежала від форми входу. */
    val resetting: Boolean = false,
    /** «Увійти кодом з пошти»: пошта й «Надіслати код» замість форми. */
    val codeMode: Boolean = false,
    /** Пошта, на яку пішов код: поки є — поле коду. */
    val awaitingCode: String? = null,
    val code: String = "",
    /** Скільки секунд до «Надіслати ще раз»: Supabase шле код не частіше за раз на хвилину. */
    val resendIn: Int = 0
) {
    val emailValid get() = AccountRules.isEmail(email)
    /** Без `mutating`: під час запиту кнопка лишається кольоровою зі спінером, а не сірою. */
    val canSubmit get() = emailValid && AccountRules.isPassword(password) &&
        (!signup || (AccountRules.isName(name) && adult))
    /** Код з листа — цифри; довжину задає проєкт Supabase (6 за замовчуванням), тож не прибиваємо її. */
    val canVerify get() = code.length in CODE_LENGTH && code.all(Char::isDigit)

    companion object {
        val CODE_LENGTH = 6..10
    }
}

sealed interface AuthIntent {
    data class SetEmail(val value: String) : AuthIntent
    data class SetName(val value: String) : AuthIntent
    data class SetPassword(val value: String) : AuthIntent
    data class SetAdult(val value: Boolean) : AuthIntent
    data object TogglePasswordReveal : AuthIntent
    data object ToggleMode : AuthIntent
    data object Submit : AuthIntent
    data object SignInWithGoogle : AuthIntent
    /** Аркуш Google повернув токен для nonce з [AuthEffect.RequestGoogleToken]. */
    data class GoogleToken(val idToken: String) : AuthIntent
    /** Галочка після входу через Google чи кодом. */
    data object ConfirmAdult : AuthIntent
    /** «Увійти кодом з пошти» і назад до форми. */
    data class ShowCode(val show: Boolean) : AuthIntent
    data class SetCode(val value: String) : AuthIntent
    /** «Надіслати код» і «Надіслати ще раз». */
    data object SendCode : AuthIntent
    data object VerifyCode : AuthIntent
    /** З кроку коду назад до пошти. */
    data object OtherEmail : AuthIntent
    data class ShowReset(val show: Boolean) : AuthIntent
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
    /** Людина вийшла з екрана сама: «назад». */
    data object Close : AuthEffect
    /** Вхід вдався: екран закривається; під ним редактор, якщо гість прийшов з «Опублікувати», — там подія публікується сама. */
    data object SignedIn : AuthEffect
    /** Показати аркуш Google; [nonce] — SHA-256 для токена, сирий чекає в спільному шарі. */
    data class RequestGoogleToken(val nonce: String) : AuthEffect
    /** Відкрити поштовий застосунок, якщо він є. */
    data object OpenMail : AuthEffect
    /** Відкрити сторінку в браузері. */
    data class OpenLink(val url: String) : AuthEffect
}
