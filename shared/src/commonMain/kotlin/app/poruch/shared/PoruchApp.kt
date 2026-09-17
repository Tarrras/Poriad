package app.poruch.shared

import app.poruch.account.AccountActions
import app.poruch.domain.*
import app.poruch.events.EventActions
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.StateFlow
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

/**
 * Єдиний стор, за яким стежать обидві платформи: фасад із дієсловами екранів над [AppState].
 * Логіка живе поруч: читання й фільтрація — у [DiscoveryEngine], [UserLibrary] і [ChatEngine];
 * дії — у [EventUseCases], [SessionUseCases], [SafetyUseCases], [TasteUseCases]; сесія й пуші —
 * в [IdentitySync] і [PushSync]. Правило «одна зміна за раз» тримає [AppStore].
 */
class PoruchApp internal constructor(
    events: EventDiscovery,
    saved: SavedEvents,
    authoring: EventAuthoring,
    participation: EventParticipation,
    requests: EventRequests,
    chat: EventChat,
    push: PushTokens? = null,
    auth: AuthRepository,
    geo: GeoSearchRepository,
    eventActions: EventActions,
    accountActions: AccountActions,
    preferences: PreferencesRepository? = null,
    safety: SafetyRepository? = null,
    tasteStore: TasteStore? = null,
    creationIdentity: CreationIdentityStore? = null,
    timeZones: TimeZoneLocator? = null,
    addresses: AddressSearch? = null,
    private val reminderStore: ReminderPreferenceStore? = null,
    /** Системний планувальник нагадувань. Null у тестах і превʼю: план рахується, але нікуди не йде. */
    reminders: ReminderScheduler? = null,
    /** Сповіщення про нові запити на участь: сховище «бачених» і платформний показ. Обидва або нічого. */
    seenRequests: SeenRequestStore? = null,
    requestNotifier: RequestNotifier? = null,
    /** Сповіщення про нові повідомлення в чатах: окремий список «бачених» і показ. Обидва або нічого. */
    seenMessages: SeenRequestStore? = null,
    chatNotifier: ChatNotifier? = null,
    config: AppConfig = AppConfig("", ""),
    /** Стан живе на головному потоці: звідси читають і Compose, і SwiftUI. */
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
    /** Де рахувати важке. Порожньо за замовчуванням, щоб тести під `runTest` нічого не знали; [AppGraph] підставляє диспетчер. */
    compute: CoroutineContext = EmptyCoroutineContext
) {
    // Відповіді читаємо синхронно: від них залежить, чи перший кадр — онбординг чи застосунок.
    private val store = AppStore(
        AppState(
            userId = auth.session.value?.userId, taste = tasteStore?.read() ?: Taste(),
            remindersEnabled = reminderStore?.enabled() ?: false
        ),
        scope
    )
    val state: StateFlow<AppState> get() = store.state

    private val discovery = DiscoveryEngine(events, geo, store.flow, scope, config.home, compute)
    private val library = UserLibrary(events, saved, participation, requests, chat, auth, preferences, safety, tasteStore, store.flow, scope)
    private val chatEngine = ChatEngine(chat, store.flow, scope)
    private val reloader = Reloader(discovery, library)
    private val pushSync = PushSync(push, seenRequests, seenMessages, store)
    private val places = PlaceLookup(addresses, timeZones, scope)
    private val eventUseCases = EventUseCases(events, saved, authoring, participation, requests, auth, eventActions, creationIdentity, store, library, reloader)
    private val identity = IdentitySync(auth, store, discovery, library, chatEngine, pushSync, eventUseCases)
    private val sessionUseCases = SessionUseCases(auth, accountActions, store, identity, pushSync, reloader)
    private val safetyUseCases = SafetyUseCases(safety, store, library, reloader)
    private val tasteUseCases = TasteUseCases(tasteStore, preferences, store)

    init {
        discovery.onQueryChanged = library::dismiss
        identity.start()
        refresh()
        if (state.value.signedIn) loadMyEvents()
        if (reminders != null) ReminderSync(state, reminders, scope).start()
        if (requestNotifier != null && seenRequests != null) RequestAlertSync(state, seenRequests, requestNotifier, scope).start()
        if (chatNotifier != null && seenMessages != null) ChatAlertSync(state, seenMessages, chatNotifier, scope).start()
    }

    fun observe(onChange: (AppState) -> Unit): Subscription {
        val job = scope.launch { state.collect { onChange(it) } }
        return Subscription { job.cancel() }
    }

    // ---- Пуші

    /** Платформа отримала або оновила токен. Реєструється під кожним акаунтом, з яким входять. */
    fun pushTokenChanged(token: String, platform: String) = pushSync.tokenChanged(token, platform)

    /** Пуш прийшов на цей пристрій: перечитуємо стан, щоб бейджі й списки відповідали. */
    fun pushReceived(kind: String, key: String) { pushSync.received(kind, key); resume() }

    // ---- Пошук

    fun refresh() = discovery.refresh()

    /** Стрічка дійшла до краю: індекс повний, довантажуємо ще карток за відомими id. */
    fun loadMore(upTo: Int) = discovery.materialize(upTo)

    /** Картки названих подій, напр. стос майданчика під пальцем. */
    fun loadCards(ids: List<String>) = discovery.loadCards(ids)

    /** Сеанси прокату за id будь-якого сеансу, в межах поточної видачі. Див. [AppState.sessionsOf]. */
    fun sessionsOf(id: String): List<EventSession> = state.value.sessionsOf(id)

    /**
     * Сеанси для каруселі на екрані деталей. На відміну від [sessionsOf] за id, бачить і
     * скасований сеанс, якого в індексі нема. Див. [EventSeries.sessionsOf].
     */
    fun sessionsOf(event: Event): List<EventSession> = EventSeries.sessionsOf(event, state.value.index)

    /** Id картки, під якою подія стоїть у видачі. Див. [AppState.cardIdOf]. */
    fun cardIdOf(id: String): String = state.value.cardIdOf(id)

    fun searchArea(south: Double, west: Double, north: Double, east: Double) = discovery.searchArea(south, west, north, east)
    fun setSearchText(query: String) = discovery.setSearchText(query)
    fun setOnlyAvailable(available: Boolean) = discovery.setOnlyAvailable(available)
    fun setCategory(category: String) = discovery.setCategory(category)
    fun setDateFilter(filter: String) = discovery.setDateFilter(filter)
    fun searchCity(query: String) = discovery.searchCity(query)
    fun selectCity(city: CityResult) = discovery.selectCity(city)

    /** Підказки адрес для редактора. Порожній список — просто нічого не знайшли. */
    fun searchAddress(query: String, latitude: Double, longitude: Double, onFound: (List<PlaceResult>) -> Unit) =
        places.searchAddress(query, latitude, longitude, onFound)

    /** Адреса поставленої крапки, зворотний бік [searchAddress]. Null — у полі лишається старе. */
    fun resolveAddress(latitude: Double, longitude: Double, onFound: (PlaceResult?) -> Unit) =
        places.resolveAddress(latitude, longitude, onFound)

    /** Пояс місця події для редактора. Null — не визначили, екран лишає пояс пристрою. */
    fun resolveTimeZone(latitude: Double, longitude: Double, onResolved: (String?) -> Unit) =
        places.resolveTimeZone(latitude, longitude, onResolved)

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

    /** Повернення на передній план: перечитує мапу, «мої» і відкриту подію. */
    fun resume() = reloader.all()

    // ---- Оновлення жестом

    /**
     * Потяг головної вниз: перечитує те саме, що [resume], але повертається лише коли відповіді
     * приїхали, щоб індикатор знав, коли сховатись. Збій не кидає: він уже в [AppState.notice].
     */
    suspend fun reloadAll() { resume(); reloader.awaitAll() }

    /** Потяг «моїх подій» вниз. Див. [reloadAll]. */
    suspend fun reloadMyEvents() { loadMyEvents(); library.awaitList() }

    /** Потяг деталей вниз: місця, членство й запити перечитуються, як при відкритті. Див. [reloadAll]. */
    suspend fun reloadEvent(id: String) { openEvent(id); library.awaitDetail() }

    // ---- Чат події

    /** Екран чату відкрито: тягнемо хвіст і перечитуємо, поки не закриють. */
    fun openChat(eventId: String) = chatEngine.open(eventId)
    fun closeChat() = chatEngine.close()
    fun sendMessage(text: String) = chatEngine.send(text)
    fun deleteMessage(messageId: String) = chatEngine.delete(messageId)
    fun reportMessage(messageId: String, reason: String, details: String? = null) = safetyUseCases.reportMessage(messageId, reason, details)

    // ---- Події

    fun joinEvent(id: String) = eventUseCases.join(id)
    fun joinWaitlist(id: String) = eventUseCases.joinWaitlist(id)
    fun leaveWaitlist(id: String) = eventUseCases.leaveWaitlist(id)
    fun leaveEvent(id: String) = eventUseCases.leave(id)
    fun cancelEvent(id: String) = eventUseCases.cancel(id)
    /** Закладка спрацьовує одразу, запит іде окремо; при збої повертається як було. */
    fun toggleSaved(id: String) = eventUseCases.toggleSaved(id)
    fun createEvent(draft: EventDraft) = eventUseCases.create(draft)
    fun updateEvent(id: String, draft: EventDraft) = eventUseCases.update(id, draft)
    fun uploadEventImage(eventId: String, bytes: ByteArray, contentType: String) = eventUseCases.uploadImage(eventId, bytes, contentType)
    fun approveMember(eventId: String, userId: String) = eventUseCases.approveMember(eventId, userId)
    fun declineMember(eventId: String, userId: String) = eventUseCases.declineMember(eventId, userId)

    // ---- Смак і нагадування

    /** Відповіді онбордингу. Зберігаються на пристрої, щоб мав і гість. */
    fun saveTaste(interests: List<String>, times: List<String>, crowd: String) = tasteUseCases.save(interests, times, crowd)
    /** «Не зараз»: питання закриті, ранжуємо лише за часом. */
    fun skipOnboarding() = tasteUseCases.skipOnboarding()
    /** Знову відкриває питання з профілю. */
    fun restartOnboarding() = tasteUseCases.restartOnboarding()
    fun toggleInterest(category: String) = tasteUseCases.toggleInterest(category)

    /**
     * Перемикач у профілі. Дозвіл системи — справа платформи: сюди приходить уже результат,
     * а план нагадувань перераховується зі стану, див. [ReminderSync].
     */
    fun setRemindersEnabled(enabled: Boolean) {
        PoruchLog.i("reminders") { if (enabled) "enabled" else "disabled" }
        reminderStore?.setEnabled(enabled)
        store.update { it.copy(remindersEnabled = enabled) }
    }

    // ---- Безпека

    /** Вік для акаунта, створеного до появи питання. Дозволено раз. */
    fun declareBirthDate(birthDate: String) = safetyUseCases.declareBirthDate(birthDate)
    fun reportEvent(eventId: String, reason: String, details: String? = null) = safetyUseCases.reportEvent(eventId, reason, details)
    fun reportUser(userId: String, reason: String, details: String? = null) = safetyUseCases.reportUser(userId, reason, details)
    /** Блокування взаємне й миттєве: події людини зникають з мапи при наступному читанні. */
    fun blockUser(userId: String) = safetyUseCases.blockUser(userId)
    fun unblockUser(userId: String) = safetyUseCases.unblockUser(userId)

    // ---- Акаунт

    fun signIn(email: String, password: String) = sessionUseCases.signIn(email, password)
    /** [birthDate] — ISO-8601. Платформа лише для дорослих. */
    fun signUp(email: String, password: String, name: String, birthDate: String) = sessionUseCases.signUp(email, password, name, birthDate)
    /** Людина повернулась до форми або закрила екран: крок «перевірте пошту» більше не показуємо. */
    fun dismissConfirmationStep() = sessionUseCases.dismissConfirmationStep()
    fun signOut() = sessionUseCases.signOut()
    /** Видалення акаунту: пароль підтверджує власника, сервер видаляє все каскадом. */
    fun deleteAccount(password: String) = sessionUseCases.deleteAccount(password)
    fun requestPasswordReset(email: String) = sessionUseCases.requestPasswordReset(email)
    fun updatePassword(password: String) = sessionUseCases.updatePassword(password)
    /** Зміна пароля з профілю: поточний пароль доводить, що телефон у руках власника. */
    fun changePassword(current: String, password: String) = sessionUseCases.changePassword(current, password)
    fun handleAuthCallback(url: String) = sessionUseCases.handleAuthCallback(url)

    // ---- Одноразовий стан

    fun clearNotice() { store.update { it.copy(notice = null) } }
    fun clearCompletedEvent() { store.update { it.copy(completedEventId = null) } }
    fun close() { scope.cancel() }
}
