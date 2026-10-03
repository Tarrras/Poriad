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
    /** Підписки «Стежити». Null — у тестах і превʼю: дії відповідають «сервіс недоступний». */
    follows: Follows? = null,
    auth: AuthRepository,
    geo: GeoSearchRepository,
    eventActions: EventActions,
    accountActions: AccountActions,
    preferences: PreferencesRepository? = null,
    safety: SafetyRepository? = null,
    /** Профіль і картки людей. Null — у тестах і превʼю, дії профілю відповідають «сервіс недоступний». */
    profiles: ProfileRepository? = null,
    tasteStore: TasteStore? = null,
    creationIdentity: CreationIdentityStore? = null,
    timeZones: TimeZoneLocator? = null,
    addresses: AddressSearch? = null,
    reminderStore: ReminderPreferenceStore? = null,
    /** Останнє обране місто. Null — кожен запуск з [AppConfig.home]. */
    cityStore: CityStore? = null,
    /** Системний планувальник нагадувань. Null у тестах і превʼю: план рахується, але нікуди не йде. */
    reminders: ReminderScheduler? = null,
    /** Сповіщення про нові запити на участь: сховище «бачених» і платформний показ. Обидва або нічого. */
    seenRequests: SeenRequestStore? = null,
    requestNotifier: RequestNotifier? = null,
    /** Сповіщення про нові повідомлення в чатах: окремий список «бачених» і показ. Обидва або нічого. */
    seenMessages: SeenRequestStore? = null,
    chatNotifier: ChatNotifier? = null,
    /** Згода на аналітику на пристрої. Null — збір увімкнено й не запам'ятовується. */
    analyticsStore: AnalyticsPreferenceStore? = null,
    /** Пуш-токен, який не вдалося зняти при виході: повторюємо на старті й при поверненні. */
    pendingPush: PendingUnregisterStore? = null,
    config: AppConfig = AppConfig("", ""),
    /** Стан живе на головному потоці: звідси читають і Compose, і SwiftUI. */
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
    /** Де рахувати важке. Порожньо за замовчуванням, щоб тести під `runTest` нічого не знали; [AppGraph] підставляє диспетчер. */
    compute: CoroutineContext = EmptyCoroutineContext
) {
    /** Звідки стартує пошук: останнє обране місто, інакше місто збірки. */
    private val startCity = cityStore?.read()?.let { HomeLocation(it.name, it.latitude, it.longitude) } ?: config.home

    // Відповіді читаємо синхронно: від них залежить, чи перший кадр — онбординг чи застосунок.
    private val store = AppStore(
        AppState(
            session = SessionState(userId = auth.session.value?.userId), taste = tasteStore?.read() ?: Taste(),
            remindersEnabled = reminderStore?.enabled() ?: false,
            digestEnabled = reminderStore?.digestEnabled() ?: true,
            analyticsEnabled = analyticsStore?.enabled() ?: true,
            city = CityState(startCity.city, startCity.latitude, startCity.longitude)
        ),
        scope
    )
    val state: StateFlow<AppState> get() = store.state

    private val discovery = DiscoveryEngine(events, geo, store, scope, startCity, compute, cityStore)
    private val library = UserLibrary(
        events,
        saved,
        participation,
        requests,
        chat,
        auth,
        preferences,
        safety,
        profiles,
        follows,
        tasteStore,
        store,
        scope
    )
    private val chatEngine = ChatEngine(chat, store, scope)
    private val reloader = Reloader(discovery, library)
    private val pushSync = PushSync(push, seenRequests, seenMessages, store, pendingPush)
    private val places = PlaceLookup(addresses, timeZones, scope)
    private val followUseCases = FollowUseCases(follows, events, store, library, discovery)
    private val eventUseCases = EventUseCases(
        events,
        saved,
        authoring,
        participation,
        requests,
        auth,
        eventActions,
        creationIdentity,
        store,
        library,
        reloader,
        followUseCases
    )
    private val identity =
        IdentitySync(auth, store, discovery, library, chatEngine, pushSync, eventUseCases)
    private val sessionUseCases =
        SessionUseCases(auth, accountActions, store, identity, pushSync)
    private val safetyUseCases = SafetyUseCases(safety, store, library, reloader)
    private val profileUseCases = ProfileUseCases(profiles, store, scope)
    private val tasteUseCases = TasteUseCases(tasteStore, preferences, reminderStore, store, analyticsStore)

    init {
        // Перемикач збору — до першої події: `first_open` не має піти, якщо людина відмовилась.
        PoruchAnalytics.enabled = state.value.analyticsEnabled
        discovery.onQueryChanged = library::dismiss
        identity.start()
        pushSync.retryPending()
        refresh()
        if (state.value.signedIn) loadMyEvents()
        if (reminders != null) ReminderSync(state, reminders, scope).start()
        if (requestNotifier != null && seenRequests != null) RequestAlertSync(
            state,
            seenRequests,
            requestNotifier,
            scope
        ).start()
        if (chatNotifier != null && seenMessages != null) ChatAlertSync(
            state,
            seenMessages,
            chatNotifier,
            scope
        ).start()
    }

    fun observe(onChange: (AppState) -> Unit): Subscription {
        val job = scope.launch { state.collect { onChange(it) } }
        return Subscription { job.cancel() }
    }

    // ---- Пуші

    // Обидва входи платформа кличе з будь-якого потоку (FCM — з фонового), а стан і рушії живуть
    // на головному: тіло завжди переходить у [scope].

    /** Платформа отримала або оновила токен. Реєструється під кожним акаунтом, з яким входять. */
    fun pushTokenChanged(token: String, platform: PushPlatform) {
        scope.launch { pushSync.tokenChanged(token, platform) }
    }

    /** Пуш прийшов на цей пристрій: перечитуємо стан, щоб бейджі й списки відповідали. */
    fun pushReceived(kind: String, key: String) {
        scope.launch { pushSync.received(kind, key); resume() }
    }

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
    fun sessionsOf(event: Event): List<EventSession> = state.value.sessionsOf(event)

    /** Інші події на тій самій точці, для секції «Ще в цьому місці». Див. [AppState.othersAt]. */
    fun othersAt(event: Event): List<EventIndexEntry> = state.value.othersAt(event)

    /** Id картки, під якою подія стоїть у видачі. Див. [AppState.cardIdOf]. */
    fun cardIdOf(id: String): String = state.value.cardIdOf(id)

    fun searchArea(south: Double, west: Double, north: Double, east: Double) =
        discovery.searchArea(south, west, north, east)

    /** Пошук мапи. */
    fun setSearchText(query: String) = discovery.setSearchText(query)
    /** Тап по закладу в пошуку мапи чи головної: мапа переходить до нього й відкриває його стос. Див. [PlaceFocus]. */
    fun focusPlace(place: Place) = discovery.focusPlace(place)
    /** Платформа відкрила стос з [MapFeed.placeFocus]. */
    fun placeFocusShown() = discovery.placeFocusShown()
    /** Пошук головної: окремий від мапи, у тій самій області. */
    fun setHomeSearchText(query: String) = discovery.setHomeSearchText(query)
    /** Пошук головної: усі міста чи лише обране; категорія й дата звужують лише знайдене. */
    fun setHomeSearchEverywhere(everywhere: Boolean) = discovery.setHomeSearchEverywhere(everywhere)
    /** «Скасувати» в режимі пошуку: текст і фільтри скидаються. */
    fun cancelHomeSearch() = discovery.cancelHomeSearch()
    fun setHomeSearchCategory(category: EventCategory?) = discovery.setHomeSearchCategory(category)
    fun setHomeSearchDate(filter: DateFilter) = discovery.setHomeSearchDate(filter)
    fun setOnlyAvailable(available: Boolean) = discovery.setOnlyAvailable(available)

    /** «Усі N» біля «Від людей»: мапа лише зі зустрічами від людей з вільним місцем, без інших фільтрів. */
    fun showPeopleOnMap() = discovery.showOnMap(available = true)

    /** «Усі N» біля «У місті»: мапа з усім містом, без фільтрів і власної області. */
    fun showEverythingOnMap() = discovery.showOnMap(available = false)
    fun setCategory(category: EventCategory?) = discovery.setCategory(category)
    fun setDateFilter(filter: DateFilter) = discovery.setDateFilter(filter)
    fun searchCity(query: String) = discovery.searchCity(query)
    /** Місто, обране руками: запам'ятовується і має перевагу над геолокацією на старті. */
    fun selectCity(city: CityResult) = discovery.selectCity(city, manual = true)
    /** Геолокація на старті застосунку. Обране руками місто не перебиває. */
    fun locatedCity(city: CityResult) = discovery.locatedCity(city)
    /** «Поруч зі мною» на мапі: людина сама попросила геолокацію, тож далі місто знову йде за нею. */
    fun followLocation(city: CityResult) = discovery.selectCity(city, manual = false)

    /** Підказки адрес для редактора. Порожній список — просто нічого не знайшли. */
    fun searchAddress(
        query: String,
        latitude: Double,
        longitude: Double,
        onFound: (List<PlaceResult>) -> Unit
    ) =
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

    /** Те саме з підписом, звідки людина прийшла (`home_hero`, `home_poster`, `home_your`, `home_search`): `event_view` каже, що з головної веде до подій. */
    fun selectEvent(id: String, from: String) = library.select(id, from = from)

    /**
     * Тап по «Створити» (`fab`, `home_top`, `home_footer`, `map`, `mine`). `guest` — людина без акаунта: її далі чекає
     * реєстрація, тож воронку «тапнув → зареєструвався → опублікував» видно лише за `guest=true`, а не змішаною з тими,
     * хто вже увійшов. Публікація рахується окремо: `event_create`.
     */
    fun createStarted(from: String) = PoruchAnalytics.track("create_start", "from" to from, "guest" to !state.value.signedIn)

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

    /** Повернення на передній план: перечитує «мої» і відкриту подію, мапу — якщо видача не свіжа. */
    fun resume() {
        reloader.resumed(); pushSync.retryPending()
    }

    // ---- Оновлення жестом

    /**
     * Потяг головної вниз: перечитує все, як [resume], але й свіжу видачу, і повертається лише коли відповіді
     * приїхали, щоб індикатор знав, коли сховатись. Збій не кидає: він уже в [AppState.notice].
     */
    suspend fun reloadAll() {
        reloader.all(); reloader.awaitAll()
    }

    /** Потяг «моїх подій» вниз. Див. [reloadAll]. */
    suspend fun reloadMyEvents() {
        loadMyEvents(); library.awaitList()
    }

    /** Потяг деталей вниз: місця, членство й запити перечитуються, як при відкритті. Див. [reloadAll]. */
    suspend fun reloadEvent(id: String) {
        openEvent(id); library.awaitDetail()
    }

    // ---- Чат події

    /** Екран чату відкрито: тягнемо хвіст і перечитуємо, поки не закриють. */
    fun openChat(eventId: String) = chatEngine.open(eventId)
    fun closeChat() = chatEngine.close()
    fun sendMessage(text: String) = chatEngine.send(text)

    /** Текст, що не пішов (див. [ChatState.failedDraft]), для поля вводу. Віддає раз. */
    fun consumeFailedDraft(): String? = chatEngine.consumeFailedDraft()
    fun deleteMessage(messageId: String) = chatEngine.delete(messageId)
    fun reportMessage(messageId: String, reason: ReportReason, details: String? = null) =
        safetyUseCases.reportMessage(messageId, reason, details)

    // ---- Події

    fun joinEvent(id: String) = eventUseCases.join(id)
    fun joinWaitlist(id: String) = eventUseCases.joinWaitlist(id)
    fun leaveWaitlist(id: String) = eventUseCases.leaveWaitlist(id)
    fun leaveEvent(id: String) = eventUseCases.leave(id)
    fun cancelEvent(id: String) = eventUseCases.cancel(id)
    /** [followOrganizer]: що показував перемикач «Стежити за організатором» у шторці; null — перемикача не було. */
    fun rateEvent(
        id: String, score: Int, comment: String? = null, tags: List<RatingTag> = emptyList(), followOrganizer: Boolean? = null
    ) = eventUseCases.rate(id, score, comment, tags, followOrganizer)

    /** Закладка спрацьовує одразу, запит іде окремо; при збої повертається як було. */
    fun toggleSaved(id: String) = eventUseCases.toggleSaved(id)
    fun createEvent(draft: EventDraft) = eventUseCases.create(draft)

    /** «Шукаю компанію» на відкриту афішу. [meetAt] — з [CompanionRules.meetTimes], ISO-8601. */
    fun createCompanion(parentId: String, meetAt: String, note: String?, capacity: Int) =
        eventUseCases.createCompanion(parentId, meetAt, note, capacity)
    fun updateEvent(id: String, draft: EventDraft) = eventUseCases.update(id, draft)
    fun uploadEventImage(eventId: String, bytes: ByteArray, contentType: String) =
        eventUseCases.uploadImage(eventId, bytes, contentType)

    fun approveMember(eventId: String, userId: String) =
        eventUseCases.approveMember(eventId, userId)

    fun declineMember(eventId: String, userId: String) =
        eventUseCases.declineMember(eventId, userId)

    // ---- Підписки

    /**
     * «Стежити» / «Ви стежите» на закладі чи організаторі. Кнопка перемикається одразу ([AppState.isFollowing]),
     * запит іде окремо. [name] — для списку, поки сервер не віддав повних даних. Гостя веде на вхід платформа.
     */
    fun setFollowing(kind: FollowKind, targetId: String, name: String, following: Boolean) =
        followUseCases.set(kind, targetId, name, following)

    /** Тап по пушу про кілька подій закладу: мапа переходить до нього й відкриває його стос. */
    fun openPlace(placeId: String) = followUseCases.openPlace(placeId)

    /**
     * Екран артиста в [AppState.artist]. З пошуку чи рядка підписки — з [name] і [kind]; з пуша лише за id: ім'я
     * доїде з карток подій. Платформа показує екран, поки стан не null, і кличе [closeArtist], коли його закрито.
     */
    fun openArtist(artistId: String, name: String? = null, kind: ArtistKind? = null) = followUseCases.openArtist(artistId, name, kind)
    fun closeArtist() = followUseCases.closeArtist()

    /**
     * Сповіщення відкрито тапом. [reason] — що воно було: chat, request, joined, moved, cancelled, place,
     * artist, organizer, reminder. Єдиний спосіб дізнатись, який тригер повертає людей, а який лише дратує.
     */
    fun pushOpened(reason: String) = PoruchAnalytics.track("push_open", "reason" to reason)

    // ---- Смак і нагадування

    /** Відповіді онбордингу. Зберігаються на пристрої, щоб мав і гість. */
    fun saveTaste(interests: List<EventCategory>, times: List<TimeSlot>, crowd: Crowd) =
        tasteUseCases.save(interests, times, crowd)

    /** «Не зараз»: питання закриті, ранжуємо лише за часом. */
    fun skipOnboarding() = tasteUseCases.skipOnboarding()

    /** Знову відкриває питання з профілю. */
    fun restartOnboarding() = tasteUseCases.restartOnboarding()
    fun toggleInterest(category: EventCategory) = tasteUseCases.toggleInterest(category)

    /**
     * Перемикач у профілі. Дозвіл системи — справа платформи: сюди приходить уже результат,
     * а план нагадувань перераховується зі стану, див. [ReminderSync].
     */
    fun setRemindersEnabled(enabled: Boolean) = tasteUseCases.setRemindersEnabled(enabled)

    /** Перемикач дайджесту вихідних. Як і нагадування: дозвіл уже спитала платформа. */
    fun setDigestEnabled(enabled: Boolean) = tasteUseCases.setDigestEnabled(enabled)

    /**
     * Відповідь на мʼяке питання про дайджест. Дозвіл дано — вмикаємо й нагадування про свої
     * події: людина погодилась на сповіщення, а інакше Android більше б про них не спитав.
     */
    fun digestPromptAnswered(granted: Boolean) {
        PoruchAnalytics.track("digest_prompt", "granted" to granted)
        if (!granted) return
        tasteUseCases.setDigestEnabled(true)
        tasteUseCases.setRemindersEnabled(true)
    }

    /** Тап по дайджесту: єдиний спосіб дізнатися, чи він повертає людей. */
    fun digestOpened() = PoruchAnalytics.track("digest_open")

    /** Відкрито системне «Поділитися» з посиланням на подію: чи працює петля запрошень. */
    fun eventShared() = PoruchAnalytics.track("share", "kind" to "event")

    /** Подію відкрито з посилання `poriad.app/e/…` — друга половина тієї ж петлі. */
    fun eventLinkOpened() = PoruchAnalytics.track("link_open", "kind" to "event")

    /**
     * Перемикач аналітики в профілі. Вимкнено — події не йдуть у сінк, а платформа отримує
     * [PoruchAnalytics.collection] з false (Firebase `setAnalyticsCollectionEnabled`).
     */
    fun setAnalyticsEnabled(enabled: Boolean) = tasteUseCases.setAnalyticsEnabled(enabled)

    // ---- Безпека

    /** Вік для акаунта, створеного до появи питання. Дозволено раз. */
    fun declareBirthDate(birthDate: String) = safetyUseCases.declareBirthDate(birthDate)
    fun reportEvent(eventId: String, reason: ReportReason, details: String? = null) =
        safetyUseCases.reportEvent(eventId, reason, details)

    fun reportUser(userId: String, reason: ReportReason, details: String? = null) =
        safetyUseCases.reportUser(userId, reason, details)

    /** Блокування взаємне й миттєве: події людини зникають з мапи при наступному читанні. */
    fun blockUser(userId: String) = safetyUseCases.blockUser(userId)
    fun unblockUser(userId: String) = safetyUseCases.unblockUser(userId)

    // ---- Профіль

    /** Імʼя й «Про себе». Перевіряє стоп-словник сервера: відмова — [AppError.ObjectionableContent]. */
    fun saveProfile(name: String, bio: String?) = profileUseCases.save(name, bio)

    /** Нове фото профілю: JPEG/PNG/WebP до 5 MiB, платформа вже перекодувала його без EXIF. */
    fun setAvatar(bytes: ByteArray, contentType: String) = profileUseCases.setAvatar(bytes, contentType)
    fun removeAvatar() = profileUseCases.removeAvatar()

    /** Картка людини в [AppState.person]. Видимість вирішує сервер. */
    fun openPerson(userId: String) = profileUseCases.open(userId)
    fun closePerson() = profileUseCases.close()

    // ---- Акаунт

    fun signIn(email: String, password: String) = sessionUseCases.signIn(email, password)

    /** [birthDate] — ISO-8601. Платформа лише для дорослих. */
    fun signUp(email: String, password: String, name: String, birthDate: String) =
        sessionUseCases.signUp(email, password, name, birthDate)

    /** Людина повернулась до форми або закрила екран: крок «перевірте пошту» більше не показуємо. */
    fun dismissConfirmationStep() = sessionUseCases.dismissConfirmationStep()
    fun signOut() = sessionUseCases.signOut()

    /** Видалення акаунту: пароль підтверджує власника, сервер видаляє все каскадом. Збій мережі лишає в акаунті. */
    fun deleteAccount(password: String) = sessionUseCases.deleteAccount(password)
    fun requestPasswordReset(email: String) = sessionUseCases.requestPasswordReset(email)
    fun updatePassword(password: String) = sessionUseCases.updatePassword(password)

    /** Зміна пароля з профілю: поточний пароль доводить, що телефон у руках власника. */
    fun changePassword(current: String, password: String) =
        sessionUseCases.changePassword(current, password)

    fun handleAuthCallback(url: String) = sessionUseCases.handleAuthCallback(url)

    // ---- Одноразовий стан

    fun clearNotice() {
        store.update { it.copy(notice = null) }
    }

    /** «Поділитися» для щойно створеного супутника вже відкрито. */
    fun clearCreatedCompanion() {
        store.update { it.copy(createdCompanion = null) }
    }

    fun clearCompletedEvent() {
        store.update { it.copy(completedEventId = null) }
    }

    fun close() {
        scope.cancel()
    }
}
