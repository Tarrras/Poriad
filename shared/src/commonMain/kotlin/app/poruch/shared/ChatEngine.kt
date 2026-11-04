package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.*

/**
 * Чат однієї події, поки його екран відкритий. Без сокетів: перечитує хвіст кожні
 * [ChatRules.POLL_INTERVAL_MS], після відправлення — одразу. Закриття екрана зупиняє все.
 */
internal class ChatEngine(
    private val chat: EventChat,
    private val store: AppStore,
    private val scope: CoroutineScope
) {
    private var polling: Job? = null
    private var sending: Job? = null
    /** Лічильник опитувань: кожне [FULL_EVERY] читає весь хвіст, щоб видалені зникали й у інших. */
    private var polls = 0
    /**
     * Скріншоти відкритого чату, що вантажаться зараз: опитування після відправлення й за таймером не просять той самий
     * файл удвох. Новий набір на кожне відкриття: завантаження закритого чату не зачепить відкритого.
     */
    private var loadingProofs = mutableSetOf<String>()

    val openEventId: String? get() = store.value.chat?.eventId

    /** Загальний чат події або, з [thread] (хто питає), розмова «Запитати організатора». */
    fun open(eventId: String, thread: String? = null) {
        if (store.value.chat?.isFor(eventId, thread) == true && polling?.isActive == true) return
        close()
        PoruchLog.i("chat") { "open ${eventId.shortId()}${if (thread != null) " thread" else ""}" }
        // Відкрили — прочитали: бейдж зникає одразу, сервер дізнається після першого читання.
        store.update { s ->
            val opened = s.copy(chat = ChatState(eventId, thread = thread))
            if (thread == null) opened.withoutUnread(eventId) else opened.withQuestionRead(eventId, thread)
        }
        polls = 0
        polling = scope.launch {
            while (isActive) {
                poll(eventId, thread)
                delay(ChatRules.POLL_INTERVAL_MS)
            }
        }
    }

    /** Зупиняє опитування. Відправлення в дорозі доїде: закрити екран — не те саме, що передумати. */
    fun close() {
        polling?.cancel(); polling = null
        loadingProofs = mutableSetOf()
        if (store.value.chat != null) store.update { it.copy(chat = null) }
    }

    /**
     * Відправлення поза [AppStore.mutate]: спінер на кнопці чату, а не на всьому застосунку. [jpeg] — скріншот оплати
     * (docs/organizer-events.md): лише в моїй розмові з організатором події з оплатою онлайн ([AppState.canSendProof]),
     * уже JPEG без метаданих (платформа перекодовує, як фото події). Він іде в приватний бакет, а повідомлення — з текстом
     * поля або [ChatRules.PROOF_BODY]; свій скріншот видно одразу, без завантаження назад.
     */
    fun send(text: String, jpeg: ByteArray? = null) {
        val eventId = openEventId ?: return
        if (jpeg != null && !store.value.canSendProof()) return
        val thread = store.value.chat?.thread
        val body = ChatRules.normalize(text).ifEmpty { if (jpeg != null) ChatRules.PROOF_BODY else "" }
        if (!ChatRules.isBody(body)) {
            store.failed(AppError.InvalidMessage)
            return
        }
        if (sending?.isActive == true) return
        sending = scope.launch {
            update(eventId) { copy(sending = true) }
            try {
                val image = jpeg?.let { bytes ->
                    chat.uploadProof(eventId, bytes).also { path -> update(eventId) { copy(proofs = proofs + (path to bytes)) } }
                }
                chat.send(eventId, body, thread, image)
                poll(eventId, thread)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Платформа чистить поле до відповіді: текст повертається через стан, а не губиться.
                if (text.isNotBlank()) update(eventId) { copy(failedDraft = text) }
                store.failed(e.asAppError(), byPerson = true)
            } finally {
                update(eventId) { copy(sending = false) }
            }
        }
    }

    /**
     * Байти скріншотів, яких ще нема в [ChatState.proofs]: з приватного бакета з токеном, паралельно, у корутині
     * опитування — закриття чату їх скасовує. У памʼяті лише поки чат відкритий: скріншот — до 5 МБ. Недоступний
     * (видалено, нема права) — у [ChatState.missingProofs], екран показує заглушку й більше не просить.
     */
    private suspend fun loadProofs(eventId: String) = coroutineScope {
        val open = store.value.chat?.takeIf { it.eventId == eventId } ?: return@coroutineScope
        val loading = loadingProofs
        for (path in open.messages.mapNotNull { it.image }.distinct()) {
            if (path in open.proofs || path in open.missingProofs || !loading.add(path)) continue
            launch {
                try {
                    val bytes = chat.proof(path)
                    update(eventId) { copy(proofs = proofs + (path to bytes)) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // Без мережі — спробуємо з наступним опитуванням; інше — не наше чи вже нема.
                    if (e.asAppError() !is AppError.Network) update(eventId) { copy(missingProofs = missingProofs + path) }
                } finally {
                    loading.remove(path)
                }
            }
        }
    }

    /** Текст, що не пішов, для поля вводу. Віддає раз: друге читання — null. */
    fun consumeFailedDraft(): String? {
        val draft = store.value.chat?.failedDraft ?: return null
        store.update { s -> s.copy(chat = s.chat?.copy(failedDraft = null)) }
        return draft
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
                store.failed(e.asAppError())
            }
        }
    }

    /**
     * Перше читання — увесь хвіст, далі лише пізніше за останнє відоме. Кожне [FULL_EVERY]
     * опитування знову читає весь хвіст: так видалене кимось повідомлення зникає й у решти.
     */
    private suspend fun poll(eventId: String, thread: String?) {
        val current = store.value.chat?.takeIf { it.isFor(eventId, thread) } ?: return
        val full = current.messages.isEmpty() || polls++ % FULL_EVERY == 0
        val after = if (full) null else current.messages.last().createdAt
        try {
            val fresh = chat.messages(eventId, after, thread)
            update(eventId) {
                copy(messages = if (full) ChatRules.merge(emptyList(), fresh) else ChatRules.merge(messages, fresh), loading = false, available = true, offline = false)
            }
            // Прочитано до зараз: при відкритті і щоразу, коли приїхало чуже нове.
            val me = store.value.session.userId
            if (current.loading || fresh.any { it.authorId != me }) {
                try { chat.markRead(eventId, thread) } catch (e: CancellationException) { throw e } catch (e: Exception) { /* best-effort */ }
            }
            loadProofs(eventId)
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppFailure) {
            // Сервер без міграції чату: екран каже про це один раз і не заливає банерами.
            if (e.serverCode == "PGRST202") update(eventId) { copy(loading = false, available = false) }
            else if (e.error is AppError.Network) offline(eventId)
            else if (current.loading) store.failed(e.error)
            if (e.serverCode == "PGRST202") polling?.cancel()
        } catch (e: Exception) {
            if (e.asAppError() is AppError.Network) offline(eventId) else if (current.loading) store.failed(e.asAppError())
        }
    }

    /** Без мережі екран каже «Немає звʼязку» сам, а опитування підхопить її: банер кожні 5 с був би шумом. */
    private fun offline(eventId: String) = update(eventId) { copy(loading = false, offline = true) }

    /** Мережа повернулась: читаємо одразу, не чекаючи наступного опитування. */
    fun pollNow() {
        val open = store.value.chat ?: return
        scope.launch { poll(open.eventId, open.thread) }
    }

    private companion object {
        /** Раз на пів хвилини при інтервалі 5 с. */
        const val FULL_EVERY = 6
    }

    private fun update(eventId: String, change: ChatState.() -> ChatState) {
        store.update { s -> if (s.chat?.eventId == eventId) s.copy(chat = s.chat.change()) else s }
    }
}

/**
 * Чат однієї події, поки його екран відкритий. Живе в [AppState], а не в екрані: обидві
 * платформи слухають один стор, а опитування веде [ChatEngine].
 */
data class ChatState(
    val eventId: String,
    val messages: List<ChatMessage> = emptyList(),
    /** Розмова «Запитати організатора»: id того, хто питає. Null — загальний чат події. */
    val thread: String? = null,
    /** Перше читання ще в дорозі. */
    val loading: Boolean = true,
    val sending: Boolean = false,
    /** Сервер без міграції чату: екран каже про це замість порожнього списку. */
    val available: Boolean = true,
    /** Останнє читання впало без мережі: порожній чат — «Немає звʼязку», а не спінер. */
    val offline: Boolean = false,
    /**
     * Текст, який не вдалося надіслати: екран повертає його в поле вводу і кличе
     * `PoruchApp.consumeFailedDraft()`, щоб не повернути двічі.
     */
    val failedDraft: String? = null,
    /** Скріншоти оплати: шлях у бакеті → JPEG. Вантажить [ChatEngine] з токеном; свій — одразу після вивантаження. */
    val proofs: Map<String, ByteArray> = emptyMap(),
    /** Скріншоти, яких не вийшло завантажити (видалено чи нема права): екран показує заглушку. */
    val missingProofs: Set<String> = emptySet()
)

/** Заявка в розмові події з оплатою онлайн ([AppState.threadPayment]). */
enum class ThreadPayment {
    /** Заявка чекає оплати: організатору в розмові — «Оплату отримано» й «Відхилити». */
    WAITING,
    /** Оплату підтверджено: людина в списку. */
    PAID
}

internal fun ChatState.isFor(eventId: String, thread: String?) = this.eventId == eventId && this.thread == thread

/** Розмову [thread] відкрито: її непрочитане в деталях гасне одразу, сервер дізнається після першого читання. */
internal fun AppState.withQuestionRead(eventId: String, thread: String): AppState =
    if (detail.event?.id != eventId || detail.questions.none { it.askerId == thread && it.unread > 0 }) this
    else copy(detail = detail.copy(questions = detail.questions.map { if (it.askerId == thread) it.copy(unread = 0) else it }))

/** Тримає значення `chatUnread` без події [eventId]: чат відкрито або прочитано. */
internal fun AppState.withoutUnread(eventId: String): AppState =
    if (chatUnread.none { it.eventId == eventId }) this else copy(chatUnread = chatUnread.filterNot { it.eventId == eventId })
