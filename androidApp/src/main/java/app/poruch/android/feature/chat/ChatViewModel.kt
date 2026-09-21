package app.poruch.android.feature.chat

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.ChatRules
import app.poruch.shared.PoruchApp
import kotlin.time.Clock
import kotlin.time.Duration.Companion.days

/** Екран чату однієї події. Опитування веде спільний шар: тут лише відкрити, закрити й передати дії. */
class ChatViewModel(private val app: PoruchApp, private val eventId: String) :
    MviViewModel<ChatState, ChatIntent, ChatEffect>(ChatState(eventId)) {

    init {
        app.openChat(eventId)
        observe(app) { shared ->
            val event = (listOf(shared.detail.event) + shared.library.myEvents).firstOrNull { it?.id == eventId }
            val chat = shared.chat?.takeIf { it.eventId == eventId }
            val now = Clock.System.now()
            copy(
                title = event?.title ?: title,
                members = event?.gathering?.let { it.attendeeCount + 1 } ?: members,
                messages = chat?.messages ?: messages,
                loading = chat?.loading ?: loading,
                sending = chat?.sending ?: false,
                available = chat?.available ?: available,
                userId = shared.session.userId,
                organizer = event != null && shared.organizes(event),
                // Той самий поріг, що на сервері: тиждень після кінця.
                readOnly = event != null && (event.isCancelled || event.endInstant?.let { it + CHAT_GRACE < now } == true)
            )
        }
    }

    override fun onIntent(intent: ChatIntent) {
        when (intent) {
            ChatIntent.Back -> send(ChatEffect.Back)
            is ChatIntent.EditDraft -> reduce { copy(draft = intent.text.take(ChatRules.MAX_BODY)) }
            ChatIntent.Send -> {
                val text = state.value.draft
                if (!ChatRules.isBody(text) || state.value.sending) return
                reduce { copy(draft = "") }
                app.sendMessage(text)
            }
            is ChatIntent.Select -> reduce { copy(selected = intent.message) }
            is ChatIntent.Copy -> { reduce { copy(selected = null) }; send(ChatEffect.Copy(intent.message.body)) }
            is ChatIntent.ConfirmDelete -> reduce { copy(selected = null, deleting = intent.message) }
            is ChatIntent.Delete -> {
                reduce { copy(selected = null, deleting = null) }
                app.deleteMessage(intent.id)
            }
            is ChatIntent.ShowReport -> reduce { copy(selected = null, reporting = intent.message) }
            is ChatIntent.SendReport -> {
                reduce { copy(reporting = null) }
                app.reportMessage(intent.message.id, intent.reason, intent.details)
            }
        }
    }

    override fun onCleared() {
        app.closeChat()
        super.onCleared()
    }

    private companion object {
        val CHAT_GRACE = 7.days
    }
}
