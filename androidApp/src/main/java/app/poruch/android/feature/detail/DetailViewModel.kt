package app.poruch.android.feature.detail

import app.poruch.android.mvi.MviViewModel
import app.poruch.shared.PoruchApp

class DetailViewModel(private val app: PoruchApp, private val eventId: String) :
    MviViewModel<DetailState, DetailIntent, DetailEffect>(DetailState()) {

    init {
        observe(app) { shared ->
            val event = shared.selectedEvent?.takeIf { it.id == eventId }
            copy(
                event = event,
                attendees = shared.attendees,
                loading = shared.loading,
                mutating = shared.mutating,
                signedIn = shared.signedIn,
                saved = shared.isSaved(eventId),
                waitlisted = shared.isWaitlisted(eventId),
                organizer = event != null && shared.organizes(event)
            )
        }
    }

    override fun onIntent(intent: DetailIntent) {
        val event = state.value.event
        when (intent) {
            DetailIntent.Load -> app.selectEvent(eventId)
            DetailIntent.Back -> send(DetailEffect.Back)

            DetailIntent.PrimaryAction -> authenticated {
                when (state.value.action) {
                    DetailAction.JOIN -> app.joinEvent(eventId)
                    DetailAction.LEAVE -> app.leaveEvent(eventId)
                    DetailAction.JOIN_WAITLIST -> app.joinWaitlist(eventId)
                    DetailAction.LEAVE_WAITLIST -> app.leaveWaitlist(eventId)
                    else -> Unit
                }
            }

            DetailIntent.ToggleSaved -> authenticated { app.toggleSaved(eventId) }
            DetailIntent.Share -> event?.let { send(DetailEffect.ShareEvent(it)) }
            DetailIntent.AddToCalendar -> event?.let { send(DetailEffect.OpenCalendar(it)) }
            DetailIntent.OpenInMaps -> event?.let { send(DetailEffect.OpenMaps(it)) }
            DetailIntent.Edit -> send(DetailEffect.Edit(eventId))
            is DetailIntent.ConfirmCancel -> reduce { copy(confirmingCancel = intent.open) }
            DetailIntent.CancelEvent -> {
                reduce { copy(confirmingCancel = false) }
                app.cancelEvent(eventId)
            }
            is DetailIntent.AttachPhoto -> app.uploadEventImage(eventId, intent.bytes, intent.contentType)
        }
    }

    /** Guests are sent to sign-in rather than shown an action that would fail at the server. */
    private inline fun authenticated(block: () -> Unit) {
        if (state.value.signedIn) block() else send(DetailEffect.RequireSignIn)
    }
}
