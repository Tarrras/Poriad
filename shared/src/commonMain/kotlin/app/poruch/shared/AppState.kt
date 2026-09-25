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
    /** Людина дозволила продуктову аналітику. Прапорець пристрою, за замовчуванням так. Див. [PoruchAnalytics.enabled]. */
    val analyticsEnabled: Boolean = true,
    val mutating: Boolean = false,
    val notice: AppNotice? = null,
    val completedEventId: String? = null,
    /** Відкритий чат події. Null — екран чату закрито, і опитування зупинено. */
    val chat: ChatState? = null,
    /** Події з непрочитаними повідомленнями, свіжіші першими. Бейджі й секція на головній. */
    val chatUnread: List<ChatUnread> = emptyList(),
    /** Відкрита картка людини. Null — картку закрито. Пише [ProfileUseCases]. */
    val person: PersonState? = null
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

    /**
     * Інші події в цьому ж місці. Для афіші — з `place_events`, коли вони вже приїхали: сервер
     * знає всі події закладу, а індекс — лише ті, що потрапили в завантажену область. Інакше
     * (спільнотна подія, офлайн, відповідь ще їде) — з обох індексів разом: мапу міг звузити
     * фільтр чи пошук до однієї картки, а головна тримає область цілою.
     */
    internal fun othersAt(event: Event): List<EventIndexEntry> {
        val atPlace = detail.placeEvents?.takeIf { it.placeId == event.placeId }
        val others = if (atPlace != null) othersAmong(event, atPlace.events)
        else MapPins.othersAt(event, (map.index + home.index).distinctBy { it.id })
        PoruchLog.d("detail") {
            "others at ${event.id.shortId()}: ${others.size} of " +
                if (atPlace != null) "place=${atPlace.events.size}" else "map=${map.index.size} home=${home.index.size}"
        }
        return others
    }

    /**
     * Події закладу без цієї картки, її дублів і сеансів її прокату. Склеюємо, як видачу мапи:
     * інакше тижневий прокат у кінотеатрі займав би секцію десятком однакових рядків.
     */
    private fun othersAmong(event: Event, events: List<Event>): List<EventIndexEntry> =
        EventSeries.fold(DuplicateEvents.fold(events.map { it.asIndexEntry() }))
            .filter { it.id != event.id && event.id !in it.mergedWith && it.sessions.none { s -> s.id == event.id } }
            .sortedBy { it.startsAt }

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
    val joinRequests: List<Attendee> = emptyList(),
    /** Фото організатора для рядка в «Ідуть»: проєкція події його не несе. Null — нема фото або не завантажилось. */
    val organizerAvatar: String? = null,
    /** Майбутні події закладу відкритої афіші, для «Ще в цьому місці». Null — не питали або збій. */
    val placeEvents: PlaceEvents? = null,
    /**
     * Сама подія ще в дорозі. Поки так, порожній [event] — не «подія недоступна», а спінер.
     * Власний прапорець: `map.loading` про мапу, а не про деталі.
     */
    val loading: Boolean = false
)

/** Події закладу [placeId] з `place_events`, від найближчої. */
data class PlaceEvents(val placeId: String, val events: List<Event>)

/** Списки й факти акаунта. Зникають разом з ним, див. [forAccount]. */
data class LibraryState(
    val myEvents: List<Event> = emptyList(),
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    /** Запити до всіх моїх подій, свіжіші першими. Головна показує, [RequestAlertSync] дзвонить про нові. */
    val pendingRequests: List<JoinRequest> = emptyList(),
    val account: AccountFacts = AccountFacts(),
    /** Свій профіль. Null — ще не завантажено або сервер без міграції профілю. */
    val profile: Profile? = null,
    val blocked: List<Attendee> = emptyList(),
    /** «Мої події» перечитуються. Для спінера екрана «Мої», замість `map.loading`. */
    val loading: Boolean = false
)

/** Відкрита картка людини. [profile] null після завантаження — людина недоступна (блок, приватність). */
data class PersonState(val userId: String, val profile: Profile? = null, val loading: Boolean = true)

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
 * Картки теж: у них членство («Ви йдете»), тож їх перечитує новий акаунт. Індекси — публічні й лишаються.
 */
internal fun AppState.forAccount(uid: String?): AppState = copy(
    session = SessionState(
        userId = uid,
        // Вхід або підтвердження з листа: наступний крок реєстрації вже не потрібен.
        awaitingConfirmation = if (uid != null) null else session.awaitingConfirmation
    ),
    cards = emptyMap(),
    detail = DetailState(),
    library = LibraryState(),
    chatUnread = emptyList(),
    person = null,
    completedEventId = null
).materialized()
