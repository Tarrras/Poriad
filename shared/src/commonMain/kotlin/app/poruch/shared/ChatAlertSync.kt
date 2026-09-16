package app.poruch.shared

import app.poruch.domain.ChatAlertRules
import app.poruch.domain.ChatNotifier
import app.poruch.domain.PoruchLog
import app.poruch.domain.SeenRequestStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * Дзвонить про нові повідомлення в чатах. Як і [RequestAlertSync], без пушів: «нове» — це
 * подія, чиє останнє чуже повідомлення зʼявилось у [AppState.chatUnread] і ще не бачене.
 */
internal class ChatAlertSync(
    private val state: StateFlow<AppState>,
    private val seen: SeenRequestStore,
    private val notifier: ChatNotifier,
    private val scope: CoroutineScope
) {
    fun start() {
        scope.launch {
            state.map { it.chatUnread.map { u -> u.lastMessageId } }
                .distinctUntilChanged()
                .collect { keys ->
                    if (keys.isEmpty()) return@collect
                    val current = state.value
                    val alerts = ChatAlertRules.alerts(
                        current.chatUnread, seen.seen(), current.chat?.eventId,
                        enabled = current.signedIn && current.remindersEnabled
                    )
                    if (alerts.isNotEmpty()) {
                        PoruchLog.i("chat") { "${alerts.size} chats with new messages" }
                        notifier.notifyMessages(alerts)
                    }
                    seen.markSeen(keys.toSet())
                }
        }
    }
}
