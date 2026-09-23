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
    private val push: PushSync
) {
    fun signIn(email: String, password: String) = store.mutate {
        PoruchLog.i("auth") { "sign in requested" }
        account.signIn(email, password)
        PoruchAnalytics.track("login")
        // Одразу, не чекаючи слухача сесії: мапа й «мої» перечитуються там, один раз.
        identity.synchronize(auth.session.value?.userId)
        store.tell(AppMessage.SIGNED_IN)
    }

    /** [birthDate] — ISO-8601. Платформа лише для дорослих, і перевірка починається тут. */
    fun signUp(email: String, password: String, name: String, birthDate: String) = store.mutate {
        PoruchLog.i("auth") { "sign up requested" }
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val signedIn = account.signUp(email, password, name, birthDate, today)
        PoruchAnalytics.track("sign_up", "confirmed" to signedIn)
        PoruchLog.i("auth") { "sign up ${if (signedIn) "signed in immediately" else "awaiting email confirmation"}" }
        // Без сесії відповідь — не банер, а окремий крок: екран входу показує, куди пішов лист і що далі.
        if (signedIn) store.tell(AppMessage.ACCOUNT_CREATED)
        else store.update { it.copy(session = it.session.copy(awaitingConfirmation = email.trim())) }
    }

    /** Людина повернулась до форми або закрила екран: крок «перевірте пошту» більше не показуємо. */
    fun dismissConfirmationStep() = store.update { it.copy(session = it.session.copy(awaitingConfirmation = null)) }

    fun signOut() = store.mutate {
        PoruchLog.i("auth") { "sign out" }
        push.unregister(auth.session.value)
        try {
            auth.signOut()
        } catch (e: AppFailure) {
            // Токен уже прострочений: сервер не впізнав сесію, а локально вихід відбувся. Банер тут збрехав би.
            if (e.error != AppError.SessionRequired) throw e
        } finally {
            // Чистимо навіть якщо сервер відмовив: людина попросила вийти.
            identity.synchronize(null)
        }
    }

    /**
     * Пароль підтверджує, що телефон у руках власника; сервер (Edge Function) видаляє все каскадом,
     * далі — те саме прибирання, що при виході. Мережевий збій лишає людину в акаунті: вона ще
     * існує на сервері, і видалення можна повторити.
     */
    fun deleteAccount(password: String) = store.mutate {
        PoruchLog.i("auth") { "account deletion requested" }
        if (!AccountRules.isPassword(password)) fail(AppError.InvalidCredentials)
        auth.verifyPassword(password)
        push.unregister(auth.session.value)
        try {
            auth.deleteAccount()
        } catch (e: Exception) {
            // 401 — сесії вже нема, акаунт вийшов разом з нею. Інакше повертаємо пуші, які щойно зняли.
            if (e.asAppError() == AppError.SessionRequired) identity.synchronize(null) else push.register()
            throw e
        }
        identity.synchronize(null)
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
        store.update { it.copy(session = it.session.copy(passwordRecovery = false), notice = AppNotice.Told(AppMessage.PASSWORD_CHANGED)) }
    }

    /** Зміна пароля з профілю: поточний пароль доводить, що телефон у руках власника, як і при видаленні. */
    fun changePassword(current: String, password: String) = store.mutate {
        if (!AccountRules.isPassword(password)) fail(AppError.WeakPassword)
        auth.verifyPassword(current)
        auth.updatePassword(password)
        store.tell(AppMessage.PASSWORD_CHANGED)
    }

    /** Посилання з листа: підтвердження пошти або відновлення пароля. */
    fun handleAuthCallback(url: String) = store.mutate(queued = true) {
        PoruchLog.i("auth") { "handling auth callback" }
        val recovery = auth.handleCallback(url)
        identity.synchronize(auth.session.value?.userId)
        store.update {
            it.copy(
                session = it.session.copy(passwordRecovery = recovery),
                notice = AppNotice.Told(if (recovery) AppMessage.SET_NEW_PASSWORD else AppMessage.EMAIL_CONFIRMED)
            )
        }
    }
}
