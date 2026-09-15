package app.poruch.android.feature.account

import app.poruch.android.mvi.MviViewModel
import app.poruch.android.platform.NotificationPermission
import app.poruch.shared.PoruchApp

class ProfileViewModel(private val app: PoruchApp, private val notifications: NotificationPermission) :
    MviViewModel<ProfileState, ProfileIntent, ProfileEffect>(ProfileState()) {

    init {
        observe(app) { shared ->
            copy(
                signedIn = shared.signedIn,
                interests = shared.interests,
                needsAge = shared.needsAgeDeclaration,
                blocked = shared.blocked,
                mutating = shared.mutating,
                passwordRecovery = shared.passwordRecovery,
                // Після відновлення поле чистимо, щоб пароль не висів.
                newPassword = if (shared.passwordRecovery) newPassword else "",
                reminders = shared.remindersEnabled
            )
        }
    }

    override fun onIntent(intent: ProfileIntent) {
        when (intent) {
            ProfileIntent.SignIn -> send(ProfileEffect.SignIn)
            ProfileIntent.SignOut -> app.signOut()
            is ProfileIntent.ToggleInterest -> app.toggleInterest(intent.category)
            ProfileIntent.TuneRecommendations -> app.restartOnboarding()
            is ProfileIntent.ShowBirthDatePicker -> reduce { copy(pickingBirthDate = intent.show) }
            is ProfileIntent.SetBirthDate -> {
                reduce { copy(pickingBirthDate = false) }
                app.declareBirthDate(intent.value.toString())
            }
            is ProfileIntent.Unblock -> app.unblockUser(intent.userId)
            is ProfileIntent.SetNewPassword -> reduce { copy(newPassword = intent.value) }
            ProfileIntent.SavePassword -> app.updatePassword(state.value.newPassword)
            // Увімкнути можна лише з дозволом системи; без нього спершу питаємо, а стор чекає відповіді.
            is ProfileIntent.SetReminders ->
                if (intent.enabled && !notifications.granted()) send(ProfileEffect.AskNotificationPermission)
                else app.setRemindersEnabled(intent.enabled)
            is ProfileIntent.NotificationPermissionAnswered -> {
                reduce { copy(remindersDenied = !intent.granted) }
                app.setRemindersEnabled(intent.granted)
            }
        }
    }
}
