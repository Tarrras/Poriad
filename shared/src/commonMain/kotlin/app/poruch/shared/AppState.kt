package app.poruch.shared

import app.poruch.domain.*

/**
 * Увесь стан застосунку одним незмінним знімком. Поділений на зрізи за власником: кожен зріз
 * пише один рушій, а екрани беруть свій зріз.
 */
data class AppState(
    /** Мапа: видача з її фільтрами й пошуком. Пише [DiscoveryEngine]. */
    val map: MapFeed = MapFeed(),
    /** Головна: та сама область, але без фільтрів мапи і зі своїм пошуком. Пише [DiscoveryEngine]. */
    val home: HomeFeed = HomeFeed(),
    /** Обране місто або область «Шукати тут». Пише [DiscoveryEngine]. */
    val city: CityState = CityState(),
    /** Завантажені картки за id, спільні для мапи й головної. Переживають зміну області й фільтра. */
    val cards: Map<String, Event> = emptyMap(),
    /** Лічильник перебудов [cards], [MapFeed.events] і стрічки головної. Змінюється лише в [materialized]. */
    val feedVersion: Int = 0,
    /** Відкрита або підсвічена подія. Пише [UserLibrary]. */
    val detail: DetailState = DetailState(),
    /** Усе, що належить акаунту і зникає з ним. Пише [UserLibrary]. */
    val library: LibraryState = LibraryState(),
    /** Хто увійшов і на якому кроці входу. Пишуть [IdentitySync], [SessionUseCases], [PushSync]. */
    val session: SessionState = SessionState(),
    val taste: Taste = Taste(),
    /** Людина попросила нагадувати про свої події. Прапорець пристрою, дозвіл системи перевіряє платформа. */
    val remindersEnabled: Boolean = false,
    val mutating: Boolean = false,
    val notice: AppNotice? = null,
    val completedEventId: String? = null,
    /** Відкритий чат події. Null — екран чату закрито, і опитування зупинено. */
    val chat: ChatState? = null,
    /** Події з непрочитаними повідомленнями, свіжіші першими. Бейджі й секція на головній. */
    val chatUnread: List<ChatUnread> = emptyList()
) {
    /** Скільки чатів чекають: бейдж на вкладці. Не сума повідомлень: три чати — три справи. */
    val unreadChats get() = chatUnread.size
    val signedIn get() = session.userId != null
    fun isSaved(id: String) = id in library.savedIds
    fun isWaitlisted(id: String) = id in library.waitlistedIds
    fun organizes(event: Event) = session.userId != null && event.organizerId == session.userId

    /** Своя подія: організую або йду. Це і є «плани» на головній і в нагадуваннях. */
    fun concerns(event: Event) = event.gathering?.joined == true || organizes(event)

    /** Обрані категорії. Живуть у [taste], щоб були і в гостя. */
    val interests: List<String> get() = taste.interests

    /** Поки на питання онбордингу не відповіли і не відмахнулись. */
    val needsOnboarding get() = !taste.answered

    /** Акаунт без віку має його вказати, перш ніж кудись приєднатись. Питає застосунок, відмовляє сервер. */
    val needsAgeDeclaration get() = signedIn && !library.account.ageDeclared
    fun hasBlocked(userId: String) = library.blocked.any { it.userId == userId }

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
        EventSeries.sessionsOf(event, map.index).ifEmpty { EventSeries.sessionsOf(event, home.index) }

    private fun runOf(id: String) = map.index.firstOrNull { run -> run.sessions.any { it.id == id } }
        ?: home.index.firstOrNull { run -> run.sessions.any { it.id == id } }
}

/** Відкрита подія з тим, що бачить лише вона. Порожньо — нічого не відкрито. */
data class DetailState(
    val event: Event? = null,
    val attendees: List<Attendee> = emptyList(),
    /** Оцінки відкритої завершеної події: організаторові всі, учасникові — своя. */
    val ratings: List<EventRating> = emptyList(),
    /** Хто проситься на відкриту подію. Непорожньо лише для організатора. */
    val joinRequests: List<Attendee> = emptyList()
)

/** Списки й факти акаунта. Зникають разом з ним, див. [forAccount]. */
data class LibraryState(
    val myEvents: List<Event> = emptyList(),
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    /** Запити до всіх моїх подій, свіжіші першими. Головна показує, [RequestAlertSync] дзвонить про нові. */
    val pendingRequests: List<JoinRequest> = emptyList(),
    val account: AccountFacts = AccountFacts(),
    val blocked: List<Attendee> = emptyList()
)

data class SessionState(
    val userId: String? = null,
    /** Людина прийшла з листа відновлення: наступний крок — новий пароль. */
    val passwordRecovery: Boolean = false,
    /**
     * Пошта, на яку після реєстрації пішов лист із підтвердженням. Поки непорожньо, екран входу
     * показує наступний крок замість форми. Зникає з входом або коли людина повертається до форми.
     */
    val awaitingConfirmation: String? = null,
    /**
     * Пристрій зареєстровано для пушів під цим акаунтом. Тоді про нове дзвонить сервер, а
     * локальні сповіщення при перечитуванні мовчать, щоб не дублювати.
     */
    val pushRegistered: Boolean = false
)

/**
 * Стан під акаунтом [uid]: усе приватне попереднього зникає. Єдиний перелік того, що належить
 * акаунту, для входу, виходу й зміни акаунта. Відповіді онбордингу й місто належать телефону і лишаються.
 */
internal fun AppState.forAccount(uid: String?): AppState = copy(
    session = SessionState(
        userId = uid,
        // Вхід або підтвердження з листа: наступний крок реєстрації вже не потрібен.
        awaitingConfirmation = if (uid != null) null else session.awaitingConfirmation
    ),
    map = map.copy(events = emptyList()),
    detail = DetailState(),
    library = LibraryState(),
    chatUnread = emptyList(),
    completedEventId = null
)
