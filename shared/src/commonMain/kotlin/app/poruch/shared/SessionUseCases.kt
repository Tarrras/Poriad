package app.poruch.shared

import app.poruch.account.AccountActions
import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
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
    private val safety: SafetyRepository?,
    private val profiles: ProfileRepository?
) {
    fun signIn(email: String, password: String) = store.mutate {
        PoruchLog.i("auth") { "sign in requested" }
        account.signIn(email, password)
        PoruchAnalytics.track("login", "method" to "email")
        // Одразу, не чекаючи слухача сесії: мапа й «мої» перечитуються там, один раз.
        identity.synchronize(auth.session.value?.userId)
        store.tell(AppMessage.SIGNED_IN)
    }

    fun idTokenNonce() = auth.idTokenNonce()

    /**
     * Вхід ID-токеном Google чи Apple, виданим з nonce від [AuthRepository.idTokenNonce]. Новий акаунт
     * з'являється тут же (тригер бази бере імʼя з профілю Google). Провайдер не каже вік: [adult] — галочка «Мені вже є
     * 18» на першому екрані входу; без неї акаунт без віку лишає екран входу на кроці галочки ([SessionState.askBirthDate]).
     */
    fun signInWithIdToken(provider: IdProvider, idToken: String, name: String?, adult: Boolean) = store.mutate {
        PoruchLog.i("auth") { "sign in with ${provider.key} requested" }
        auth.signInWithIdToken(provider, idToken)
        PoruchAnalytics.track("login", "method" to provider.key)
        identity.synchronize(auth.session.value?.userId)
        // Apple дає імʼя лише при першому вході і не в токені: не збережемо зараз — лишиться «Учасник».
        // Лише замість імені за замовчуванням: Apple з тією ж поштою GoTrue привʼязує до наявного
        // акаунта, і обране людиною імʼя не має мінятися на імʼя з Apple ID.
        val uid = auth.session.value?.userId
        name?.trim()?.takeIf(AccountRules::isName)?.let { name ->
            try {
                if (uid != null && profiles?.profile(uid)?.name == ProfileRules.DEFAULT_NAME) profiles.rename(name)
            } catch (e: CancellationException) { throw e } catch (e: Exception) {
                PoruchLog.w("auth") { "provider name not saved: ${e.asAppError()}" }
            }
        }
        askAgeIfMissing(adult)
        store.tell(AppMessage.SIGNED_IN)
    }

    /** Ставить [PoruchApp]: галочка без «Вік підтверджено» ([SafetyUseCases.confirmed]). */
    var confirmAdult: (suspend () -> Unit)? = null

    /**
     * Акаунт без віку (новий через Google, Apple чи код з пошти). Галочку «Мені вже є 18» відмітили на першому екрані
     * входу ([adult]) — ставимо її самі, без окремого кроку (власник 02.11: окремий крок про вік лякає). Ні, чи не
     * вийшло — екран входу лишається на кроці галочки ([SessionState.askBirthDate]).
     */
    private suspend fun askAgeIfMissing(adult: Boolean) {
        // Не вдалось дізнатись — не питаємо: картка віку в профілі й сервер при приєднанні підстрахують.
        val ageDeclared = try { safety?.account()?.ageDeclared } catch (e: CancellationException) { throw e } catch (e: Exception) { null } ?: true
        if (!ageDeclared && adult) {
            val confirm = confirmAdult
            try {
                if (confirm != null) return confirm()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("auth") { "adult checkbox not saved: ${e.asAppError()}" }
            }
        }
        store.update { it.copy(session = it.session.copy(askBirthDate = !ageDeclared)) }
    }

    /** Код входу на [email]: далі екран входу питає код ([SessionState.awaitingCode]). Повтор — новий лист. */
    fun sendSignInCode(email: String) = store.mutate {
        PoruchLog.i("auth") { "sign-in code requested" }
        account.sendCode(email)
        store.update { it.copy(session = it.session.copy(awaitingCode = email.trim())) }
    }

    /**
     * Код з листа. Новий акаунт з'являється тут же, як на сайті, і без віку: тоді крок галочки, як після Google.
     * Хибний чи прострочений код — [AppError.InvalidCode], крок коду лишається.
     */
    fun verifySignInCode(email: String, code: String, adult: Boolean) = store.mutate {
        PoruchLog.i("auth") { "sign-in code entered" }
        account.verifyCode(email, code)
        PoruchAnalytics.track("login", "method" to "code")
        identity.synchronize(auth.session.value?.userId)
        askAgeIfMissing(adult)
        store.tell(AppMessage.SIGNED_IN)
    }

    /** [birthDate] — ISO-8601. Платформа лише для дорослих, і перевірка починається тут. */
    fun signUp(email: String, password: String, name: String, birthDate: String) = signUp(email) {
        account.signUp(email, password, name, birthDate, Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date)
    }

    /** Реєстрація з галочкою «Мені вже є 18» замість дати (хвиля 2). */
    fun signUp(email: String, password: String, name: String) = signUp(email) { account.signUp(email, password, name) }

    private fun signUp(email: String, request: suspend () -> Boolean) = store.mutate {
        PoruchLog.i("auth") { "sign up requested" }
        val signedIn = request()
        PoruchAnalytics.track("sign_up", "confirmed" to signedIn)
        PoruchLog.i("auth") { "sign up ${if (signedIn) "signed in immediately" else "awaiting email confirmation"}" }
        // Без сесії відповідь — не банер, а окремий крок: екран входу показує, куди пішов лист і що далі.
        if (signedIn) store.tell(AppMessage.ACCOUNT_CREATED)
        else store.update { it.copy(session = it.session.copy(awaitingConfirmation = email.trim())) }
    }

    /** Людина повернулась до форми або закрила екран: крок «перевірте пошту» більше не показуємо. */
    fun dismissConfirmationStep() = store.update {
        it.copy(session = it.session.copy(awaitingConfirmation = null, awaitingCode = null, askBirthDate = false))
    }

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
     * Пароль підтверджує, що телефон у руках власника, — тут і ще раз на сервері: чужий токен без пароля
     * акаунт не видалить. Сервер (Edge Function) видаляє все каскадом, далі — те саме прибирання, що при
     * виході. Мережевий збій лишає людину в акаунті: вона ще існує на сервері, і видалення можна повторити.
     * Акаунт без пароля (Google/Apple) підтверджує саме видалення; для Apple платформа ще дає свіжий код,
     * щоб сервер відкликав токени Apple.
     */
    fun deleteAccount(password: String?, appleAuthorizationCode: String?) = store.mutate {
        PoruchLog.i("auth") { "account deletion requested" }
        val passwordless = store.value.session.passwordless
        if (!passwordless) {
            if (password == null || !AccountRules.isPassword(password)) fail(AppError.InvalidCredentials)
            auth.verifyPassword(password)
        }
        delete(password.takeUnless { passwordless }, appleAuthorizationCode)
    }

    /**
     * Код на пошту акаунта перед видаленням: акаунт з коду (запис з вебу) пароля не має, а сервер без пароля видаляє лише
     * одразу після входу. Пошта — з профілю, тож код підтвердить саме цей акаунт.
     */
    fun sendDeletionCode() = store.mutate {
        PoruchLog.i("auth") { "deletion code requested" }
        account.sendCode(accountEmail())
    }

    /** Код з листа — свіжий вхід (`amr` не старший за 10 хв), і сервер видаляє акаунт без пароля. Хибний код — нічого не видаляє. */
    fun deleteAccountWithCode(code: String) = store.mutate {
        PoruchLog.i("auth") { "account deletion with a code requested" }
        val uid = auth.session.value?.userId ?: fail(AppError.SessionRequired)
        account.verifyCode(accountEmail(), code)
        // Та сама пошта — той самий акаунт; інший тут означав би, що профіль показував чужу пошту.
        if (auth.session.value?.userId != uid) fail(AppError.Rejected)
        delete(null, null)
    }

    private suspend fun accountEmail(): String {
        val uid = auth.session.value?.userId ?: fail(AppError.SessionRequired)
        return (store.value.library.profile ?: profiles?.profile(uid))?.email?.takeIf { it.isNotBlank() } ?: fail(AppError.ServiceUnavailable)
    }

    private suspend fun delete(password: String?, appleAuthorizationCode: String?) {
        push.unregister(auth.session.value)
        try {
            auth.deleteAccount(password, appleAuthorizationCode)
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

    /**
     * Зміна пароля з профілю: поточний пароль доводить, що телефон у руках власника, як і при видаленні.
     * Перевірка тут дає зрозумілу відмову до запиту, а сервер звіряє той самий пароль ще раз.
     */
    fun changePassword(current: String, password: String) = store.mutate {
        if (!AccountRules.isPassword(password)) fail(AppError.WeakPassword)
        auth.verifyPassword(current)
        auth.updatePassword(password, current)
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
