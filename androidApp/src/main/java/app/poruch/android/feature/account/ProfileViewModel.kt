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
    /** Один запит дозволу на два перемикачі: відповідь іде тому, хто питав. */
    private var askingDigest = false

    init {
        observe(app) { shared ->
            copy(
                signedIn = shared.signedIn,
                profile = shared.library.profile,
                // Збережено або сесії нема — шторка редагування закривається.
                editing = editing && shared.signedIn && shared.notice != AppNotice.Told(AppMessage.CHANGES_SAVED),
                editError = (shared.notice as? AppNotice.Failed)?.error?.takeIf { editing && shared.signedIn },
                interests = shared.interests,
                needsAge = shared.needsAgeDeclaration,
                blocked = shared.library.blocked,
                follows = shared.library.follows,
                mutating = shared.mutating,
                passwordRecovery = shared.session.passwordRecovery,
                passwordless = shared.session.passwordless,
                // Після відновлення чи зміни поле чистимо, щоб пароль не висів.
                newPassword = if (shared.session.passwordRecovery || changingPassword) newPassword else "",
                newPasswordConfirm = if (shared.session.passwordRecovery) newPasswordConfirm else "",
                // Пароль змінено або сесії нема — шторка зміни закривається разом із полями.
                changingPassword = changingPassword && shared.signedIn && shared.notice != AppNotice.Told(AppMessage.PASSWORD_CHANGED),
                currentPassword = if (changingPassword && shared.signedIn) currentPassword else "",
                changeError = (shared.notice as? AppNotice.Failed)?.error?.takeIf { changingPassword && shared.signedIn },
                reminders = shared.remindersEnabled,
                digest = shared.digestEnabled && notifications.granted(),
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
            is ProfileIntent.ShowEdit -> {
                if (!intent.show) app.clearNotice()
                reduce { copy(editing = intent.show, editError = null) }
            }
            is ProfileIntent.SaveProfile -> app.saveProfile(intent.name, intent.bio)
            is ProfileIntent.PickAvatar -> app.setAvatar(intent.bytes, intent.contentType)
            ProfileIntent.RemoveAvatar -> app.removeAvatar()
            ProfileIntent.SignOut -> app.signOut()
            is ProfileIntent.ToggleInterest -> app.toggleInterest(intent.category)
            ProfileIntent.TuneRecommendations -> app.restartOnboarding()
            is ProfileIntent.ShowBirthDatePicker -> reduce { copy(pickingBirthDate = intent.show) }
            is ProfileIntent.SetBirthDate -> {
                reduce { copy(pickingBirthDate = false) }
                app.declareBirthDate(intent.value.toString())
            }
            is ProfileIntent.Unblock -> app.unblockUser(intent.userId)
            ProfileIntent.OpenFollows -> send(ProfileEffect.OpenFollows)
            is ProfileIntent.SetNewPassword -> reduce { copy(newPassword = intent.value) }
            ProfileIntent.SavePassword -> app.updatePassword(state.value.newPassword)
            is ProfileIntent.SetNewPasswordConfirm -> reduce { copy(newPasswordConfirm = intent.value) }
            ProfileIntent.ToggleNewPasswordReveal -> reduce { copy(newPasswordRevealed = !newPasswordRevealed) }
            // Увімкнути можна лише з дозволом системи; без нього спершу питаємо, а стор чекає відповіді.
            is ProfileIntent.SetReminders ->
                if (intent.enabled && !notifications.granted()) send(ProfileEffect.AskNotificationPermission)
                else app.setRemindersEnabled(intent.enabled)
            is ProfileIntent.SetAnalytics -> app.setAnalyticsEnabled(intent.enabled)
            is ProfileIntent.SetDigest ->
                if (intent.enabled && !notifications.granted()) { askingDigest = true; send(ProfileEffect.AskNotificationPermission) }
                else app.setDigestEnabled(intent.enabled)
            is ProfileIntent.NotificationPermissionAnswered -> if (askingDigest) {
                askingDigest = false
                reduce { copy(digestDenied = !intent.granted) }
                app.setDigestEnabled(intent.granted)
            } else {
                reduce { copy(remindersDenied = !intent.granted) }
                app.setRemindersEnabled(intent.granted)
            }
            ProfileIntent.OpenPrivacy -> send(ProfileEffect.OpenLink(LegalLinks.PRIVACY))
            ProfileIntent.OpenTerms -> send(ProfileEffect.OpenLink(LegalLinks.TERMS))
            ProfileIntent.ContactSupport -> send(ProfileEffect.WriteEmail(LegalLinks.SUPPORT_EMAIL))
            ProfileIntent.ShareApp -> { app.appShared(); send(ProfileEffect.ShareApp) }
            ProfileIntent.RateApp -> { app.rateAppOpened(); send(ProfileEffect.OpenStorePage) }
            is ProfileIntent.ShowDeleteAccount -> {
                if (!intent.show) app.clearNotice()
                reduce { copy(deleting = intent.show, deletePassword = "", deleteError = null) }
            }
            is ProfileIntent.SetDeletePassword -> reduce { copy(deletePassword = intent.value, deleteError = null) }
            // Акаунт Apple, видалений з Android, токенів Apple не відкликає: свіжого коду тут не взяти.
            ProfileIntent.ConfirmDeleteAccount -> state.value.let { app.deleteAccount(if (it.passwordless) null else it.deletePassword, null) }
            is ProfileIntent.ShowChangePassword -> {
                if (!intent.show) app.clearNotice()
                reduce { copy(changingPassword = intent.show, currentPassword = "", newPassword = "", changeError = null) }
            }
            is ProfileIntent.SetCurrentPassword -> reduce { copy(currentPassword = intent.value, changeError = null) }
            ProfileIntent.ConfirmChangePassword -> app.changePassword(state.value.currentPassword, state.value.newPassword)
        }
    }
}
