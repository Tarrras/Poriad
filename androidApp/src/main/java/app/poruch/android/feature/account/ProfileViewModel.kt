package app.poruch.android.feature.account

import app.poruch.android.mvi.MviViewModel
import app.poruch.shared.PoruchApp

class ProfileViewModel(private val app: PoruchApp) :
    MviViewModel<ProfileState, ProfileIntent, ProfileEffect>(ProfileState()) {

    init {
        observe(app) { shared ->
            copy(
                signedIn = shared.signedIn,
                interests = shared.interests,
                mutating = shared.mutating,
                passwordRecovery = shared.passwordRecovery,
                // Clearing the field once recovery is over keeps a typed password from lingering.
                newPassword = if (shared.passwordRecovery) newPassword else ""
            )
        }
    }

    override fun onIntent(intent: ProfileIntent) {
        when (intent) {
            ProfileIntent.SignIn -> send(ProfileEffect.SignIn)
            ProfileIntent.SignOut -> app.signOut()
            is ProfileIntent.ToggleInterest -> app.toggleInterest(intent.category)
            is ProfileIntent.SetNewPassword -> reduce { copy(newPassword = intent.value) }
            ProfileIntent.SavePassword -> app.updatePassword(state.value.newPassword)
        }
    }
}
