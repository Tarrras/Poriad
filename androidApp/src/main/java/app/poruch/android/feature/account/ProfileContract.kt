package app.poruch.android.feature.account

import app.poruch.domain.AccountRules

data class ProfileState(
    val signedIn: Boolean = false,
    val interests: List<String> = emptyList(),
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
    data class SetNewPassword(val value: String) : ProfileIntent
    data object SavePassword : ProfileIntent
}

sealed interface ProfileEffect {
    data object SignIn : ProfileEffect
}
