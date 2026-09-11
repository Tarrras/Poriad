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
                organizer = event != null && shared.organizes(event),
                requests = shared.joinRequests
            )
        }
    }

    override fun onIntent(intent: DetailIntent) {
        val event = state.value.event
        when (intent) {
            // Саме `openEvent`, а не `selectEvent`: цей екран — єдине місце, де показують число
            // місць і членство, тож він єдиний і має право їх перепитати.
            DetailIntent.Load -> app.openEvent(eventId)
            DetailIntent.Back -> send(DetailEffect.Back)

            // Квиток на афішу купують у джерела, а не в нас, тож акаунт для цього не потрібен —
            // саме тому дія стоїть перед перевіркою входу, а не всередині неї.
            DetailIntent.PrimaryAction -> if (state.value.action == DetailAction.TICKETS) {
                event?.listing?.canonicalUrl?.let { send(DetailEffect.OpenLink(it)) }
            } else authenticated {
                when (state.value.action) {
                    DetailAction.JOIN, DetailAction.REQUEST -> app.joinEvent(eventId)
                    DetailAction.LEAVE -> app.leaveEvent(eventId)
                    DetailAction.JOIN_WAITLIST -> app.joinWaitlist(eventId)
                    DetailAction.LEAVE_WAITLIST -> app.leaveWaitlist(eventId)
                    else -> Unit
                }
            }
            DetailIntent.OpenSource -> event?.listing?.canonicalUrl?.let { send(DetailEffect.OpenLink(it)) }

            DetailIntent.ToggleSaved -> authenticated { app.toggleSaved(eventId) }
            DetailIntent.Share -> event?.let { send(DetailEffect.ShareEvent(it)) }
            DetailIntent.AddToCalendar -> event?.let { send(DetailEffect.OpenCalendar(it)) }
            DetailIntent.OpenInMaps -> event?.let { send(DetailEffect.OpenMaps(it)) }
            DetailIntent.OpenMap -> send(DetailEffect.OpenMap(eventId))
            DetailIntent.Edit -> send(DetailEffect.Edit(eventId))
            is DetailIntent.ConfirmCancel -> reduce { copy(confirmingCancel = intent.open) }
            DetailIntent.CancelEvent -> {
                reduce { copy(confirmingCancel = false) }
                app.cancelEvent(eventId)
            }
            is DetailIntent.AttachPhoto -> app.uploadEventImage(eventId, intent.bytes, intent.contentType)

            is DetailIntent.ShowReport -> if (intent.target != null && !state.value.signedIn) {
                send(DetailEffect.RequireSignIn)
            } else reduce { copy(reporting = intent.target) }
            is DetailIntent.SendReport -> {
                val target = state.value.reporting
                reduce { copy(reporting = null) }
                when (target) {
                    ReportTarget.EVENT -> app.reportEvent(eventId, intent.reason, intent.details)
                    // У афіші організатора немає — скаржитись нема на кого. Сама подія лишається
                    // доступною для скарги через ReportTarget.EVENT.
                    ReportTarget.ORGANIZER -> event?.organizerId?.let { app.reportUser(it, intent.reason, intent.details) }
                    null -> Unit
                }
            }
            is DetailIntent.ConfirmBlock -> if (intent.open && !state.value.signedIn) {
                send(DetailEffect.RequireSignIn)
            } else reduce { copy(confirmingBlock = intent.open) }
            DetailIntent.BlockOrganizer -> {
                reduce { copy(confirmingBlock = false) }
                // Blocking removes the event from this account's map, so the screen behind it goes too.
                event?.organizerId?.let { app.blockUser(it); send(DetailEffect.Back) }
            }
            is DetailIntent.ApproveRequest -> app.approveMember(eventId, intent.userId)
            is DetailIntent.DeclineRequest -> app.declineMember(eventId, intent.userId)
        }
    }

    /** Guests are sent to sign-in rather than shown an action that would fail at the server. */
    private inline fun authenticated(block: () -> Unit) {
        if (state.value.signedIn) block() else send(DetailEffect.RequireSignIn)
    }
}
