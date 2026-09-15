package app.poruch.shared

import app.poruch.domain.PoruchLog
import app.poruch.domain.RequestNotifier
import app.poruch.domain.RequestRules
import app.poruch.domain.SeenRequestStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * Дзвонить про нові запити на участь. Пушів нема, тож «нове» — те, що зʼявилось у
 * [AppState.pendingRequests] після останнього перечитування і чого ще нема у [SeenRequestStore].
 * Слухає лише склад запитів: інші зміни стану сюди не доходять.
 */
internal class RequestAlertSync(
    private val state: StateFlow<AppState>,
    private val seen: SeenRequestStore,
    private val notifier: RequestNotifier,
    private val scope: CoroutineScope
) {
    fun start() {
        scope.launch {
            state.map { it.pendingRequests.map { request -> request.key } }
                .distinctUntilChanged()
                .collect { keys ->
                    if (keys.isEmpty()) return@collect
                    val current = state.value
                    val alerts = RequestRules.alerts(
                        current.pendingRequests, seen.seen(), current.myEvents,
                        enabled = current.signedIn && current.remindersEnabled
                    )
                    if (alerts.isNotEmpty()) {
                        PoruchLog.i("requests") { "${alerts.sumOf { it.count }} new across ${alerts.size} events" }
                        notifier.notify(alerts)
                    }
                    // Бачені — усі поточні, навіть без сповіщення: вмикання пізніше не має дзвонити про давнє.
                    seen.markSeen(keys.toSet())
                }
        }
    }
}
