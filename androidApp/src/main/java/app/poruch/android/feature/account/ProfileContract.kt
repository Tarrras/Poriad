package app.poruch.android.feature.account

import app.poruch.domain.AccountRules
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
    val remindersDenied: Boolean = false
) {
    val canSavePassword get() = !mutating && AccountRules.isPassword(newPassword)
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
    data class SetReminders(val enabled: Boolean) : ProfileIntent
    /** Відповідь системи на запит дозволу, який маршрут показав за [ProfileEffect.AskNotificationPermission]. */
    data class NotificationPermissionAnswered(val granted: Boolean) : ProfileIntent
}

sealed interface ProfileEffect {
    data object SignIn : ProfileEffect
    data object AskNotificationPermission : ProfileEffect
}
