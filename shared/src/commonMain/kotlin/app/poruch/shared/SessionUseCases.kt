package app.poruch.shared

import app.poruch.account.AccountActions
import app.poruch.domain.*
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.time.Clock

/** Вхід, реєстрація, паролі й вихід. Перевірка полів — в [AccountActions], тут — стан і прибирання. */
internal class SessionUseCases(
    private val auth: AuthRepository,
    private val account: AccountActions,
    private val store: AppStore,
    private val identity: IdentitySync,
    private val push: PushSync,
    private val reloader: Reloader
) {
    fun signIn(email: String, password: String) = store.mutate {
        PoruchLog.i("auth") { "sign in requested" }
        account.signIn(email, password)
        store.tell(AppMessage.SIGNED_IN); reloader.lists()
    }

    /** [birthDate] — ISO-8601. Платформа лише для дорослих, і перевірка починається тут. */
    fun signUp(email: String, password: String, name: String, birthDate: String) = store.mutate {
        PoruchLog.i("auth") { "sign up requested" }
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val signedIn = account.signUp(email, password, name, birthDate, today)
        PoruchLog.i("auth") { "sign up ${if (signedIn) "signed in immediately" else "awaiting email confirmation"}" }
        // Без сесії відповідь — не банер, а окремий крок: екран входу показує, куди пішов лист і що далі.
        if (signedIn) store.tell(AppMessage.ACCOUNT_CREATED)
        else store.update { it.copy(awaitingConfirmation = email.trim()) }
    }

    /** Людина повернулась до форми або закрила екран: крок «перевірте пошту» більше не показуємо. */
    fun dismissConfirmationStep() = store.update { it.copy(awaitingConfirmation = null) }

    fun signOut() = store.mutate {
        PoruchLog.i("auth") { "sign out" }
        push.unregister()
        try { auth.signOut() } finally { identity.forget() }
    }

    /**
     * Пароль підтверджує, що телефон у руках власника; сервер видаляє все каскадом (власні події
     * скасовуються, фото прибираються), далі — те саме прибирання, що при виході.
     */
    fun deleteAccount(password: String) = store.mutate {
        PoruchLog.i("auth") { "account deletion requested" }
        if (!AccountRules.isPassword(password)) fail(AppError.InvalidCredentials)
        auth.verifyPassword(password)
        push.unregister()
        try { auth.deleteAccount() } finally { identity.forget() }
        store.tell(AppMessage.ACCOUNT_DELETED)
    }

    fun requestPasswordReset(email: String) = store.mutate {
        if (!AccountRules.isEmail(email)) fail(AppError.InvalidEmail)
        auth.requestPasswordReset(email)
        store.tell(AppMessage.RECOVERY_SENT)
    }

    /** Новий пароль після відновлення з листа. */
    fun updatePassword(password: String) = store.mutate {
        if (!AccountRules.isPassword(password)) fail(AppError.WeakPassword)
        auth.updatePassword(password)
        store.update { it.copy(passwordRecovery = false, notice = AppNotice.Told(AppMessage.PASSWORD_CHANGED)) }
    }

    /** Зміна пароля з профілю: поточний пароль доводить, що телефон у руках власника, як і при видаленні. */
    fun changePassword(current: String, password: String) = store.mutate {
        if (!AccountRules.isPassword(password)) fail(AppError.WeakPassword)
        auth.verifyPassword(current)
        auth.updatePassword(password)
        store.tell(AppMessage.PASSWORD_CHANGED)
    }

    /** Посилання з листа: підтвердження пошти або відновлення пароля. */
    fun handleAuthCallback(url: String) = store.mutate {
        PoruchLog.i("auth") { "handling auth callback" }
        val recovery = auth.handleCallback(url)
        identity.synchronize(auth.session.value?.userId)
        store.update {
            it.copy(
                passwordRecovery = recovery,
                notice = AppNotice.Told(if (recovery) AppMessage.SET_NEW_PASSWORD else AppMessage.EMAIL_CONFIRMED)
            )
        }
        reloader.lists()
    }
}
