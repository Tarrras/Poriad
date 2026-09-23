package app.poruch.android.feature.account

import app.poruch.android.BuildConfig
import app.poruch.android.mvi.MviViewModel
import app.poruch.android.platform.NotificationPermission
import app.poruch.domain.LegalLinks
import app.poruch.shared.AppMessage
import app.poruch.shared.AppNotice
import app.poruch.shared.PoruchApp

class ProfileViewModel(private val app: PoruchApp, private val notifications: NotificationPermission) :
    MviViewModel<ProfileState, ProfileIntent, ProfileEffect>(ProfileState(version = BuildConfig.VERSION_NAME)) {

    init {
        observe(app) { shared ->
            copy(
                signedIn = shared.signedIn,
                interests = shared.interests,
                needsAge = shared.needsAgeDeclaration,
                blocked = shared.library.blocked,
                mutating = shared.mutating,
                passwordRecovery = shared.session.passwordRecovery,
                // Після відновлення чи зміни поле чистимо, щоб пароль не висів.
                newPassword = if (shared.session.passwordRecovery || changingPassword) newPassword else "",
                newPasswordConfirm = if (shared.session.passwordRecovery) newPasswordConfirm else "",
                // Пароль змінено або сесії нема — шторка зміни закривається разом із полями.
                changingPassword = changingPassword && shared.signedIn && shared.notice != AppNotice.Told(AppMessage.PASSWORD_CHANGED),
                currentPassword = if (changingPassword && shared.signedIn) currentPassword else "",
                changeError = (shared.notice as? AppNotice.Failed)?.error?.takeIf { changingPassword && shared.signedIn },
                reminders = shared.remindersEnabled,
                analytics = shared.analyticsEnabled,
                // Акаунта більше нема — шторка видалення зникає разом із паролем.
                deleting = deleting && shared.signedIn,
                deletePassword = if (shared.signedIn) deletePassword else "",
                deleteError = (shared.notice as? AppNotice.Failed)?.error?.takeIf { deleting && shared.signedIn }
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
            is ProfileIntent.SetNewPasswordConfirm -> reduce { copy(newPasswordConfirm = intent.value) }
            ProfileIntent.ToggleNewPasswordReveal -> reduce { copy(newPasswordRevealed = !newPasswordRevealed) }
            // Увімкнути можна лише з дозволом системи; без нього спершу питаємо, а стор чекає відповіді.
            is ProfileIntent.SetReminders ->
                if (intent.enabled && !notifications.granted()) send(ProfileEffect.AskNotificationPermission)
                else app.setRemindersEnabled(intent.enabled)
            is ProfileIntent.SetAnalytics -> app.setAnalyticsEnabled(intent.enabled)
            is ProfileIntent.NotificationPermissionAnswered -> {
                reduce { copy(remindersDenied = !intent.granted) }
                app.setRemindersEnabled(intent.granted)
            }
            ProfileIntent.OpenPrivacy -> send(ProfileEffect.OpenLink(LegalLinks.PRIVACY))
            ProfileIntent.OpenTerms -> send(ProfileEffect.OpenLink(LegalLinks.TERMS))
            ProfileIntent.ContactSupport -> send(ProfileEffect.WriteEmail(LegalLinks.SUPPORT_EMAIL))
            is ProfileIntent.ShowDeleteAccount -> {
                if (!intent.show) app.clearNotice()
                reduce { copy(deleting = intent.show, deletePassword = "", deleteError = null) }
            }
            is ProfileIntent.SetDeletePassword -> reduce { copy(deletePassword = intent.value, deleteError = null) }
            ProfileIntent.ConfirmDeleteAccount -> app.deleteAccount(state.value.deletePassword)
            is ProfileIntent.ShowChangePassword -> {
                if (!intent.show) app.clearNotice()
                reduce { copy(changingPassword = intent.show, currentPassword = "", newPassword = "", changeError = null) }
            }
            is ProfileIntent.SetCurrentPassword -> reduce { copy(currentPassword = intent.value, changeError = null) }
            ProfileIntent.ConfirmChangePassword -> app.changePassword(state.value.currentPassword, state.value.newPassword)
        }
    }
}
