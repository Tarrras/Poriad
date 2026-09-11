package app.poruch.shared

import app.poruch.domain.*
import app.poruch.events.EventActions
import app.poruch.account.AccountActions
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.time.Clock
import kotlin.uuid.Uuid
import kotlin.uuid.ExperimentalUuidApi

/**
 * The single store both platforms observe. It owns the state and the jobs that change it; reading
 * and filtering live in [DiscoveryEngine] and [UserLibrary], and what remains here are the verbs a
 * screen can invoke and the session they all depend on.
 */
class PoruchApp internal constructor(
    private val events: EventDiscovery,
    private val saved: SavedEvents,
    private val authoring: EventAuthoring,
    private val participation: EventParticipation,
    private val requests: EventRequests,
    private val auth: AuthRepository,
    geo: GeoSearchRepository,
    private val eventActions: EventActions,
    private val accountActions: AccountActions,
    private val preferences: PreferencesRepository? = null,
    private val safety: SafetyRepository? = null,
    private val tasteStore: TasteStore? = null,
    private val creationIdentity: CreationIdentityStore? = null,
    private val timeZones: TimeZoneLocator? = null,
    private val addresses: AddressSearch? = null,
    config: AppConfig = AppConfig("", ""),
    /** Де живе стан. Головний потік навмисно: звідси читають і Compose, і SwiftUI. */
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
    /**
     * Де рахувати те, що не має рахуватись у [scope]. Порожньо за замовчуванням — тоді все
     * лишається на місці, і тест під `runTest` не мусить нічого про це знати. Збірка підставляє
     * справжній диспетчер у [AppGraph].
     */
    compute: CoroutineContext = EmptyCoroutineContext
) {
    // The answers are read straight off the device, not awaited: they decide whether the first
    // frame is the onboarding or the app, and a suspending read there would flash the wrong one.
    private val mutable = MutableStateFlow(
        AppState(userId = auth.session.value?.userId, taste = tasteStore?.read() ?: Taste())
    )
    val state: StateFlow<AppState> = mutable.asStateFlow()

    private val discovery = DiscoveryEngine(events, geo, mutable, scope, config.home, compute)
    private val library = UserLibrary(events, saved, participation, requests, auth, preferences, safety, tasteStore, mutable, scope)

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

    /**
     * Стрічка дійшла до краю завантаженого. Індекс уже повний, тож це не «наступна сторінка» — це
     * ще кілька карток за вже відомими ідентифікаторами.
     */
    fun loadMore(upTo: Int) = discovery.materialize(upTo)

    /** Картки названих подій: стос майданчика під пальцем. */
    fun loadCards(ids: List<String>) = discovery.loadCards(ids)
    fun searchArea(south: Double, west: Double, north: Double, east: Double) = discovery.searchArea(south, west, north, east)
    fun setSearchText(query: String) = discovery.setSearchText(query)
    fun setOnlyAvailable(available: Boolean) = discovery.setOnlyAvailable(available)
    fun setCategory(category: String) = discovery.setCategory(category)
    fun setDateFilter(filter: String) = discovery.setDateFilter(filter)
    fun searchCity(query: String) = discovery.searchCity(query)

    /**
     * Адреси, що збігаються з набраним, — щоб координати не набирали руками.
     *
     * Відповідь приходить у зворотний виклик, а не в стан: підказки належать чернетці, яку тримає
     * екран редактора. Порожній список означає «нічого не знайшли» і нічого більше — крапку
     * завжди можна поставити на мапі.
     */
    fun searchAddress(
        query: String,
        latitude: Double,
        longitude: Double,
        onFound: (List<PlaceResult>) -> Unit
    ) {
        val search = addresses ?: return onFound(emptyList())
        scope.launch {
            val found = try {
                search.places(query, latitude, longitude)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                emptyList()
            }
            onFound(found)
        }
    }

    /**
     * Адреса поставленої крапки.
     *
     * Друга половина тієї самої синхронізації, що й [searchAddress]: поле й мапа показують одну
     * адресу, тож рухати її можна з обох боків. `null` означає «не впізнали місце» — тоді в полі
     * лишається те, що там уже стоїть.
     */
    fun resolveAddress(latitude: Double, longitude: Double, onFound: (PlaceResult?) -> Unit) {
        val search = addresses ?: return onFound(null)
        scope.launch {
            val found = try {
                search.placeAt(latitude, longitude)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
            onFound(found)
        }
    }

    /**
     * Пояс місця події — щоб його не набирали руками.
     *
     * Відповідь приходить у зворотний виклик, а не в стан: пояс належить чернетці, яку тримає
     * екран редактора, а не застосунку. `null` означає «не визначили» — тоді екран лишає те, що
     * вже стоїть, тобто пояс пристрою.
     */
    fun resolveTimeZone(latitude: Double, longitude: Double, onResolved: (String?) -> Unit) {
        val locator = timeZones ?: return onResolved(null)
        scope.launch { onResolved(locator.zoneAt(latitude, longitude)) }
    }
    fun selectCity(city: CityResult) = discovery.selectCity(city)

    // ---------------------------------------------------------------- detail and lists

    /** Підсвітити подію: пін на мапі, картка в каруселі. Без мережі, якщо рядок уже є. */
    fun selectEvent(id: String) = library.select(id)

    /** Відкрити екран деталей. Тут лічильник місць і членство вже варті запиту. */
    fun openEvent(id: String) = library.select(id, full = true)

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
        // Саме тут дешевий шлях був би шкідливий: після приєднання змінилося рівно те, що знає
        // лише сервер — число учасників і наше членство.
        if (library.openEventId == id) library.select(id, full = true)
    }

    fun joinEvent(id: String) = mutate {
        PoruchLog.i("action") { "joinEvent ${id.shortId()}" }
        // An event that vets its guests answers with a request, not a seat, so it is worded as one.
        val byRequest = (state.value.selectedEvent?.takeIf { it.id == id }
            ?: state.value.events.firstOrNull { it.id == id })?.gathering?.approvalRequired == true
        eventActions.join(id); changed(id)
        tell(if (byRequest) AppMessage.REQUEST_SENT else AppMessage.JOINED_EVENT)
    }

    fun joinWaitlist(id: String) = mutate {
        PoruchLog.i("action") { "joinWaitlist ${id.shortId()}" }
        participation.joinWaitlist(id); changed(id); tell(AppMessage.JOINED_WAITLIST)
    }

    fun leaveWaitlist(id: String) = mutate {
        PoruchLog.i("action") { "leaveWaitlist ${id.shortId()}" }
        participation.leaveWaitlist(id); changed(id)
    }

    fun leaveEvent(id: String) = mutate {
        PoruchLog.i("action") { "leaveEvent ${id.shortId()}" }
        eventActions.leave(id); changed(id)
    }

    fun cancelEvent(id: String) = mutate {
        PoruchLog.i("action") { "cancelEvent ${id.shortId()}" }
        eventActions.cancel(id); changed(id)
    }

    /**
     * Закладка змінюється миттєво, а мережа лише підтверджує.
     *
     * Це найдешевша дія в застосунку, і поводитись вона мала б відповідно. Досі вона йшла через
     * [mutate] — тобто вмикала загальний індикатор, блокувала будь-яку іншу зміну до свого
     * завершення й робила **два** послідовні запити: записати, а потім перечитати весь список,
     * щоб дізнатися те, що ми вже знали. Іконка перемикалася аж після обох.
     *
     * Тепер стан міняється одразу, запит іде сам по собі, а якщо не вдався — повертаємо як було
     * й кажемо про це. Гірший випадок — закладка блимне назад; кращий, теперішній, — вона
     * спрацьовує тоді, коли по ній тицьнули.
     */
    fun toggleSaved(id: String) {
        if (!state.value.signedIn) {
            mutable.update { it.copy(notice = AppNotice.Failed(AppError.SessionRequired)) }
            return
        }
        val wasSaved = state.value.isSaved(id)
        PoruchLog.i("action") { "toggleSaved ${id.shortId()} saved=${!wasSaved}" }
        mutable.update { it.copy(savedIds = it.savedIds.toggling(id, add = !wasSaved)) }
        scope.launch {
            try {
                if (wasSaved) saved.unsave(id) else saved.save(id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("action") { "toggleSaved ${id.shortId()} failed: $error" }
                mutable.update {
                    it.copy(savedIds = it.savedIds.toggling(id, add = wasSaved), notice = AppNotice.Failed(error))
                }
            }
        }
    }

    private fun List<String>.toggling(id: String, add: Boolean) =
        if (add) (this + id).distinct() else this - id

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
        // Фото має лише кімната: у афіші немає ні власника, який його додає, ні прав на нього.
        val room = event.gathering ?: fail(AppError.NotOwner)
        if (room.organizerId != auth.session.value?.userId) fail(AppError.NotOwner)
        val url = authoring.uploadImage(eventId, bytes, contentType)
        authoring.update(
            eventId,
            EventDraft(
                event.title, event.description, event.category, event.city, event.address,
                event.latitude, event.longitude, event.startsAt, event.endsAt, event.timeZone,
                room.capacity, url, room.minAge, room.maxAge, room.approvalRequired
            )
        )
        changed(eventId); tell(AppMessage.PHOTO_ADDED)
    }

    // ---------------------------------------------------------------- taste

    /**
     * The opening questions, answered. What comes back from a screen is unvalidated — a category
     * the build no longer ships would rank against nothing — so the vocabulary is checked here
     * rather than trusted, and the answers are kept on the device where a guest also has them.
     */
    fun saveTaste(interests: List<String>, times: List<String>, crowd: String) = mutate {
        val answered = Taste(
            interests = interests.filter(EventRules::isCategory).distinct(),
            times = times.filter(TimeSlot::isSlot).distinct(),
            crowd = crowd.takeIf(Crowd::isCrowd) ?: Crowd.ANY,
            answered = true
        )
        PoruchLog.i("taste") {
            "answered: ${answered.interests.size} interests, ${answered.times.size} slots, crowd=${answered.crowd}"
        }
        applyTaste(answered)
        // An account carries its categories to the next device; the rest stays on this one.
        if (state.value.signedIn) preferences?.setInterests(answered.interests)
    }

    /** «Не зараз». The questions are done with, and the app goes back to ranking by time alone. */
    fun skipOnboarding() {
        PoruchLog.i("taste") { "onboarding skipped" }
        applyTaste(state.value.taste.copy(answered = true))
    }

    /** Reopens the questions from the profile, with the current answers as their starting point. */
    fun restartOnboarding() = applyTaste(state.value.taste.copy(answered = false))

    fun toggleInterest(category: String) = mutate {
        if (!EventRules.isCategory(category)) return@mutate
        val selected = state.value.taste.interests
        val next = if (category in selected) selected - category else selected + category
        applyTaste(state.value.taste.copy(interests = next))
        if (state.value.signedIn) preferences?.setInterests(next)
    }

    private fun applyTaste(taste: Taste) {
        tasteStore?.write(taste)
        mutable.update { it.copy(taste = taste).ranked() }
    }

    // ---------------------------------------------------------------- safety

    /**
     * States an age for an account made before the app asked for one. Allowed once — after that a
     * declared age is a moderation matter, which is also why the server, not this, decides.
     */
    fun declareBirthDate(birthDate: String) = mutate {
        val store = safety ?: fail(AppError.ServiceUnavailable)
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val declared = runCatching { LocalDate.parse(birthDate) }.getOrElse { fail(AppError.Rejected) }
        if (!SafetyRules.isSignupAge(declared, today)) fail(AppError.Underage)
        store.declareBirthDate(declared.toString())
        mutable.update { it.copy(account = it.account.copy(birthDate = declared.toString())) }
        tell(AppMessage.AGE_CONFIRMED)
    }

    fun reportEvent(eventId: String, reason: String, details: String? = null) = mutate {
        val store = safety ?: fail(AppError.ServiceUnavailable)
        if (!state.value.signedIn) fail(AppError.SessionRequired)
        PoruchLog.i("safety") { "report event ${eventId.shortId()} reason=$reason" }
        store.reportEvent(eventId, reason, details)
        tell(AppMessage.REPORT_SENT)
    }

    fun reportUser(userId: String, reason: String, details: String? = null) = mutate {
        val store = safety ?: fail(AppError.ServiceUnavailable)
        if (!state.value.signedIn) fail(AppError.SessionRequired)
        PoruchLog.i("safety") { "report user ${userId.shortId()} reason=$reason" }
        store.reportUser(userId, reason, details)
        tell(AppMessage.REPORT_SENT)
    }

    /**
     * Blocking is mutual and immediate: their events leave this account's map on the next read, and
     * the door closes in both directions. Refreshing is part of the action, not a nicety.
     */
    fun blockUser(userId: String) = mutate {
        val store = safety ?: fail(AppError.ServiceUnavailable)
        if (!state.value.signedIn) fail(AppError.SessionRequired)
        PoruchLog.i("safety") { "block ${userId.shortId()}" }
        store.block(userId)
        // The block takes effect on the server, so the app asks again rather than guessing: the
        // map, «my events» and the blocked list all come back already filtered.
        mutable.update { it.copy(selectedEvent = null, joinRequests = emptyList()) }
        library.dismiss(); refresh(); loadMyEvents()
        tell(AppMessage.USER_BLOCKED)
    }

    fun unblockUser(userId: String) = mutate {
        val store = safety ?: fail(AppError.ServiceUnavailable)
        store.unblock(userId)
        mutable.update { it.copy(blocked = it.blocked.filterNot { person -> person.userId == userId }) }
        refresh(); loadMyEvents()
    }

    fun approveMember(eventId: String, userId: String) = mutate {
        PoruchLog.i("safety") { "approve ${userId.shortId()} for ${eventId.shortId()}" }
        requests.approveMember(eventId, userId); changed(eventId)
    }

    fun declineMember(eventId: String, userId: String) = mutate {
        PoruchLog.i("safety") { "decline ${userId.shortId()} for ${eventId.shortId()}" }
        requests.declineMember(eventId, userId); changed(eventId)
    }

    // ---------------------------------------------------------------- account

    fun signIn(email: String, password: String) = mutate {
        PoruchLog.i("auth") { "sign in requested" }
        accountActions.signIn(email, password)
        tell(AppMessage.SIGNED_IN); refresh(); loadMyEvents()
    }

    /** [birthDate] is ISO-8601. The platform is adults-only, and this is where that starts. */
    fun signUp(email: String, password: String, name: String, birthDate: String) = mutate {
        PoruchLog.i("auth") { "sign up requested" }
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val signedIn = accountActions.signUp(email, password, name, birthDate, today)
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
