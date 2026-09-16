package app.poruch.shared

import app.poruch.domain.*
import kotlin.time.Clock
import kotlin.time.Instant

/** Реекспорт, щоб платформний модуль залежав лише від `shared`. */
typealias SecureSessionStore = app.poruch.domain.SecureSessionStore

/** Увесь стан застосунку одним незмінним знімком. Екрани беруть свій зріз. */
data class AppState(
    /** Усе в області в порядку показу. Повний список, не вікно: мапа малює його, ранжування йде по ньому. */
    val index: List<EventIndexEntry> = emptyList(),
    /** Завантажені картки за id. Переживають зміну області й фільтра. */
    val cards: Map<String, Event> = emptyMap(),
    /** Скільки подій в області насправді. Дорівнює `index.size`, поки не спрацював запобіжник. */
    val totalFound: Int = 0,
    /** Те з [index], для чого вже є картка, у тому ж порядку. Це показують стрічка, карусель і головна. */
    val events: List<Event> = emptyList(), val selectedEvent: Event? = null,
    val myEvents: List<Event> = emptyList(), val savedIds: List<String> = emptyList(),
    val userId: String? = null, val loading: Boolean = false, val mutating: Boolean = false,
    val notice: AppNotice? = null, val cityName: String = HomeLocation.Kyiv.city,
    val cityLatitude: Double = HomeLocation.Kyiv.latitude,
    val cityLongitude: Double = HomeLocation.Kyiv.longitude, val cities: List<CityResult> = emptyList(),
    val category: String = ALL_CATEGORIES, val dateFilter: String = DateFilter.ANY, val offline: Boolean = false,
    val passwordRecovery: Boolean = false, val completedEventId: String? = null,
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
    val account: AccountFacts = AccountFacts(), val blocked: List<Attendee> = emptyList(),
    /** Хто проситься на відкриту подію. Непорожньо лише для організатора. */
    val joinRequests: List<Attendee> = emptyList(),
    /** Запити до всіх моїх подій, свіжіші першими. Головна показує, [RequestAlertSync] дзвонить про нові. */
    val pendingRequests: List<JoinRequest> = emptyList(),
    val searchText: String = "", val onlyAvailable: Boolean = false,
    /** Область поставлена рукою («Шукати тут»), а не обрана зі списку міст. Головна каже це вголос. */
    val customArea: Boolean = false,
    val attendees: List<Attendee> = emptyList(), val waitlistedIds: List<String> = emptyList(),
    /** Відкритий чат події. Null — екран чату закрито, і опитування зупинено. */
    val chat: ChatState? = null,
    /** Події з непрочитаними повідомленнями, свіжіші першими. Бейджі й секція на головній. */
    val chatUnread: List<ChatUnread> = emptyList()
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
}

/** Ранжує індекс за смаком, а не картки: порядок вирішується над усією областю. */
internal fun AppState.ranked(now: Instant = Clock.System.now()): AppState {
    val ordered = TasteRanking.rank(index, taste, now)
    return copy(index = ordered, suggestedIndex = TasteRanking.matching(ordered, taste)).materialized()
}

/**
 * Перебудовує [events] і [suggested] під поточні [cards]. Стрічка обривається на першій
 * незавантаженій картці, а не пропускає її, інакше після довантаження картки стрибали б.
 */
internal fun AppState.materialized(): AppState {
    val cards = cardsWithSessions()
    val shown = ArrayList<Event>(minOf(index.size, cards.size))
    for (entry in index) shown += cards[entry.id] ?: break
    return copy(cards = cards, events = shown, suggested = suggestedIndex.mapNotNull { cards[it.id] })
}

/**
 * Кладе сеанси прокату з індексу в картки. Саме в [AppState.cards], бо головна, стос і шторка
 * читають картки за id. Картка без змін лишається тим самим об'єктом.
 */
private fun AppState.cardsWithSessions(): Map<String, Event> {
    val runs = HashMap<String, List<EventSession>>()
    for (entry in index) if (entry.isSeries) runs[entry.id] = entry.sessions
    var changed: MutableMap<String, Event>? = null
    for ((id, card) in cards) {
        val sessions = runs[id] ?: emptyList()
        if (card.sessions == sessions) continue
        val target = changed ?: cards.toMutableMap().also { changed = it }
        target[id] = card.copy(sessions = sessions)
    }
    return changed ?: cards
}

/**
 * Чат однієї події, поки його екран відкритий. Живе в [AppState], а не в екрані: обидві
 * платформи слухають один стор, а опитування веде [ChatEngine].
 */
data class ChatState(
    val eventId: String,
    val messages: List<ChatMessage> = emptyList(),
    /** Перше читання ще в дорозі. */
    val loading: Boolean = true,
    val sending: Boolean = false,
    /** Сервер без міграції чату: екран каже про це замість порожнього списку. */
    val available: Boolean = true
)

/** Тримає значення `chatUnread` без події [eventId]: чат відкрито або прочитано. */
internal fun AppState.withoutUnread(eventId: String): AppState =
    if (chatUnread.none { it.eventId == eventId }) this else copy(chatUnread = chatUnread.filterNot { it.eventId == eventId })

/** Значення фільтра «без фільтра». Не категорія, тому окремо. */
const val ALL_CATEGORIES = "all"

/** Фільтри дати. Рядки, бо обидві платформи їх так зберігають. */
object DateFilter {
    const val ANY = "all"
    const val TODAY = "today"
    const val WEEKEND = "weekend"
}

/** Повідомлення для банера: іменоване, без тексту. Текст бере платформа зі своїх ресурсів. */
sealed interface AppNotice {
    /** Щоб банер обрав тон, не знаючи випадку. */
    val isError: Boolean

    data class Failed(val error: AppError) : AppNotice {
        override val isError get() = true
    }

    data class Told(val message: AppMessage) : AppNotice {
        override val isError get() = false
    }
}

/** Усе, що застосунок каже, коли все гаразд. */
enum class AppMessage {
    JOINED_EVENT, JOINED_WAITLIST, SIGNED_IN, ACCOUNT_CREATED, CONFIRM_EMAIL_FIRST,
    EVENT_PUBLISHED, CHANGES_SAVED, PHOTO_ADDED, RECOVERY_SENT, PASSWORD_CHANGED,
    SET_NEW_PASSWORD, EMAIL_CONFIRMED, ZOOM_IN_FOR_MORE,
    REQUEST_SENT, REPORT_SENT, USER_BLOCKED, AGE_CONFIRMED
}

/** Що збірці треба, щоб дістатися бекенду і знати, де відкривати мапу. */
data class AppConfig(
    val supabaseUrl: String,
    val publishableKey: String,
    val home: HomeLocation = HomeLocation.Kyiv
)

class Subscription(private val cancel: () -> Unit) { fun close() = cancel() }
