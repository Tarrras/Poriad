package app.poruch.shared

import app.poruch.domain.*

/** Увесь стан застосунку одним незмінним знімком. Екрани беруть свій зріз. */
data class AppState(
    /** Видача мапи (з її фільтрами) в порядку показу. Повний список, не вікно: мапа малює його, ранжування йде по ньому. */
    val index: List<EventIndexEntry> = emptyList(),
    /** Завантажені картки за id. Переживають зміну області й фільтра. */
    val cards: Map<String, Event> = emptyMap(),
    /** Скільки подій в області насправді. Дорівнює `index.size`, поки не спрацював запобіжник. */
    val totalFound: Int = 0,
    /** Те з [index], для чого вже є картка, у тому ж порядку. Це показують стрічка, карусель і головна. */
    val events: List<Event> = emptyList(),
    val selectedEvent: Event? = null,
    val myEvents: List<Event> = emptyList(),
    val savedIds: List<String> = emptyList(),
    val userId: String? = null,
    val loading: Boolean = false,
    val mutating: Boolean = false,
    val notice: AppNotice? = null,
    val cityName: String = HomeLocation.Kyiv.city,
    val cityLatitude: Double = HomeLocation.Kyiv.latitude,
    val cityLongitude: Double = HomeLocation.Kyiv.longitude,
    val cities: List<CityResult> = emptyList(),
    val category: String = ALL_CATEGORIES,
    val dateFilter: String = DateFilter.ANY,
    val offline: Boolean = false,
    val passwordRecovery: Boolean = false,
    val completedEventId: String? = null,
    /**
     * Пошта, на яку після реєстрації пішов лист із підтвердженням. Поки непорожньо, екран входу
     * показує наступний крок замість форми. Зникає з входом або коли людина повертається до форми.
     */
    val awaitingConfirmation: String? = null,
    val taste: Taste = Taste(),
    /** Людина попросила нагадувати про свої події. Прапорець пристрою, дозвіл системи перевіряє платформа. */
    val remindersEnabled: Boolean = false,
    /**
     * Події, що відповідають відповідям людини: лише вони йдуть у «Для вас». Зберігається, а не
     * рахується при читанні: як `get()` це коштувало 34 мс на складання головної на iOS.
     */
    val suggested: List<Event> = emptyList(),
    /** Ті з [index], що відповідають смаку. Картки можуть ще не приїхати. */
    val suggestedIndex: List<EventIndexEntry> = emptyList(),
    val account: AccountFacts = AccountFacts(),
    val blocked: List<Attendee> = emptyList(),
    /** Хто проситься на відкриту подію. Непорожньо лише для організатора. */
    val joinRequests: List<Attendee> = emptyList(),
    /** Запити до всіх моїх подій, свіжіші першими. Головна показує, [RequestAlertSync] дзвонить про нові. */
    val pendingRequests: List<JoinRequest> = emptyList(),
    /**
     * Лічильник змін складу чи порядку [index]. Платформи порівнюють число, а не обходять
     * тисячі записів через міст на кожну емісію: так iOS знає, коли перебудувати піни.
     */
    val indexVersion: Int = 0,
    /** Лічильник перебудов [cards], [events] і стрічки головної. Змінюється лише в [materialized]. */
    val feedVersion: Int = 0,
    /** Пошук мапи. У головної свій: [HomeFeed.searchText]. */
    val searchText: String = "",
    val onlyAvailable: Boolean = false,
    /** Головна: та сама область, але без фільтрів мапи і зі своїм пошуком. */
    val home: HomeFeed = HomeFeed(),
    /** Область поставлена рукою («Шукати тут»), а не обрана зі списку міст. Головна каже це вголос. */
    val customArea: Boolean = false,
    val attendees: List<Attendee> = emptyList(),
    /** Оцінки відкритої завершеної події: організаторові всі, учасникові — своя. */
    val ratings: List<EventRating> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    /** Відкритий чат події. Null — екран чату закрито, і опитування зупинено. */
    val chat: ChatState? = null,
    /** Події з непрочитаними повідомленнями, свіжіші першими. Бейджі й секція на головній. */
    val chatUnread: List<ChatUnread> = emptyList(),
    /**
     * Пристрій зареєстровано для пушів під цим акаунтом. Тоді про нове дзвонить сервер, а
     * локальні сповіщення при перечитуванні мовчать, щоб не дублювати.
     */
    val pushRegistered: Boolean = false
) {
    /** Скільки чатів чекають: бейдж на вкладці. Не сума повідомлень: три чати — три справи. */
    val unreadChats get() = chatUnread.size
    val signedIn get() = userId != null
    fun isSaved(id: String) = id in savedIds
    fun isWaitlisted(id: String) = id in waitlistedIds
    fun organizes(event: Event) = userId != null && event.organizerId == userId

    /** Своя подія: організую або йду. Це і є «плани» на головній і в нагадуваннях. */
    fun concerns(event: Event) = event.gathering?.joined == true || organizes(event)

    /** Обрані категорії. Живуть у [taste], щоб були і в гостя. */
    val interests: List<String> get() = taste.interests

    /** Поки на питання онбордингу не відповіли і не відмахнулись. */
    val needsOnboarding get() = !taste.answered

    /** Акаунт без віку має його вказати, перш ніж кудись приєднатись. Питає застосунок, відмовляє сервер. */
    val needsAgeDeclaration get() = signedIn && !account.ageDeclared
    fun hasBlocked(userId: String) = blocked.any { it.userId == userId }

    /**
     * Сеанси прокату, до якого належить подія, за часом. Без запиту: дати вже в індексі, але
     * лише в межах поточної видачі (під «Сьогодні» — сьогоднішні). Приймає id будь-якого сеансу.
     */
    fun sessionsOf(id: String): List<EventSession> = runOf(id)?.sessions ?: emptyList()

    /**
     * Id картки, під якою подія стоїть у видачі: для сеансу прокату — представник, для решти — вона
     * сама. Потрібно мапі, відкритій з другої дати прокату: окремого піна для неї нема.
     */
    fun cardIdOf(id: String): String = runOf(id)?.id ?: id

    /** Сеанси прокату з видачі мапи, а якщо там його нема (відсік фільтр) — з головної. */
    internal fun sessionsOf(event: Event): List<EventSession> =
        EventSeries.sessionsOf(event, index).ifEmpty { EventSeries.sessionsOf(event, home.index) }

    private fun runOf(id: String) = index.firstOrNull { run -> run.sessions.any { it.id == id } }
        ?: home.index.firstOrNull { run -> run.sessions.any { it.id == id } }
}

/**
 * Стан під акаунтом [uid]: усе приватне попереднього зникає. Єдиний перелік того, що належить
 * акаунту, для входу, виходу й зміни акаунта. Відповіді онбордингу й місто належать телефону і лишаються.
 */
internal fun AppState.forAccount(uid: String?): AppState = copy(
    userId = uid,
    events = emptyList(),
    myEvents = emptyList(), savedIds = emptyList(), waitlistedIds = emptyList(),
    selectedEvent = null, attendees = emptyList(), ratings = emptyList(), joinRequests = emptyList(),
    pendingRequests = emptyList(), chatUnread = emptyList(), account = AccountFacts(), blocked = emptyList(),
    pushRegistered = false,
    passwordRecovery = false,
    completedEventId = null,
    // Вхід або підтвердження з листа: наступний крок реєстрації вже не потрібен.
    awaitingConfirmation = if (uid != null) null else awaitingConfirmation
)
