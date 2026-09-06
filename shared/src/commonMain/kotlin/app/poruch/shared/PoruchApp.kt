package app.poruch.shared

import app.poruch.domain.*
import app.poruch.events.EventActions
import app.poruch.account.AccountActions
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlin.uuid.Uuid
import kotlin.uuid.ExperimentalUuidApi

/**
 * The single store both platforms observe. It owns the state and the jobs that change it; reading
 * and filtering live in [DiscoveryEngine] and [UserLibrary], and what remains here are the verbs a
 * screen can invoke and the session they all depend on.
 */
class PoruchApp internal constructor(
    private val events: EventRepository,
    private val auth: AuthRepository,
    geo: GeoSearchRepository,
    private val eventActions: EventActions,
    private val accountActions: AccountActions,
    private val preferences: PreferencesRepository? = null,
    private val creationIdentity: CreationIdentityStore? = null,
    config: AppConfig = AppConfig("", ""),
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
) {
    private val mutable = MutableStateFlow(AppState(userId = auth.session.value?.userId))
    val state: StateFlow<AppState> = mutable.asStateFlow()

    private val discovery = DiscoveryEngine(events, geo, mutable, scope, config.home)
    private val library = UserLibrary(events, auth, preferences, mutable, scope)

    private var mutationJob: Job? = null
    /** Retry of an uncertain create must reuse its id, or the retry publishes a second event. */
    private var pendingCreation: Pair<EventDraft, String>? = null

    init {
        discovery.onQueryChanged = library::dismiss
        scope.launch {
            auth.session.map { it?.userId }.distinctUntilChanged().collect(::synchronizeIdentity)
        }
        refresh()
        if (state.value.signedIn) loadMyEvents()
    }

    // ---------------------------------------------------------------- session

    private fun synchronizeIdentity(uid: String?) {
        if (mutable.value.userId == uid) {
            mutable.update { it.copy(userId = uid) }
            return
        }
        PoruchLog.i("session") { "identity → ${uid.shortId()}, clearing private state" }
        pendingCreation = null
        library.clear()
        mutable.update { it.copy(userId = uid, events = emptyList(), passwordRecovery = false, completedEventId = null) }
        refresh()
        if (uid != null) loadMyEvents()
    }

    fun observe(onChange: (AppState) -> Unit): Subscription {
        val job = scope.launch { state.collect { onChange(it) } }
        return Subscription { job.cancel() }
    }

    // ---------------------------------------------------------------- discovery

    fun refresh() = discovery.refresh()
    fun searchArea(south: Double, west: Double, north: Double, east: Double) = discovery.searchArea(south, west, north, east)
    fun setSearchText(query: String) = discovery.setSearchText(query)
    fun setOnlyAvailable(available: Boolean) = discovery.setOnlyAvailable(available)
    fun setCategory(category: String) = discovery.setCategory(category)
    fun setDateFilter(filter: String) = discovery.setDateFilter(filter)
    fun searchCity(query: String) = discovery.searchCity(query)
    fun selectCity(city: CityResult) = discovery.selectCity(city)

    // ---------------------------------------------------------------- detail and lists

    fun selectEvent(id: String) = library.select(id)
    fun dismissEvent() = library.dismiss()
    fun loadMyEvents() = library.load()

    // ---------------------------------------------------------------- mutations

    /**
     * One mutation at a time. A second tap while the first is in flight is a double tap, not a
     * second intent, and letting both through is how duplicate joins happen.
     */
    private fun mutate(block: suspend () -> Unit) {
        if (mutationJob?.isActive == true) { PoruchLog.w("action") { "ignored: a mutation is already running" }; return }
        mutationJob = scope.launch {
            mutable.update { it.copy(mutating = true, notice = null) }
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("action") { "failed: $error" }
                mutable.update { it.copy(notice = AppNotice.Failed(error)) }
            } finally {
                mutable.update { it.copy(mutating = false) }
            }
        }
    }

    private fun tell(message: AppMessage) = mutable.update { it.copy(notice = AppNotice.Told(message)) }

    /** Re-reads everything a change to [id] could have touched. */
    private fun changed(id: String) {
        refresh(); loadMyEvents()
        if (library.openEventId == id) library.select(id)
    }

    fun joinEvent(id: String) = mutate {
        PoruchLog.i("action") { "joinEvent ${id.shortId()}" }
        eventActions.join(id); changed(id); tell(AppMessage.JOINED_EVENT)
    }

    fun joinWaitlist(id: String) = mutate {
        PoruchLog.i("action") { "joinWaitlist ${id.shortId()}" }
        events.joinWaitlist(id); changed(id); tell(AppMessage.JOINED_WAITLIST)
    }

    fun leaveWaitlist(id: String) = mutate {
        PoruchLog.i("action") { "leaveWaitlist ${id.shortId()}" }
        events.leaveWaitlist(id); changed(id)
    }

    fun leaveEvent(id: String) = mutate {
        PoruchLog.i("action") { "leaveEvent ${id.shortId()}" }
        eventActions.leave(id); changed(id)
    }

    fun cancelEvent(id: String) = mutate {
        PoruchLog.i("action") { "cancelEvent ${id.shortId()}" }
        eventActions.cancel(id); changed(id)
    }

    fun toggleSaved(id: String) = mutate {
        PoruchLog.i("action") { "toggleSaved ${id.shortId()}" }
        if (!state.value.signedIn) fail(AppError.SessionRequired)
        if (state.value.isSaved(id)) events.unsave(id) else events.save(id)
        mutable.update { it.copy(savedIds = events.savedIds()) }
    }

    @OptIn(ExperimentalUuidApi::class)
    fun createEvent(draft: EventDraft) = mutate {
        val id = creationIdentity?.idFor(draft)
            ?: pendingCreation?.takeIf { it.first == draft }?.second
            ?: Uuid.random().toString().also { pendingCreation = draft to it }
        PoruchLog.i("action") { "createEvent ${id.shortId()} category=${draft.category} capacity=${draft.capacity}" }
        val created = eventActions.create(id, draft)
        pendingCreation = null; creationIdentity?.clear()
        changed(created); selectEvent(created)
        mutable.update { it.copy(notice = AppNotice.Told(AppMessage.EVENT_PUBLISHED), completedEventId = created) }
    }

    fun updateEvent(id: String, draft: EventDraft) = mutate {
        PoruchLog.i("action") { "updateEvent ${id.shortId()} capacity=${draft.capacity}" }
        eventActions.update(id, draft); changed(id)
        mutable.update { it.copy(notice = AppNotice.Told(AppMessage.CHANGES_SAVED), completedEventId = id) }
    }

    fun uploadEventImage(eventId: String, bytes: ByteArray, contentType: String) = mutate {
        val event = events.details(eventId) ?: fail(AppError.EventUnavailable)
        if (event.organizerId != auth.session.value?.userId) fail(AppError.NotOwner)
        val url = events.uploadImage(eventId, bytes, contentType)
        events.update(
            eventId,
            EventDraft(
                event.title, event.description, event.category, event.city, event.address,
                event.latitude, event.longitude, event.startsAt, event.endsAt, event.timeZone,
                event.capacity, url
            )
        )
        changed(eventId); tell(AppMessage.PHOTO_ADDED)
    }

    fun toggleInterest(category: String) = mutate {
        if (!EventRules.isCategory(category)) return@mutate
        val store = preferences ?: fail(AppError.SessionRequired)
        val selected = state.value.interests
        val next = if (category in selected) selected - category else selected + category
        store.setInterests(next)
        mutable.update { it.copy(interests = next) }
    }

    // ---------------------------------------------------------------- account

    fun signIn(email: String, password: String) = mutate {
        PoruchLog.i("auth") { "sign in requested" }
        accountActions.signIn(email, password)
        tell(AppMessage.SIGNED_IN); refresh(); loadMyEvents()
    }

    fun signUp(email: String, password: String, name: String) = mutate {
        PoruchLog.i("auth") { "sign up requested" }
        val signedIn = accountActions.signUp(email, password, name)
        PoruchLog.i("auth") { "sign up ${if (signedIn) "signed in immediately" else "awaiting email confirmation"}" }
        tell(if (signedIn) AppMessage.ACCOUNT_CREATED else AppMessage.CONFIRM_EMAIL_FIRST)
    }

    fun signOut() = mutate {
        PoruchLog.i("auth") { "sign out" }
        // Local state goes even if the server call fails: the user asked to be signed out.
        try { auth.signOut() } finally {
            library.clear()
            mutable.update { it.copy(userId = null) }
            refresh()
        }
    }

    fun requestPasswordReset(email: String) = mutate {
        if (!AccountRules.isEmail(email)) fail(AppError.InvalidEmail)
        auth.requestPasswordReset(email)
        tell(AppMessage.RECOVERY_SENT)
    }

    fun updatePassword(password: String) = mutate {
        if (!AccountRules.isPassword(password)) fail(AppError.WeakPassword)
        auth.updatePassword(password)
        mutable.update { it.copy(passwordRecovery = false, notice = AppNotice.Told(AppMessage.PASSWORD_CHANGED)) }
    }

    fun handleAuthCallback(url: String) = mutate {
        PoruchLog.i("auth") { "handling auth callback" }
        val recovery = auth.handleCallback(url)
        synchronizeIdentity(auth.session.value?.userId)
        mutable.update {
            it.copy(
                passwordRecovery = recovery,
                notice = AppNotice.Told(if (recovery) AppMessage.SET_NEW_PASSWORD else AppMessage.EMAIL_CONFIRMED)
            )
        }
        refresh(); loadMyEvents()
    }

    // ---------------------------------------------------------------- one-shot state

    fun clearNotice() { mutable.update { it.copy(notice = null) } }
    fun clearCompletedEvent() { mutable.update { it.copy(completedEventId = null) } }
    fun close() { scope.cancel() }
}
