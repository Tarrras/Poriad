package app.poruch.shared

import app.poruch.domain.ArtistHit
import app.poruch.domain.ChatUnread
import app.poruch.domain.CityResult
import app.poruch.domain.Event
import app.poruch.domain.EventCategory
import app.poruch.domain.FeedEntry
import app.poruch.domain.FeedFilter
import app.poruch.domain.FeedSource
import app.poruch.domain.FollowRules
import app.poruch.domain.HomeLocation
import app.poruch.domain.HomeRules
import app.poruch.domain.Place
import app.poruch.domain.RequestRules
import kotlin.time.Clock
import kotlin.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

/*
 * Пер-екранний презентер: згортає спільний [AppState] у стан одного екрана й віддає його обом
 * платформам. Раніше ту саму згортку писали двічі (HomeViewModel.fold на Android і
 * HomePresentation.init на iOS), і вони розходились. Тут вона одна, рахується не на головному
 * потоці й лише коли змінились її входи, а не на кожну емісію стору.
 */

/** Рядок «Ваше»: своя подія, її непрочитаний чат і скільки людей просяться. */
data class PersonalRow(val event: Event, val chat: ChatUnread?, val requests: Int, val organizing: Boolean)

/** Стан головної: усе вже відфільтроване й посортоване для рендеру. Платформа додає лише своє локальне (режим пошуку, ліміти, листи). */
data class HomeScreenState(
    val signedIn: Boolean = false,
    val cityName: String = "",
    val cities: List<CityResult> = emptyList(),
    val loading: Boolean = false,
    /** «Ваше»: до [HomeRules.PERSONAL_LIMIT] своїх подій, спершу ті, де хтось чекає відповіді. */
    val personal: List<PersonalRow> = emptyList(),
    /** Майбутні події тих, за ким стежу, з усіх міст, найближчі першими. Порожньо — рядка «Ви стежите» нема. */
    val followed: List<Event> = emptyList(),
    /** Хто з підписок має щось попереду, у порядку найближчої події: підпис рядка «Ви стежите». */
    val followNames: List<String> = emptyList(),
    /** Скільки нового в підписках ще не переглянуто: бейдж рядка «Ви стежите». */
    val newFollowEvents: Int = 0,
    /** Скільки подій, що чекають відповіді (чат, запит), у [personal] не влізло: рядок «Чекають відповіді: ще N». */
    val moreWaiting: Int = 0,
    /** «Від людей»: зустрічі з вільним місцем окремою рейкою, коли їх набралось досить ([HomeRules.people]); інакше порожньо. */
    val people: List<FeedEntry> = emptyList(),
    /** «У місті»: [HomeRules.HERO_COUNT] великих карток, далі сітка, вже звужена [feedFilter]. */
    val feed: List<FeedEntry> = emptyList(),
    /** Чипи над сіткою: що з неї можна відфільтрувати. Порожньо — рядка нема. */
    val chips: List<FeedFilter> = emptyList(),
    /** Обраний чип; якщо його вже нема в [chips] (дані оновились), стрічка лишається цілою. */
    val feedFilter: FeedFilter = FeedFilter(),
    /** Скільки подій в області, без фільтрів мапи. */
    val totalFound: Int = 0,
    /** Скільки відкритих зустрічей від людей у місті всього: число в «Усі N» біля «Від людей», рейка показує лише перші. */
    val openRooms: Int = 0,
    val savedIds: List<String> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    /** Пошук головної, окремий від мапи: фільтр одного екрана не порожнить інший. */
    val searchText: String = "",
    /** Результати пошуку в порядку видачі, до першої картки, що ще їде. */
    val results: List<Event> = emptyList(),
    /** Id усього знайденого, у порядку видачі: з нього довантажують картки наступного шматка. */
    val resultIds: List<String> = emptyList(),
    /** Скільки знайдено насправді. */
    val resultsTotal: Int = 0,
    /** Заклади за тим самим запитом: секція «Місця» під подіями. */
    val places: List<Place> = emptyList(),
    /** Артисти за тим самим запитом: секція «Артисти» під «Місцями». */
    val artists: List<ArtistHit> = emptyList(),
    val searchLoading: Boolean = false,
    /** Пошук по всіх містах, а не лише в [cityName]. Фільтри пошуку звужують лише знайдене, не стрічку. */
    val searchEverywhere: Boolean = false,
    val searchCategory: EventCategory? = null,
    val searchDate: DateFilter = DateFilter.ANY,
    /** Місто з подіями, назване в пошуку, крім поточного: текстовий пошук іде лише в межах міста. */
    val cityMatch: HomeLocation? = null
) {
    val searching: Boolean get() = searchText.isNotBlank()
    /** Скільки результатів прийшло в індексі: більше за ліміт показу — є що показати ще. */
    val resultsIndexed: Int get() = resultIds.size
    val isEmpty: Boolean get() =
        if (searching) results.isEmpty() && places.isEmpty() && artists.isEmpty() else personal.isEmpty() && people.isEmpty() && feed.isEmpty()
    val busy: Boolean get() = if (searching) searchLoading else loading
    fun isSaved(id: String): Boolean = id in savedIds
    fun isWaitlisted(id: String): Boolean = id in waitlistedIds
    /** Перші [limit] результатів: «Показати ще» росте на місці. */
    fun results(limit: Int): List<Event> = results.take(limit)
    /** Будь-яка зміна запиту чи фільтрів — нова видача: «Показати ще» починає спочатку. */
    val searchKey: String get() = "$searchText|$searchEverywhere|${searchCategory?.key ?: "*"}|${searchDate.name}"

    companion object {
        /** Порожній стан до першої згортки: Swift не бачить аргументів за замовчуванням конструктора. */
        val Empty = HomeScreenState()
    }
}

/**
 * Згортає [PoruchApp.state] у [HomeScreenState]. Перераховує лише коли змінились зрізи, від яких залежить
 * головна (`home`, `library`, `chatUnread`, `city`, `session` — за посиланням, бо `copy()` їх зберігає),
 * обраний чип або минула хвилина (щоб «сьогодні» і «почалось» ішли за годинником). Рахує на [compute],
 * стан віддає на [scope]: на Android це Main моделі, на iOS — головний потік.
 */
class HomePresenter(
    private val app: PoruchApp,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
    compute: CoroutineDispatcher = Dispatchers.Default,
    private val clock: Clock = Clock.System
) {
    /** Для iOS: Swift не бачить аргументів за замовчуванням, а диспетчери й годинник йому не потрібні. */
    constructor(app: PoruchApp) : this(app, CoroutineScope(SupervisorJob() + Dispatchers.Main))

    private val filter = MutableStateFlow(FeedFilter())
    private val minutes = flow { while (true) { emit(Unit); delay(MINUTE_MS) } }

    val state: StateFlow<HomeScreenState> = combine(
        app.state.distinctUntilChanged { old, new -> sameInputs(old, new) }, filter, minutes
    ) { shared, filter, _ -> derive(shared, filter, clock.now(), TimeZone.currentSystemDefault()) }
        .flowOn(compute)
        .stateIn(scope, SharingStarted.Eagerly, HomeScreenState())

    /** Чип над сіткою. Сітку збирає згортка, тож чип — її вхід, а не локальний стан екрана. */
    fun selectFeedFilter(filter: FeedFilter) { this.filter.value = filter }

    /** Для iOS: колбек на кожну зміну стану екрана, на головному потоці. */
    fun observe(onChange: (HomeScreenState) -> Unit): Subscription {
        val job = scope.launch { state.collect { onChange(it) } }
        return Subscription { job.cancel() }
    }

    fun close() = scope.cancel()

    private fun sameInputs(old: AppState, new: AppState): Boolean =
        old.home === new.home && old.library === new.library && old.chatUnread === new.chatUnread &&
            old.city === new.city && old.session === new.session

    internal fun derive(shared: AppState, feedFilter: FeedFilter, now: Instant, zone: TimeZone): HomeScreenState {
        val zoneId = zone.id
        val today = now.toLocalDateTime(zone).date
        // Увесь екран в одному порядку — ранжованому.
        // Своя стрічка: та сама область, що на мапі, але без її фільтрів.
        // Картки до індексу прив'язує спільний код: тут лише завантажені, а не тисячі записів.
        val home = shared.home
        // Сервер не віддає сеанси, що почались, але за час у застосунку вони починаються (Event.isListed).
        val ranked = home.events.filter { it.isListed(now) }
        val suggested = home.suggested.filter { it.isListed(now) }.take(SUGGESTED_LIMIT)
        // Те, що вже в «Для вас», у списку міста не повторюємо.
        val remaining = ranked - suggested.toSet()
        // Місто: куди можна піти сьогодні, включно з прокатами, далі решта за рангом. Але те, що сьогодні
        // починається, йде першим: прокат буде відкритий і завтра, а концерт можна пропустити.
        val (startingToday, later) = remaining.partition { it.startsOn(today, zone) }
        val runningToday = later.filter { it.isUnderway(now) }
        val city = startingToday + runningToday + (later - runningToday.toSet())
        // Стрічка приїхала з сервера, а події за час у застосунку встигають скінчитись.
        val followed = shared.library.followEvents.filter { it.isPublished && it.isListed(now) }
        // Підписки сервер віддає з усіх міст (тур артиста). «Ваше» показує їх усі, а «У місті» й «Від людей» — лише свої.
        val area = HomeLocation(shared.city.name, shared.city.latitude, shared.city.longitude)
        val followedHere = followed.filter { area.contains(it.latitude, it.longitude) }
        val via = followed.associate { it.id to FollowRules.via(it, shared.library.follows)?.name }

        // «Ваше»: чат із непрочитаним (навіть минулої події) і запити чекають на людину, тож вони першими.
        val mine = shared.library.myEvents.associateBy { it.id }
        val plans = shared.library.myEvents.filter { shared.concerns(it) && it.isPublished && it.isCurrent(now) }.sortedBy { it.startsAt }
        val chats = shared.chatUnread.associateBy { it.eventId }
        val asks = RequestRules.pendingByEvent(shared.library.pendingRequests)
        val waiting = shared.chatUnread.mapNotNull { mine[it.eventId] } + asks.keys.mapNotNull { mine[it] }.filter { it.isCurrent(now) }
        val mineFirst = (waiting + plans).distinctBy { it.id }
        val personal = mineFirst.take(HomeRules.PERSONAL_LIMIT)
            .map { PersonalRow(it, chats[it.id], asks[it.id] ?: 0, shared.organizes(it)) }
        val shown = personal.mapTo(HashSet()) { it.event.id }
        // Усі свої плани, а не лише три з «Ваше»: решта живе в «Моїх подіях», а в місті стояла б безіменним постером.
        val mineIds = mineFirst.mapTo(HashSet()) { it.id }
        val people = HomeRules.people(suggested, city, followedHere, mineIds)
        // Кімнати, що дістали власну секцію, у стрічці не повторюємо й уперед їх більше не ставимо.
        val all = HomeRules.feed(suggested, city, followedHere, mineIds + people.map { it.event.id }, roomsFirst = people.isEmpty())
            .map { if (it.source == FeedSource.FOLLOWING) it.copy(followName = via[it.event.id]) else it }
        val rest = all.drop(HomeRules.HERO_COUNT)
        val chips = HomeRules.chips(rest, now, zoneId)
        val filter = feedFilter.takeIf { it in chips } ?: FeedFilter()
        return HomeScreenState(
            signedIn = shared.signedIn,
            cityName = shared.city.name,
            cities = shared.city.suggestions,
            loading = home.loading,
            personal = personal,
            followed = followed,
            followNames = followed.mapNotNull { via[it.id] }.distinct(),
            newFollowEvents = shared.library.newFollowEvents,
            moreWaiting = waiting.mapTo(HashSet()) { it.id }.count { it !in shown },
            people = people,
            feed = all.take(HomeRules.HERO_COUNT) + HomeRules.apply(rest, filter, now, zoneId),
            chips = chips,
            feedFilter = filter,
            totalFound = home.totalFound,
            openRooms = home.openRooms,
            savedIds = shared.library.savedIds,
            waitlistedIds = shared.library.waitlistedIds,
            searchText = home.searchText,
            results = inOrder(home),
            resultIds = home.results.map { it.id },
            resultsTotal = home.resultsTotal,
            places = home.places.map { it.countedIn(home.index) },
            artists = home.artists,
            searchLoading = home.searchLoading,
            searchEverywhere = home.searchEverywhere,
            searchCategory = home.searchCategory,
            searchDate = home.searchDate,
            // Пошук усюди вже бачить інші міста: підказка «лише в межах міста» була б неправдою.
            cityMatch = if (home.searching && !home.searchEverywhere) HomeLocation.mentioned(home.searchText, shared.city.name) else null
        )
    }

    /**
     * Картки видачі в її порядку, до першої, що ще їде: [HomeFeed.found] її пропускає,
     * і після довантаження нижні картки стрибали б.
     */
    private fun inOrder(home: HomeFeed): List<Event> {
        val cards = home.found.associateBy { it.id }
        val shown = ArrayList<Event>(home.found.size)
        for (entry in home.results) shown += cards[entry.id] ?: break
        return shown
    }

    private fun Event.startsOn(date: LocalDate, zone: TimeZone): Boolean =
        startInstant?.toLocalDateTime(zone)?.date == date

    private companion object {
        /** Більше за це «для вас» перестає бути добіркою. */
        const val SUGGESTED_LIMIT = 4
        const val MINUTE_MS = 60_000L
    }
}
