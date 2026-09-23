package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.time.Clock

/**
 * Реєстрація пристрою для пушів. Токен один на телефон, а людей на ньому може бути кілька,
 * тож реєструємо під кожним акаунтом, з яким входять, і знімаємо, коли акаунт іде. Зняти не
 * вдалося (офлайн, сесію відкликано) — токен із ключем того акаунта чекає в [pending] і
 * повторюється на старті й при поверненні в застосунок.
 */
internal class PushSync(
    private val push: PushTokens?,
    private val seenRequests: SeenRequestStore?,
    private val seenMessages: SeenRequestStore?,
    private val store: AppStore,
    private val pending: PendingUnregisterStore? = null
) {
    /** Токен пристрою від платформи і його платформа. */
    private var token: Pair<String, String>? = null
    /** Токен і акаунт, для яких реєстрація вже йде: токен і вхід часто приходять одночасно. */
    private var registering: Pair<String, String?>? = null
    /** Акаунт, під яким токен зареєстровано. Null — ні під яким, або вже знято. */
    private var registeredFor: String? = null
    private var retrying: Job? = null

    /** Платформа отримала або оновила токен. Реєструємо одразу, якщо є акаунт. */
    fun tokenChanged(token: String, platform: String) {
        if (this.token?.first == token && store.value.session.pushRegistered) return
        this.token = token to platform
        register()
    }

    /** Реєструє поточний токен під поточним акаунтом. Без токена, сховища чи акаунта — нічого. */
    fun register() {
        val (token, platform) = this.token ?: return
        val tokens = push ?: return
        val uid = store.value.session.userId ?: return
        if (registering == token to uid) return
        registering = token to uid
        store.scope.launch {
            try {
                tokens.register(token, platform)
                PoruchLog.i("push") { "registered $platform token" }
                registeredFor = uid
                // Сервер переписав власника токена: попередній акаунт його вже не тримає.
                if (pending?.read()?.token == token) pending.write(null)
                store.update { it.copy(session = it.session.copy(pushRegistered = true)) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("push") { "register failed: ${e.asAppError()}" }
            } finally {
                if (registering == token to uid) registering = null
            }
        }
    }

    /**
     * Знімає токен до виходу поточної сесії: після нього RPC уже не знає, чий він. Збій виходу
     * не зупиняє, але токен лишається в [pending] з ключем цього акаунта.
     */
    suspend fun unregister(session: UserSession?) {
        val (token, _) = this.token ?: return
        val tokens = push ?: return
        session ?: return
        registeredFor = null
        store.update { it.copy(session = it.session.copy(pushRegistered = false)) }
        try {
            tokens.unregister(token)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            remember(token, session, e)
        }
    }

    /**
     * Сесія зникла не через вихід (сервер відкликав refresh): пробуємо останнім ключем. Він живий
     * ще хвилину після того, як ми вирішили оновлювати; далі — лише [pending].
     */
    fun accountLeft(session: UserSession) {
        val (token, _) = this.token ?: return
        val tokens = push ?: return
        if (registeredFor != session.userId) return
        registeredFor = null
        store.scope.launch {
            try {
                tokens.unregister(token, session.accessToken)
                PoruchLog.i("push") { "token released after the session was dropped" }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                remember(token, session, e)
            }
        }
    }

    private fun remember(token: String, session: UserSession, e: Exception) {
        val error = e.asAppError()
        // 401 — ключ уже мертвий, повтор нічого не дасть.
        if (error == AppError.SessionRequired) { PoruchLog.w("push") { "token not released: session already gone" }; return }
        PoruchLog.w("push") { "unregister failed: $error, will retry" }
        pending?.write(PendingUnregister(token, session.userId, session.accessToken, session.expiresAt))
    }

    /** Старт і повернення в застосунок: повторює незняте, поки ключ того акаунта живий. */
    fun retryPending() {
        val stored = pending ?: return
        val left = stored.read() ?: return
        val tokens = push ?: return
        if (retrying?.isActive == true) return
        // Той самий акаунт знову тут — токен знову його, знімати не можна.
        if (left.userId == store.value.session.userId || left.expiresAt <= Clock.System.now().epochSeconds) {
            stored.write(null); return
        }
        retrying = store.scope.launch {
            try {
                tokens.unregister(left.token, left.accessToken)
                PoruchLog.i("push") { "pending token released" }
                stored.write(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("push") { "pending unregister failed: $error" }
                if (error == AppError.SessionRequired || error == AppError.Rejected) stored.write(null)
            }
        }
    }

    /** Пуш прийшов на цей пристрій: ключ бачений, щоб локальне сповіщення не повторило те саме. */
    fun received(kind: String, key: String) {
        PoruchLog.i("push") { "received $kind" }
        when (kind) {
            "chat" -> seenMessages?.markSeen(setOf(key))
            "request" -> seenRequests?.markSeen(setOf(key))
        }
    }
}
