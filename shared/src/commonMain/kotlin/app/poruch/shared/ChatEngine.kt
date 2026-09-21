package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/**
 * Чат однієї події, поки його екран відкритий. Без сокетів: перечитує хвіст кожні
 * [ChatRules.POLL_INTERVAL_MS], після відправлення — одразу. Закриття екрана зупиняє все.
 */
internal class ChatEngine(
    private val chat: EventChat,
    private val state: MutableStateFlow<AppState>,
    private val scope: CoroutineScope
) {
    private var polling: Job? = null
    private var sending: Job? = null
    /** Лічильник опитувань: кожне [FULL_EVERY] читає весь хвіст, щоб видалені зникали й у інших. */
    private var polls = 0

    val openEventId: String? get() = state.value.chat?.eventId

    fun open(eventId: String) {
        if (openEventId == eventId && polling?.isActive == true) return
        close()
        PoruchLog.i("chat") { "open ${eventId.shortId()}" }
        // Відкрили — прочитали: бейдж зникає одразу, сервер дізнається після першого читання.
        state.update { it.copy(chat = ChatState(eventId)).withoutUnread(eventId) }
        polls = 0
        polling = scope.launch {
            while (isActive) {
                poll(eventId)
                delay(ChatRules.POLL_INTERVAL_MS)
            }
        }
    }

    fun close() {
        polling?.cancel(); polling = null
        sending?.cancel(); sending = null
        if (state.value.chat != null) state.update { it.copy(chat = null) }
    }

    /** Відправлення поза [PoruchApp.mutate]: спінер на кнопці чату, а не на всьому застосунку. */
    fun send(text: String) {
        val eventId = openEventId ?: return
        val body = ChatRules.normalize(text)
        if (!ChatRules.isBody(body)) {
            state.update { it.copy(notice = AppNotice.Failed(AppError.InvalidMessage)) }
            return
        }
        if (sending?.isActive == true) return
        sending = scope.launch {
            update(eventId) { copy(sending = true) }
            try {
                chat.send(eventId, body)
                poll(eventId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                state.update { it.copy(notice = AppNotice.Failed(e.asAppError())) }
            } finally {
                update(eventId) { copy(sending = false) }
            }
        }
    }

    fun delete(messageId: String) {
        val eventId = openEventId ?: return
        scope.launch {
            try {
                chat.delete(messageId)
                // Видалене зникає лише при повному перечитуванні: тут прибираємо одразу.
                update(eventId) { copy(messages = messages.filterNot { it.id == messageId }) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                state.update { it.copy(notice = AppNotice.Failed(e.asAppError())) }
            }
        }
    }

    /**
     * Перше читання — увесь хвіст, далі лише пізніше за останнє відоме. Кожне [FULL_EVERY]
     * опитування знову читає весь хвіст: так видалене кимось повідомлення зникає й у решти.
     */
    private suspend fun poll(eventId: String) {
        val current = state.value.chat?.takeIf { it.eventId == eventId } ?: return
        val full = current.messages.isEmpty() || polls++ % FULL_EVERY == 0
        val after = if (full) null else current.messages.last().createdAt
        try {
            val fresh = chat.messages(eventId, after)
            update(eventId) {
                copy(messages = if (full) ChatRules.merge(emptyList(), fresh) else ChatRules.merge(messages, fresh), loading = false, available = true)
            }
            // Прочитано до зараз: при відкритті і щоразу, коли приїхало чуже нове.
            val me = state.value.userId
            if (current.loading || fresh.any { it.authorId != me }) {
                try { chat.markRead(eventId) } catch (e: CancellationException) { throw e } catch (e: Exception) { /* best-effort */ }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppFailure) {
            // Сервер без міграції чату: екран каже про це один раз і не заливає банерами.
            if (e.serverCode == "PGRST202") update(eventId) { copy(loading = false, available = false) }
            else if (current.loading) state.update { it.copy(notice = AppNotice.Failed(e.error)) }
            if (e.serverCode == "PGRST202") polling?.cancel()
        } catch (e: Exception) {
            if (current.loading) state.update { it.copy(notice = AppNotice.Failed(e.asAppError())) }
        }
    }

    private companion object {
        /** Раз на пів хвилини при інтервалі 5 с. */
        const val FULL_EVERY = 6
    }

    private inline fun update(eventId: String, change: ChatState.() -> ChatState) {
        state.update { s -> if (s.chat?.eventId == eventId) s.copy(chat = s.chat.change()) else s }
    }
}

/**
 * Чат однієї події, поки його екран відкритий. Живе в [AppState], а не в екрані: обидві
 * платформи слухають один стор, а опитування веде [ChatEngine].
 */
data class ChatState(
    val eventId: String,
    val messages: List<ChatMessage> = emptyList(),
    /** Перше читання ще в дорозі. */
    val loading: Boolean = true,
    val sending: Boolean = false,
    /** Сервер без міграції чату: екран каже про це замість порожнього списку. */
    val available: Boolean = true
)

/** Тримає значення `chatUnread` без події [eventId]: чат відкрито або прочитано. */
internal fun AppState.withoutUnread(eventId: String): AppState =
    if (chatUnread.none { it.eventId == eventId }) this else copy(chatUnread = chatUnread.filterNot { it.eventId == eventId })
