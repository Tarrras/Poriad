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
    private val events: EventDiscovery,
    private val saved: SavedEvents,
    private val participation: EventParticipation,
    private val requests: EventRequests,
    private val auth: AuthRepository,
    private val preferences: PreferencesRepository?,
    private val safety: SafetyRepository?,
    private val taste: TasteStore?,
    private val state: MutableStateFlow<AppState>,
    private val scope: CoroutineScope
) {
    private var detailJob: Job? = null
    private var listJob: Job? = null
    /** The id the detail screen is currently showing; a late answer for any other id is dropped. */
    var openEventId: String? = null
        private set

    /**
     * Наводить застосунок на подію. [full] відрізняє підсвітку від відкриття.
     *
     * Підсвітка трапляється на кожен крок каруселі, і досі кожен крок коштував запиту. А
     * `event_details` — це `select * from private.event_rows(array[p_event_id])`, тобто **та сама**
     * проєкція, якою прийшла видача: для рядка, що вже лежить у стані, відповідь збігається з
     * питанням. Виміряно 135–384 мс на свайп, а з акаунтом на iOS удвічі більше, бо слідом летів
     * ще й ростер — для афіші, у якої учасників не буває за означенням.
     *
     * Тож мережу чіпаємо лише тоді, коли є що дізнатися: рядка немає в памʼяті (глибоке посилання,
     * сповіщення, подія поза поточною областю) або екран деталей справді відкрито — там показують
     * лічильник місць і членство, а вони могли змінитися без нас.
     */
    fun select(id: String, full: Boolean = false) {
        openEventId = id
        detailJob?.cancel()
        // Show what discovery already knows while the full record loads: no empty screen.
        val known = state.value.let { (it.events + it.myEvents).firstOrNull { event -> event.id == id } }
        state.update {
            it.copy(
                selectedEvent = known ?: it.selectedEvent?.takeIf { open -> open.id == id },
                attendees = emptyList(), joinRequests = emptyList()
            )
        }
        if (!full && known != null) {
            PoruchLog.d("detail") { "select ${id.shortId()} from memory, no request" }
            return
        }
        detailJob = scope.launch {
            try {
                val event = events.details(id)
                PoruchLog.d("detail") { "loaded ${id.shortId()} kind=${if (event?.isCommunity == true) "community" else "listing"} joined=${event?.gathering?.joined} attendees=${event?.gathering?.attendeeCount}/${event?.gathering?.capacity} status=${event?.status}" }
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
            //
            // Афіша сюди не потрапляє: ростер бачать організатор і учасники (`can_view_members`),
            // а в оголошення немає ні тих, ні тих. Порожня відповідь була гарантована — питати за
            // неї було просто нічим.
            if (state.value.signedIn && state.value.selectedEvent?.isCommunity == true) {
                val roster = try { events.attendees(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
                PoruchLog.d("detail") { "roster for ${id.shortId()}: ${roster.size} visible" }
                if (openEventId == id) state.update { it.copy(attendees = roster) }
            }
            // Only an organizer has requests to answer, and only for their own event.
            val mine = state.value.selectedEvent?.let { it.id == id && state.value.organizes(it) } == true
            val requests = if (mine) {
                try { requests.joinRequests(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
            } else emptyList()
            if (openEventId == id) state.update { it.copy(joinRequests = requests) }
        }
    }

    fun dismiss() {
        openEventId = null
        detailJob?.cancel()
        state.update { it.copy(selectedEvent = null, attendees = emptyList(), joinRequests = emptyList()) }
    }

    fun load() {
        if (auth.session.value == null) return
        listJob?.cancel()
        listJob = scope.launch {
            try {
                val mine = events.myEvents()
                val savedEvents = saved.savedIds()
                val interests = adoptInterests()
                // Best-effort: a server without the safety migration must not empty «my events».
                val facts = try { safety?.account() ?: AccountFacts() } catch (e: CancellationException) { throw e } catch (e: Exception) { AccountFacts() }
                val blocked = try { safety?.blocked().orEmpty() } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
                // Queue positions decide which action the detail screen offers, so an empty list on
                // failure would show the wrong button. They load with the rest, not best-effort.
                val queued = participation.waitlistIds()
                PoruchLog.i("mine") { "${mine.size} of mine, ${savedEvents.size} saved, ${queued.size} queued, ${interests.size} interests" }
                state.update {
                    it.copy(
                        myEvents = mine, savedIds = savedEvents, waitlistedIds = queued,
                        account = facts, blocked = blocked,
                        taste = it.taste.copy(interests = interests)
                    ).ranked()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                state.update { it.copy(notice = AppNotice.Failed(e.asAppError())) }
            }
        }
    }

    /**
     * Reconciles the answers this device holds with the ones the account carries.
     *
     * The account wins when it has any, so a person who answered on their phone sees the same
     * recommendations on a tablet. When the account has none — the usual case, since the questions
     * are asked before signing up — the device's answers go up instead of being wiped by the empty
     * server copy. Persisting the result locally keeps the next launch instant.
     */
    private suspend fun adoptInterests(): List<String> {
        val local = state.value.taste.interests
        val remote = preferences?.interests().orEmpty()
        if (remote.isEmpty() && local.isNotEmpty()) {
            runCatching { preferences?.setInterests(local) }
            return local
        }
        if (remote != local) taste?.write(state.value.taste.copy(interests = remote))
        return remote
    }

    /**
     * Drops every trace of the previous account, in memory and on disk. The opening answers are not
     * a trace of it: they belong to the phone, were given before any account existed, and the app
     * would be back to a blank list the moment somebody signs out.
     */
    fun clear() {
        listJob?.cancel(); detailJob?.cancel(); openEventId = null
        events.clearPrivateCache()
        state.update {
            it.copy(
                myEvents = emptyList(), savedIds = emptyList(), waitlistedIds = emptyList(),
                attendees = emptyList(), selectedEvent = null, joinRequests = emptyList(),
                account = AccountFacts(), blocked = emptyList()
            )
        }
    }
}
