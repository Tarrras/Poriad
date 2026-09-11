package app.poruch.android.feature.account

import app.poruch.domain.AccountRules
import app.poruch.domain.Attendee
import java.time.LocalDate

data class ProfileState(
    val signedIn: Boolean = false,
    val interests: List<String> = emptyList(),
    /** An account made before the app asked for an age has to state one before it can join. */
    val needsAge: Boolean = false,
    val pickingBirthDate: Boolean = false,
    val blocked: List<Attendee> = emptyList(),
    val mutating: Boolean = false,
    val passwordRecovery: Boolean = false,
    val newPassword: String = ""
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
}

sealed interface ProfileEffect {
    data object SignIn : ProfileEffect
}
