package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * Стежить за сесією: інший акаунт — інший світ. Усе приватне прибирається в одному місці,
 * а мапа й «мої» перечитуються під новим.
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
            auth.session.map { it?.userId }.distinctUntilChanged().collect(::synchronize)
        }
    }

    /** Наводить стан на акаунт [uid]. Той самий акаунт — нічого не робить. */
    fun synchronize(uid: String?) {
        if (store.value.userId == uid) return
        PoruchLog.i("session") { "identity → ${uid.shortId()}, clearing private state" }
        events.forgetPendingCreation()
        library.clear(); chat.close()
        store.update { it.forAccount(uid) }
        discovery.refresh()
        if (uid != null) {
            library.load(); push.register()
        }
    }

    /** Локальний вихід. Чистимо навіть якщо сервер відмовив: людина попросила вийти. */
    fun forget() {
        library.clear(); chat.close()
        store.update { it.forAccount(null) }
        discovery.refresh()
    }
}
