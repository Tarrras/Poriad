package app.poruch.android.feature.account

import app.poruch.domain.AccountRules
import app.poruch.domain.AppError
import app.poruch.domain.Attendee
import java.time.LocalDate

data class ProfileState(
    val signedIn: Boolean = false,
    val interests: List<String> = emptyList(),
    /** Акаунт без віку має його вказати, перш ніж приєднуватись. */
    val needsAge: Boolean = false,
    val pickingBirthDate: Boolean = false,
    val blocked: List<Attendee> = emptyList(),
    val mutating: Boolean = false,
    val passwordRecovery: Boolean = false,
    val newPassword: String = "",
    /** Перемикач нагадувань зі спільного стану. */
    val reminders: Boolean = false,
    /** Людина відмовила в дозволі на сповіщення: перемикач лишається вимкненим, підпис каже чому. */
    val remindersDenied: Boolean = false,
    /** Шторка видалення акаунта відкрита; пароль живе лише в ній. */
    val deleting: Boolean = false,
    val deletePassword: String = "",
    /** Помилка видалення показується в шторці: банер під нею не видно. */
    val deleteError: AppError? = null,
    /** Шторка зміни пароля: поточний і новий живуть лише в ній. */
    val changingPassword: Boolean = false,
    val currentPassword: String = "",
    val changeError: AppError? = null,
    /** Повтор і показ пароля на екрані нового пароля після листа відновлення. */
    val newPasswordConfirm: String = "",
    val newPasswordRevealed: Boolean = false,
    val version: String = ""
) {
    val canSavePassword get() = !mutating && AccountRules.isPassword(newPassword)
    /** Помилку показуємо лише коли в повторі вже щось є: порожнє поле — ще не помилка. */
    val passwordsMismatch get() = newPasswordConfirm.isNotEmpty() && newPasswordConfirm != newPassword
    val canSetNewPassword get() = canSavePassword && newPasswordConfirm == newPassword
    val canChangePassword get() = canSavePassword && currentPassword.isNotEmpty()
    val canDelete get() = AccountRules.isPassword(deletePassword)
}

sealed interface ProfileIntent {
    data object SignIn : ProfileIntent
    data object SignOut : ProfileIntent
    data class ToggleInterest(val category: String) : ProfileIntent
    data object TuneRecommendations : ProfileIntent
    data class ShowBirthDatePicker(val show: Boolean) : ProfileIntent
    data class SetBirthDate(val value: LocalDate) : ProfileIntent
    data class Unblock(val userId: String) : ProfileIntent
    data class SetNewPassword(val value: String) : ProfileIntent
    data object SavePassword : ProfileIntent
    data class SetNewPasswordConfirm(val value: String) : ProfileIntent
    data object ToggleNewPasswordReveal : ProfileIntent
    data class SetReminders(val enabled: Boolean) : ProfileIntent
    /** Відповідь системи на запит дозволу, який маршрут показав за [ProfileEffect.AskNotificationPermission]. */
    data class NotificationPermissionAnswered(val granted: Boolean) : ProfileIntent
    data object OpenPrivacy : ProfileIntent
    data object OpenTerms : ProfileIntent
    data object ContactSupport : ProfileIntent
    data class ShowDeleteAccount(val show: Boolean) : ProfileIntent
    data class SetDeletePassword(val value: String) : ProfileIntent
    data object ConfirmDeleteAccount : ProfileIntent
    data class ShowChangePassword(val show: Boolean) : ProfileIntent
    data class SetCurrentPassword(val value: String) : ProfileIntent
    data object ConfirmChangePassword : ProfileIntent
}

sealed interface ProfileEffect {
    data object SignIn : ProfileEffect
    data object AskNotificationPermission : ProfileEffect
    data class OpenLink(val url: String) : ProfileEffect
    data class WriteEmail(val address: String) : ProfileEffect
}
