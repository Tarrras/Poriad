package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/**
 * Стан, прив'язаний до акаунта: відкрита подія з учасниками і списки «мої». Окремо від пошуку,
 * бо все це має зникнути при зміні акаунта, і [clear] — єдине місце, яке це гарантує.
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
    /** Id відкритої події. Запізніла відповідь для іншого id відкидається. */
    var openEventId: String? = null
        private set

    /**
     * Наводить застосунок на подію. [full] — відкриття екрана деталей, інакше підсвітка.
     * Підсвітка на кожен крок каруселі, тож мережу чіпаємо лише коли є що дізнатися: рядка нема
     * в пам'яті або деталі справді відкрито (місця й членство могли змінитися).
     */
    fun select(id: String, full: Boolean = false) {
        openEventId = id
        detailJob?.cancel()
        // Показуємо те, що вже знаємо, поки їдуть деталі. `cards` теж: сеанс прокату, обраний
        // у каруселі дат, у стрічці згорнуто.
        val known = state.value.let {
            (it.events + it.myEvents).firstOrNull { event -> event.id == id } ?: it.cards[id]
        }
        // Інша дата того ж прокату без картки: лишаємо поточну до відповіді. Порожній екран
        // гірший за секунду старої дати, а при 504 людина лишається з банером, а не спінером.
        val stay = known == null && state.value.let { current ->
            val open = current.selectedEvent
            open != null && open.id != id && EventSeries.sessionsOf(open, current.index).any { it.id == id }
        }
        state.update {
            it.copy(
                selectedEvent = known ?: it.selectedEvent?.takeIf { open -> open.id == id || stay },
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
            // Учасники — доповнення до лічильника, тож збій лишає лише число. Афішу не питаємо:
            // ростер бачать організатор і учасники (`can_view_members`), а в неї нема ні тих, ні тих.
            if (state.value.signedIn && state.value.selectedEvent?.isCommunity == true) {
                val roster = try { events.attendees(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
                PoruchLog.d("detail") { "roster for ${id.shortId()}: ${roster.size} visible" }
                if (openEventId == id) state.update { it.copy(attendees = roster) }
            }
            // Запити є лише в організатора і лише для своєї події.
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
                // Best-effort: сервер без міграції безпеки не має спустошити «мої події».
                val facts = try { safety?.account() ?: AccountFacts() } catch (e: CancellationException) { throw e } catch (e: Exception) { AccountFacts() }
                val blocked = try { safety?.blocked().orEmpty() } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
                // Черга вирішує, яку кнопку показати на деталях, тому не best-effort.
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
     * Узгоджує інтереси пристрою з акаунтом. Акаунт перемагає, якщо має хоч щось; порожній
     * акаунт (звичний випадок, питання ставлять до реєстрації) отримує відповіді пристрою.
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

    /** Прибирає все від попереднього акаунта в пам'яті й на диску. Відповіді онбордингу належать телефону і лишаються. */
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
