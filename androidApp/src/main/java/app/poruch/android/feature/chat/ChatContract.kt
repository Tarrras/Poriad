package app.poruch.android.feature.chat

import app.poruch.domain.ChatMessage
import app.poruch.domain.ReportReason
import app.poruch.shared.PersonState

/** Стан екрана чату: зріз [app.poruch.shared.ChatState] плюс те, що потрібно лише для промальовки. */
data class ChatState(
    val eventId: String,
    /** Розмова «Запитати організатора»: хто питає. Null — загальний чат. */
    val thread: String? = null,
    /** Імʼя того, хто питає, для підзаголовка організатора. */
    val askerName: String? = null,
    val title: String = "",
    /** Хто бачить чат: організатор і підтверджені. Нуль, поки подія не завантажена. */
    val members: Int = 0,
    val messages: List<ChatMessage> = emptyList(),
    val loading: Boolean = true,
    val sending: Boolean = false,
    /** Сервер без чату: показуємо пояснення замість порожнього списку. */
    val available: Boolean = true,
    /** Без мережі: порожній чат — «Немає звʼязку», а не вічний спінер. */
    val offline: Boolean = false,
    val userId: String? = null,
    /** Організатор може прибрати будь-яке повідомлення у своїй події. */
    val organizer: Boolean = false,
    /** Чат лише для читання: подію скасовано або вона давно минула. */
    val readOnly: Boolean = false,
    val draft: String = "",
    /** Повідомлення, для якого відкрито меню дій. */
    val selected: ChatMessage? = null,
    /** Повідомлення, на яке пишуть скаргу. */
    val reporting: ChatMessage? = null,
    /** Повідомлення, видалення якого підтверджують. */
    val deleting: ChatMessage? = null,
    /** Автора цього повідомлення блокують: крок підтвердження. */
    val blocking: ChatMessage? = null,
    /** Картка автора: тап по аватару. */
    val person: PersonState? = null,
    /** Люди, за якими стежу: кнопка «Стежити» на картці автора. */
    val followedOrganizers: Set<String> = emptySet(),
    /** Моя розмова з організатором події з оплатою онлайн: у полі вводу — «Надіслати скріншот оплати». */
    val canSendProof: Boolean = false,
    /** Скріншоти оплати: шлях → JPEG (вантажить спільний шар з токеном). */
    val proofs: Map<String, ByteArray> = emptyMap(),
    /** Скріншоти, яких не вийшло завантажити: заглушка замість картинки. */
    val missingProofs: Set<String> = emptySet(),
    /** Відкритий на весь екран скріншот (шлях). */
    val viewing: String? = null
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
    data class Copy(val message: ChatMessage) : ChatIntent
    /** Крок підтвердження перед видаленням; `null` — передумали. */
    data class ConfirmDelete(val message: ChatMessage?) : ChatIntent
    data class Delete(val id: String) : ChatIntent
    data class ShowReport(val message: ChatMessage?) : ChatIntent
    /** Крок підтвердження перед блокуванням автора; `null` — передумали. */
    data class ConfirmBlock(val message: ChatMessage?) : ChatIntent
    data class Block(val userId: String) : ChatIntent
    data class OpenPerson(val userId: String) : ChatIntent
    data object ClosePerson : ChatIntent
    /** «Стежити» на картці автора. Картка відкривається лише з акаунтом, тож гостя тут нема. */
    data class ToggleFollowPerson(val userId: String, val name: String) : ChatIntent
    /** Ціль їде всередині: шторка спершу закривається (і скидає [ChatState.reporting]), а вже потім шле це. */
    data class SendReport(val message: ChatMessage, val reason: ReportReason, val details: String) : ChatIntent
    /** Скріншот оплати з Photo Picker: уже JPEG без метаданих. Текст поля йде підписом. */
    class SendProof(val jpeg: ByteArray) : ChatIntent
    /** Скріншот на весь екран; `null` — закрити. */
    data class ViewProof(val path: String?) : ChatIntent
}

sealed interface ChatEffect {
    data object Back : ChatEffect
    data class Copy(val text: String) : ChatEffect
}
