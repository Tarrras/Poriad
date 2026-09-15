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
 * Єдиний стор, за яким стежать обидві платформи. Тримає стан і задачі, що його змінюють.
 * Читання й фільтрація — у [DiscoveryEngine] та [UserLibrary]; тут лишаються дії екранів і сесія.
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
    /** Стан живе на головному потоці: звідси читають і Compose, і SwiftUI. */
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
    /** Де рахувати важке. Порожньо за замовчуванням, щоб тести під `runTest` нічого не знали; [AppGraph] підставляє диспетчер. */
    compute: CoroutineContext = EmptyCoroutineContext
) {
    // Відповіді читаємо синхронно: від них залежить, чи перший кадр — онбординг чи застосунок.
    private val mutable = MutableStateFlow(
        AppState(userId = auth.session.value?.userId, taste = tasteStore?.read() ?: Taste())
    )
    val state: StateFlow<AppState> = mutable.asStateFlow()

    private val discovery = DiscoveryEngine(events, geo, mutable, scope, config.home, compute)
    private val library = UserLibrary(events, saved, participation, requests, auth, preferences, safety, tasteStore, mutable, scope)

    private var mutationJob: Job? = null
    /** Повтор непевного створення має взяти той самий id, інакше опублікує другу подію. */
    private var pendingCreation: Pair<EventDraft, String>? = null

    init {
        discovery.onQueryChanged = library::dismiss
        scope.launch {
            auth.session.map { it?.userId }.distinctUntilChanged().collect(::synchronizeIdentity)
        }
        refresh()
        if (state.value.signedIn) loadMyEvents()
    }

    // ---- Сесія

    private fun synchronizeIdentity(uid: String?) {
        if (mutable.value.userId == uid) {
            mutable.update { it.copy(userId = uid) }
            return
        }
        PoruchLog.i("session") { "identity → ${uid.shortId()}, clearing private state" }
        pendingCreation = null
        library.clear()
        mutable.update {
            it.copy(
                userId = uid, events = emptyList(), passwordRecovery = false, completedEventId = null,
                // Вхід або підтвердження з листа: наступний крок реєстрації вже не потрібен.
                awaitingConfirmation = if (uid != null) null else it.awaitingConfirmation
            )
        }
        refresh()
        if (uid != null) loadMyEvents()
    }

    fun observe(onChange: (AppState) -> Unit): Subscription {
        val job = scope.launch { state.collect { onChange(it) } }
        return Subscription { job.cancel() }
    }

    // ---- Пошук

    fun refresh() = discovery.refresh()

    /** Стрічка дійшла до краю: індекс повний, довантажуємо ще карток за відомими id. */
    fun loadMore(upTo: Int) = discovery.materialize(upTo)

    /** Картки названих подій, напр. стос майданчика під пальцем. */
    fun loadCards(ids: List<String>) = discovery.loadCards(ids)

    /**
     * Сеанси прокату, до якого належить подія, за часом. Без запиту: дати вже в індексі, але
     * лише в межах поточної видачі (під «Сьогодні» — сьогоднішні). Приймає id будь-якого сеансу.
     */
    fun sessionsOf(id: String): List<EventSession> =
        state.value.index.firstOrNull { run -> run.sessions.any { it.id == id } }?.sessions
            ?: emptyList()

    /**
     * Сеанси для каруселі на екрані деталей. На відміну від [sessionsOf] за id, бачить і
     * скасований сеанс, якого в індексі нема. Див. [EventSeries.sessionsOf].
     */
    fun sessionsOf(event: Event): List<EventSession> = EventSeries.sessionsOf(event, state.value.index)

    /**
     * Id картки, під якою подія стоїть у видачі: для сеансу прокату — представник, для решти — вона
     * сама. Потрібно мапі, відкритій з другої дати прокату: окремого піна для неї нема.
     */
    fun cardIdOf(id: String): String =
        state.value.index.firstOrNull { run -> run.sessions.any { it.id == id } }?.id ?: id
    fun searchArea(south: Double, west: Double, north: Double, east: Double) = discovery.searchArea(south, west, north, east)
    fun setSearchText(query: String) = discovery.setSearchText(query)
    fun setOnlyAvailable(available: Boolean) = discovery.setOnlyAvailable(available)
    fun setCategory(category: String) = discovery.setCategory(category)
    fun setDateFilter(filter: String) = discovery.setDateFilter(filter)
    fun searchCity(query: String) = discovery.searchCity(query)

    /**
     * Підказки адрес для редактора. Відповідь у колбек, а не в стан: підказки належать чернетці
     * екрана. Порожній список — просто нічого не знайшли.
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

    /** Адреса поставленої крапки, зворотний бік [searchAddress]. Null — у полі лишається старе. */
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

    /** Пояс місця події для редактора. Null — не визначили, екран лишає пояс пристрою. */
    fun resolveTimeZone(latitude: Double, longitude: Double, onResolved: (String?) -> Unit) {
        val locator = timeZones ?: return onResolved(null)
        scope.launch { onResolved(locator.zoneAt(latitude, longitude)) }
    }
    fun selectCity(city: CityResult) = discovery.selectCity(city)

    // ---- Деталі й списки

    /** Підсвітити подію: пін на мапі, картка в каруселі. Без мережі, якщо рядок уже є. */
    fun selectEvent(id: String) = library.select(id)

    /**
     * Відкрити екран деталей: тут місця й членство вже варті запиту. Для прокату одразу
     * підтягує картки інших сеансів, щоб вибір дати в каруселі не показував порожній екран.
     */
    fun openEvent(id: String) {
        library.select(id, full = true)
        discovery.prefetch(sessionsOf(id).map { it.id }.filter { it != id })
    }

    fun dismissEvent() = library.dismiss()
    fun loadMyEvents() = library.load()

    // ---- Зміни

    /** Одна зміна за раз: другий тап під час першої — це подвійний тап, а не другий намір. */
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

    /** Перечитує все, чого могла торкнутися зміна [id]. */
    private fun changed(id: String) {
        refresh(); loadMyEvents()
        // Повний запит, бо змінилося саме те, що знає лише сервер: учасники й членство.
        if (library.openEventId == id) library.select(id, full = true)
    }

    fun joinEvent(id: String) = mutate {
        PoruchLog.i("action") { "joinEvent ${id.shortId()}" }
        // Подія з підтвердженням відповідає запитом, а не місцем, тож і повідомлення інше.
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
     * Закладка змінюється оптимістично, поза [mutate]: стан одразу, запит окремо, при збої
     * повертаємо як було й показуємо помилку.
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
        // Фото має лише кімната: в афіші нема власника.
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

    // ---- Смак

    /** Відповіді онбордингу. Словник перевіряємо тут, а не довіряємо екрану; зберігаємо на пристрої, щоб мав і гість. */
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
        // Акаунт переносить категорії на інший пристрій; решта лишається тут.
        if (state.value.signedIn) preferences?.setInterests(answered.interests)
    }

    /** «Не зараз»: питання закриті, ранжуємо лише за часом. */
    fun skipOnboarding() {
        PoruchLog.i("taste") { "onboarding skipped" }
        applyTaste(state.value.taste.copy(answered = true))
    }

    /** Знову відкриває питання з профілю, з поточними відповідями як початковими. */
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

    // ---- Безпека

    /** Вік для акаунта, створеного до появи питання. Дозволено раз; далі це справа модерації. */
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

    /** Блокування взаємне й миттєве: події людини зникають з мапи при наступному читанні. */
    fun blockUser(userId: String) = mutate {
        val store = safety ?: fail(AppError.ServiceUnavailable)
        if (!state.value.signedIn) fail(AppError.SessionRequired)
        PoruchLog.i("safety") { "block ${userId.shortId()}" }
        store.block(userId)
        // Блок діє на сервері, тож перечитуємо: мапа й «мої події» повертаються відфільтрованими.
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

    // ---- Акаунт

    fun signIn(email: String, password: String) = mutate {
        PoruchLog.i("auth") { "sign in requested" }
        accountActions.signIn(email, password)
        tell(AppMessage.SIGNED_IN); refresh(); loadMyEvents()
    }

    /** [birthDate] — ISO-8601. Платформа лише для дорослих, і перевірка починається тут. */
    fun signUp(email: String, password: String, name: String, birthDate: String) = mutate {
        PoruchLog.i("auth") { "sign up requested" }
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val signedIn = accountActions.signUp(email, password, name, birthDate, today)
        PoruchLog.i("auth") { "sign up ${if (signedIn) "signed in immediately" else "awaiting email confirmation"}" }
        // Без сесії відповідь — не банер, а окремий крок: екран входу показує, куди пішов лист і що далі.
        if (signedIn) tell(AppMessage.ACCOUNT_CREATED)
        else mutable.update { it.copy(awaitingConfirmation = email.trim()) }
    }

    /** Людина повернулась до форми або закрила екран: крок «перевірте пошту» більше не показуємо. */
    fun dismissConfirmationStep() { mutable.update { it.copy(awaitingConfirmation = null) } }

    fun signOut() = mutate {
        PoruchLog.i("auth") { "sign out" }
        // Локальний стан чистимо навіть якщо сервер відмовив: людина попросила вийти.
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

    // ---- Одноразовий стан

    fun clearNotice() { mutable.update { it.copy(notice = null) } }
    fun clearCompletedEvent() { mutable.update { it.copy(completedEventId = null) } }
    fun close() { scope.cancel() }
}
