package app.poruch.android.feature.chat

import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.ChatRules
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
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
                readOnly = event != null && (event.isCancelled || event.endInstant?.let { it + CHAT_GRACE < now } == true),
                person = shared.person
            )
        }
        // Текст, що не пішов, повертається в поле, якщо людина ще не почала нове.
        viewModelScope.launch {
            app.state.map { it.chat?.takeIf { chat -> chat.eventId == eventId }?.failedDraft }.filterNotNull().collect {
                val failed = app.consumeFailedDraft() ?: return@collect
                reduce { if (draft.isBlank()) copy(draft = failed) else this }
            }
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
            is ChatIntent.ConfirmBlock -> reduce { copy(selected = null, blocking = intent.message) }
            is ChatIntent.Block -> {
                reduce { copy(blocking = null) }
                app.blockUser(intent.userId)
            }
            is ChatIntent.OpenPerson -> app.openPerson(intent.userId)
            ChatIntent.ClosePerson -> app.closePerson()
            is ChatIntent.SendReport -> {
                reduce { copy(reporting = null) }
                app.reportMessage(intent.message.id, intent.reason, intent.details)
            }
        }
    }

    override fun onCleared() {
        app.closeChat(); app.closePerson()
        super.onCleared()
    }

    private companion object {
        val CHAT_GRACE = 7.days
    }
}
