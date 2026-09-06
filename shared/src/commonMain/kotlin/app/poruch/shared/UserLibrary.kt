package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/**
 * The signed-in half of the state: the open event with its roster, and the lists that belong to
 * one account. Separated from discovery because every one of these must be dropped the moment the
 * identity changes — [clear] is the single place that guarantees it.
 */
internal class UserLibrary(
    private val events: EventRepository,
    private val auth: AuthRepository,
    private val preferences: PreferencesRepository?,
    private val state: MutableStateFlow<AppState>,
    private val scope: CoroutineScope
) {
    private var detailJob: Job? = null
    private var listJob: Job? = null
    /** The id the detail screen is currently showing; a late answer for any other id is dropped. */
    var openEventId: String? = null
        private set

    fun select(id: String) {
        openEventId = id
        detailJob?.cancel()
        // Show what discovery already knows while the full record loads: no empty screen.
        state.update { it.copy(selectedEvent = (it.events + it.myEvents).firstOrNull { event -> event.id == id }, attendees = emptyList()) }
        detailJob = scope.launch {
            try {
                val event = events.details(id)
                PoruchLog.d("detail") { "loaded ${id.shortId()} joined=${event?.joined} attendees=${event?.attendeeCount}/${event?.capacity} status=${event?.status}" }
                if (openEventId == id) state.update {
                    it.copy(selectedEvent = event, notice = if (event == null) AppNotice.Failed(AppError.EventUnavailable) else it.notice)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                state.update { it.copy(notice = AppNotice.Failed(e.asAppError())) }
            }
            // The roster is an enhancement over the count the details already carry, so a failure
            // (guest, non-member, or a server without the migration) leaves the count-only view.
            if (state.value.signedIn) {
                val roster = try { events.attendees(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
                PoruchLog.d("detail") { "roster for ${id.shortId()}: ${roster.size} visible" }
                if (openEventId == id) state.update { it.copy(attendees = roster) }
            }
        }
    }

    fun dismiss() {
        openEventId = null
        detailJob?.cancel()
        state.update { it.copy(selectedEvent = null, attendees = emptyList()) }
    }

    fun load() {
        if (auth.session.value == null) return
        listJob?.cancel()
        listJob = scope.launch {
            try {
                val mine = events.myEvents()
                val saved = events.savedIds()
                val interests = preferences?.interests().orEmpty()
                // Queue positions decide which action the detail screen offers, so an empty list on
                // failure would show the wrong button. They load with the rest, not best-effort.
                val queued = events.waitlistIds()
                PoruchLog.i("mine") { "${mine.size} of mine, ${saved.size} saved, ${queued.size} queued, ${interests.size} interests" }
                state.update { it.copy(myEvents = mine, savedIds = saved, interests = interests, waitlistedIds = queued) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                state.update { it.copy(notice = AppNotice.Failed(e.asAppError())) }
            }
        }
    }

    /** Drops every trace of the previous account, in memory and on disk. */
    fun clear() {
        listJob?.cancel(); detailJob?.cancel(); openEventId = null
        events.clearPrivateCache()
        state.update {
            it.copy(
                myEvents = emptyList(), savedIds = emptyList(), waitlistedIds = emptyList(),
                interests = emptyList(), attendees = emptyList(), selectedEvent = null
            )
        }
    }
}
