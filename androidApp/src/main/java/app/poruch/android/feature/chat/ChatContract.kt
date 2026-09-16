package app.poruch.android.feature.chat

import app.poruch.domain.ChatMessage

/** Стан екрана чату: зріз [app.poruch.shared.ChatState] плюс те, що потрібно лише для промальовки. */
data class ChatState(
    val eventId: String,
    val title: String = "",
    val messages: List<ChatMessage> = emptyList(),
    val loading: Boolean = true,
    val sending: Boolean = false,
    /** Сервер без чату: показуємо пояснення замість порожнього списку. */
    val available: Boolean = true,
    val userId: String? = null,
    /** Організатор може прибрати будь-яке повідомлення у своїй події. */
    val organizer: Boolean = false,
    /** Чат лише для читання: подію скасовано або вона давно минула. */
    val readOnly: Boolean = false,
    val draft: String = "",
    /** Повідомлення, для якого відкрито меню дій. */
    val selected: ChatMessage? = null,
    /** Повідомлення, на яке пишуть скаргу. */
    val reporting: ChatMessage? = null
) {
    fun isMine(message: ChatMessage) = message.authorId == userId
    fun canDelete(message: ChatMessage) = organizer || isMine(message)
}

sealed interface ChatIntent {
    data object Back : ChatIntent
    data class EditDraft(val text: String) : ChatIntent
    data object Send : ChatIntent
    /** Довгий тап по повідомленню: меню дій або закриття. */
    data class Select(val message: ChatMessage?) : ChatIntent
    data class Delete(val id: String) : ChatIntent
    data class ShowReport(val message: ChatMessage?) : ChatIntent
    /** Ціль їде всередині: шторка спершу закривається (і скидає [ChatState.reporting]), а вже потім шле це. */
    data class SendReport(val message: ChatMessage, val reason: String, val details: String) : ChatIntent
}

sealed interface ChatEffect {
    data object Back : ChatEffect
}
