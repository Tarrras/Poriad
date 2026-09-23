package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.launch

/**
 * Стежить за сесією: інший акаунт — інший світ. Усе приватне прибирається в одному місці
 * ([synchronize]), а мапа й «мої» перечитуються під новим.
 */
internal class IdentitySync(
    private val auth: AuthRepository,
    private val store: AppStore,
    private val discovery: DiscoveryEngine,
    private val library: UserLibrary,
    private val chat: ChatEngine,
    private val push: PushSync,
    private val events: EventUseCases
) {
    fun start() {
        store.scope.launch {
            var last = auth.session.value
            auth.session.collect { session ->
                // Акаунт пішов не через вихід (відкликана сесія): пуш-токен ще під ним.
                last?.takeIf { it.userId != session?.userId }?.let(push::accountLeft)
                last = session
                synchronize(session?.userId)
            }
        }
    }

    /** Наводить стан на акаунт [uid]. Той самий акаунт — нічого не робить. Вихід — `synchronize(null)`. */
    fun synchronize(uid: String?) {
        if (store.value.session.userId == uid) return
        PoruchLog.i("session") { "identity → ${uid.shortId()}, clearing private state" }
        events.forgetPendingCreation()
        library.clear(); chat.close(); discovery.reset()
        store.update { it.forAccount(uid) }
        discovery.refresh()
        if (uid != null) {
            library.load(); push.register()
        }
    }
}
