package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * Реєстрація пристрою для пушів. Токен один на телефон, а людей на ньому може бути кілька,
 * тож реєструємо під кожним акаунтом, з яким входять, і знімаємо перед виходом.
 */
internal class PushSync(
    private val push: PushTokens?,
    private val seenRequests: SeenRequestStore?,
    private val seenMessages: SeenRequestStore?,
    private val store: AppStore
) {
    /** Токен пристрою від платформи і його платформа. */
    private var token: Pair<String, String>? = null
    /** Токен і акаунт, для яких реєстрація вже йде: токен і вхід часто приходять одночасно. */
    private var registering: Pair<String, String?>? = null

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

    /** Знімає токен до виходу: після нього RPC уже не знає, чий він. Збій виходу не зупиняє. */
    suspend fun unregister() {
        val (token, _) = this.token ?: return
        runCatching { push?.unregister(token) }
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
