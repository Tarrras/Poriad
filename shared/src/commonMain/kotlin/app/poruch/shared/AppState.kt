package app.poruch.shared

import app.poruch.domain.*
import kotlin.time.Clock
import kotlin.time.Instant

/** Re-exported so a platform module depends on `shared` alone, not on `core:domain` as well. */
typealias SecureSessionStore = app.poruch.domain.SecureSessionStore

/** Everything the app knows, in one immutable snapshot. Screens select the slice they need. */
data class AppState(
    /**
     * Усе, що є в цій області, у порядку показу. Повний список — не вікно й не сторінка.
     *
     * Мапа малює саме його, тож на ній видно всі 432 київські події, а не перші 300 за датою.
     * Ранжування за смаком теж іде по ньому: доти, доки воно працювало над обрізаною видачею,
     * подія, що ідеально відповідала відповідям людини, не піднімалась нагору, якщо стояла
     * 340-ю за часом — її просто не існувало.
     */
    val index: List<EventIndexEntry> = emptyList(),
    /** Картки, які встигли завантажитись, за ідентифікатором. Переживають зміну області й фільтра. */
    val cards: Map<String, Event> = emptyMap(),
    /** Скільки подій в області насправді. Дорівнює `index.size`, доки не спрацював запобіжник. */
    val totalFound: Int = 0,
    /**
     * Те з [index], для чого вже є картка, у тому самому порядку. Саме це показують стрічка,
     * карусель і головна; мапа їх не чекає.
     */
    val events: List<Event> = emptyList(), val selectedEvent: Event? = null,
    val myEvents: List<Event> = emptyList(), val savedIds: List<String> = emptyList(),
    val userId: String? = null, val loading: Boolean = false, val mutating: Boolean = false,
    val notice: AppNotice? = null, val cityName: String = HomeLocation.Kyiv.city,
    val cityLatitude: Double = HomeLocation.Kyiv.latitude,
    val cityLongitude: Double = HomeLocation.Kyiv.longitude, val cities: List<CityResult> = emptyList(),
    val category: String = ALL_CATEGORIES, val dateFilter: String = DateFilter.ANY, val offline: Boolean = false,
    val passwordRecovery: Boolean = false, val completedEventId: String? = null,
    val taste: Taste = Taste(),
    /**
     * The events that answer something the person actually said. A section titled «для вас» may
     * only show these — a suggestion that matched nothing is the same list under a new heading.
     *
     * Зберігається, а не рахується при читанні: доки це був `get()`, кожне звертання наново
     * фільтрувало всі знайдені події, піднімаючи для кожної часовий пояс. На iOS одне складання
     * головної коштувало через це 34 мс — більше за два кадри.
     */
    val suggested: List<Event> = emptyList(),
    /** Ті з [index], що відповідають смаку. Картки для них можуть ще не приїхати. */
    val suggestedIndex: List<EventIndexEntry> = emptyList(),
    val account: AccountFacts = AccountFacts(), val blocked: List<Attendee> = emptyList(),
    /** People asking to come to the open event. Non-empty only for its organizer. */
    val joinRequests: List<Attendee> = emptyList(),
    val searchText: String = "", val onlyAvailable: Boolean = false,
    /**
     * Чи область пошуку — уже не саме місто.
     *
     * Після «Шукати тут» слово «поруч» на головній означає не місто, а ту рамку, яку людина
     * лишила на мапі. Екрани мають право сказати це вголос, а для цього мусять розрізняти
     * два випадки: місто, обране у списку міст, і рамку, обрану рукою.
     */
    val customArea: Boolean = false,
    val attendees: List<Attendee> = emptyList(), val waitlistedIds: List<String> = emptyList()
) {
    val signedIn get() = userId != null
    fun isSaved(id: String) = id in savedIds
    fun isWaitlisted(id: String) = id in waitlistedIds
    fun organizes(event: Event) = userId != null && event.organizerId == userId

    /** The categories a person chose. They live in [taste] so that a guest can have them too. */
    val interests: List<String> get() = taste.interests

    /** True until the opening questions have been answered or waved away. */
    val needsOnboarding get() = !taste.answered

    /**
     * An account made before the app asked for an age has to state one before it can join anything.
     * Asking is the app's job; refusing is the server's.
     */
    val needsAgeDeclaration get() = signedIn && !account.ageDeclared
    fun hasBlocked(userId: String) = blocked.any { it.userId == userId }
}

/**
 * Перекладає знайдене в той порядок, про який просили відповіді онбордингу.
 *
 * Ранжується **індекс**, а не картки: порядок має вирішуватись над усім, що є в області, інакше
 * він залежав би від того, скільки карток встигло завантажитись. [events] після цього — той самий
 * порядок, але лише там, де картка вже є.
 */
internal fun AppState.ranked(now: Instant = Clock.System.now()): AppState {
    val ordered = TasteRanking.rank(index, taste, now)
    return copy(index = ordered, suggestedIndex = TasteRanking.matching(ordered, taste)).materialized()
}

/**
 * Перебудовує [events] і [suggested] під поточні [cards].
 *
 * Стрічка обривається на першій нематеріалізованій події, а не пропускає її: інакше після
 * довантаження вікна картки переставлялися б у людини під пальцем.
 */
internal fun AppState.materialized(): AppState {
    val shown = ArrayList<Event>(minOf(index.size, cards.size))
    for (entry in index) shown += cards[entry.id] ?: break
    return copy(events = shown, suggested = suggestedIndex.mapNotNull { cards[it.id] })
}

/** The category filter value that means "do not filter". Not a category, so it lives apart. */
const val ALL_CATEGORIES = "all"

/** The date filter values the map offers. Strings because both platforms persist them as such. */
object DateFilter {
    const val ANY = "all"
    const val TODAY = "today"
    const val WEEKEND = "weekend"
}

/**
 * A one-line notice for the banner: named, never worded. Presentation turns the name into text
 * from its own resources, which is what keeps Ukrainian out of the shared module.
 */
sealed interface AppNotice {
    /** True for failures, so the banner can pick its tone without knowing the case. */
    val isError: Boolean

    data class Failed(val error: AppError) : AppNotice {
        override val isError get() = true
    }

    data class Told(val message: AppMessage) : AppNotice {
        override val isError get() = false
    }
}

/** Everything the app tells the user when nothing went wrong. */
enum class AppMessage {
    JOINED_EVENT, JOINED_WAITLIST, SIGNED_IN, ACCOUNT_CREATED, CONFIRM_EMAIL_FIRST,
    EVENT_PUBLISHED, CHANGES_SAVED, PHOTO_ADDED, RECOVERY_SENT, PASSWORD_CHANGED,
    SET_NEW_PASSWORD, EMAIL_CONFIRMED, ZOOM_IN_FOR_MORE,
    REQUEST_SENT, REPORT_SENT, USER_BLOCKED, AGE_CONFIRMED
}

/** Everything a build needs to reach its backend and decide where the map opens. */
data class AppConfig(
    val supabaseUrl: String,
    val publishableKey: String,
    val home: HomeLocation = HomeLocation.Kyiv
)

class Subscription(private val cancel: () -> Unit) { fun close() = cancel() }
