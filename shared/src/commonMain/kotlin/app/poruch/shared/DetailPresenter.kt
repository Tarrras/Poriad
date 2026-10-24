package app.poruch.shared

import app.poruch.domain.Attendee
import app.poruch.domain.CompanionCard
import app.poruch.domain.CheckedLabel
import app.poruch.domain.CompanionParent
import app.poruch.domain.CurfewNote
import app.poruch.domain.Event
import app.poruch.domain.EventIndexEntry
import app.poruch.domain.EventRating
import app.poruch.domain.EventSafety
import app.poruch.domain.EventSession
import app.poruch.domain.FollowKind
import app.poruch.domain.Gathering
import app.poruch.domain.Inviter
import app.poruch.domain.Listing
import app.poruch.domain.PendingMeet
import app.poruch.domain.RatingRules
import kotlin.concurrent.Volatile
import kotlin.time.Clock
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.datetime.TimeZone

/** Єдина дія нижньої панелі деталей. Рахується в одному місці, щоб підпис, тап і доступність не розходились. */
enum class DetailAction {
    /** Кнопки нема: афіша без посилання, скасована, відкладена чи не в продажу, або зіпсований рядок. */
    NONE,
    JOIN, LEAVE, JOIN_WAITLIST, LEAVE_WAITLIST,
    /** Афіша: сторінка джерела. */
    TICKETS,
    /** Подія з підтвердженням: кнопка просить, а не бере місце. */
    REQUEST,
    /** Запит надіслано, чекаємо. */
    REQUESTED,
    /** Для організатора. */
    ORGANIZER,
    CANCELLED;

    val isEnabled: Boolean get() = this == JOIN || this == LEAVE || this == JOIN_WAITLIST ||
        this == LEAVE_WAITLIST || this == REQUEST || this == TICKETS
}

/** Стан екрана деталей однієї події: усе, що екран малює, вже порахованe. Платформа додає лише свої листи й прапорці. */
data class DetailScreenState(
    val event: Event? = null,
    /** Сеанси прокату для каруселі. Менше двох — каруселі нема. */
    val sessions: List<EventSession> = emptyList(),
    /** Сеанс на екрані: з яким відкрили або обраний у каруселі. */
    val sessionId: String = "",
    /** Сеанс прокату вже почався: показати можна, купити квиток — ні. Тижневої виставки не стосується. */
    val sessionStarted: Boolean = false,
    /** Інші події на цій же точці: «Ще в цьому місці». */
    val othersHere: List<EventIndexEntry> = emptyList(),
    val attendees: List<Attendee> = emptyList(),
    /** Сама подія ще в дорозі (або слот забрав інший екран деталей і ми ось-ось попросимо його назад). */
    val loading: Boolean = true,
    val mutating: Boolean = false,
    val signedIn: Boolean = false,
    val saved: Boolean = false,
    val waitlisted: Boolean = false,
    val organizer: Boolean = false,
    /** Хто проситься. Непорожньо лише для організатора. */
    val requests: List<Attendee> = emptyList(),
    /** Подія завершилась: участь уже нічого не змінює. */
    val ended: Boolean = false,
    /** Подія почалась: сервер не приймає правок із минулим початком, тож редагування й фото закриті. */
    val started: Boolean = false,
    /** Учасник і вікно оцінки ще відкрите. */
    val canRate: Boolean = false,
    /** Організаторові всі оцінки, учасникові — своя. */
    val ratings: List<EventRating> = emptyList(),
    /** Відкрита картка людини: з ростеру, запиту чи рядка організатора. */
    val person: PersonState? = null,
    /** Хто дивиться: своя картка без скарги й блокування. */
    val userId: String? = null,
    /** Фото організатора для рядка в «Ідуть». */
    val organizerAvatar: String? = null,
    /** Укриття поруч і комендантська міста; null — не завантажилось або даних нема. */
    val safety: EventSafety? = null,
    /** Рядок «до комендантської»; null — не вечір або міста нема в довіднику. */
    val curfew: CurfewNote? = null,
    /** Хто шукає компанію на цю афішу: картки супутників без імен. */
    val companions: List<CompanionCard> = emptyList(),
    /** Кнопка «Шукаю компанію»: афіша ще попереду, мого пошуку на неї нема. */
    val canSeekCompany: Boolean = false,
    /** Стежу за закладом цієї афіші. */
    val followingPlace: Boolean = false,
    /** Люди, за якими стежу: кнопка на картці людини й початковий стан перемикача в шторці оцінки. */
    val followedOrganizers: Set<String> = emptySet(),
    /** Щойно створений супутник: платформа відкриває «Поділитися» і кличе [PoruchApp.clearCreatedCompanion]. */
    val createdCompanion: String? = null,
    /** Хто кличе: подію відкрили з посилання-запрошення (docs/invites.md). Обкладинка каже «Тарас кличе тебе». */
    val inviter: Inviter? = null,
    /** «Перевірено сьогодні о 09:00» для афіші: коли адресна перевірка читала продавців. Null — не перевіряли. */
    val checked: CheckedLabel? = null
) {
    /** Супутник «Йдемо разом»: місце й решту тримає сервер; організатор міняє лише час ([canMoveMeet]). */
    val companionOf: CompanionParent? get() = room?.companionOf
    /** Афішу перенесли, збір чекає рішення організатора (R7а). Скасованому нема чого вирішувати. */
    val pendingMeet: PendingMeet? get() = room?.pendingMeet?.takeIf { !cancelled }
    /** Організатор збору може змінити його час (R7б): збір і афіша ще попереду, сервер знає її початок. */
    val canMoveMeet: Boolean get() = organizer && companionOf?.startsAt != null && !cancelled && !started
    val myRating: EventRating? get() = ratings.firstOrNull { it.mine }
    val cancelled: Boolean get() = event?.isCancelled == true
    /** «Покликати» замість «Поділитися» (docs/invites.md): подія ще попереду й відбудеться. Скасованою чи минулою — ділимось. */
    val canInvite: Boolean get() = event?.isCalledOff == false && !ended
    /** Кімната, якщо це кімната. Місця й участь лише в неї. */
    val room: Gathering? get() = event?.gathering
    /** Оголошення, якщо це афіша. Тоді дія одна: вийти на джерело. */
    val listing: Listing? get() = event?.listing
    val full: Boolean get() = room?.isFull == true
    /** Чат є для своїх: організатора й підтверджених. Скасована подія лишає його для читання. */
    val hasChat: Boolean get() = room != null && (organizer || room!!.joined)
    /** Чат учасників поза застосунком. Сервер віддає посилання лише організатору й підтвердженим; лише https. */
    val contactUrl: String? get() = room?.contactUrl?.takeIf { it.startsWith("https://") }

    /**
     * Афіша відгалужується першою: кнопка «приєднатися», яка гарантовано отримає відмову, гірша за відсутність кнопки.
     * У скасованої афіші кнопки нема зовсім: до продавців веде блок «Якщо купили квиток».
     */
    val action: DetailAction
        get() = when {
            event == null -> DetailAction.NONE
            listing != null ->
                if (listing!!.isWithdrawn || !listing!!.hasSource || sessionStarted) DetailAction.NONE
                else DetailAction.TICKETS
            cancelled -> DetailAction.CANCELLED
            organizer -> DetailAction.ORGANIZER
            ended -> DetailAction.NONE
            // Ні кімнати, ні оголошення — зіпсований рядок: без дій.
            room == null -> DetailAction.NONE
            room!!.awaitingApproval -> DetailAction.REQUESTED
            room!!.joined -> DetailAction.LEAVE
            waitlisted -> DetailAction.LEAVE_WAITLIST
            room!!.approvalRequired -> DetailAction.REQUEST
            full -> DetailAction.JOIN_WAITLIST
            else -> DetailAction.JOIN
        }

    companion object {
        /** До першої згортки: спінер, а не «подія недоступна». Swift не бачить аргументів за замовчуванням. */
        val Empty = DetailScreenState()
    }
}

/**
 * Згортає [PoruchApp.state] у [DetailScreenState] для однієї відкритої події — та сама логіка на Android
 * та iOS. Просить деталі в сторі сам (`openEvent`), тримає сеанс каруселі й «якір» прокату, перераховує
 * лише коли змінились зрізи, від яких залежить екран. Платформа лишає собі листи, прапорці й навігацію.
 */
class DetailPresenter(
    private val app: PoruchApp,
    /** Картка, з якою відкрили екран. Карусель будується від неї: скасованого вечора в індексі нема. */
    private val openedId: String,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
    compute: CoroutineDispatcher = Dispatchers.Default,
    private val clock: Clock = Clock.System
) {
    /** Для iOS: без диспетчерів і годинника. */
    constructor(app: PoruchApp, openedId: String) : this(app, openedId, CoroutineScope(SupervisorJob() + Dispatchers.Main))

    /**
     * Сеанс на екрані. Карусель дат перемикає його, і всі дії (збереження, участь, скарга, мапа) ідуть на нього.
     * Ключ екрана лишається [openedId], щоб не губити прокрутку й карусель.
     */
    @Volatile var sessionId: String = openedId
        private set

    /** Дата, обрана в каруселі, чиєї картки ще нема. Стане обраною, коли картка приїде; до того дії йдуть на попередню. */
    @Volatile private var pendingId: String? = null
    private var anchor: Event? = null
    private var carousel: List<EventSession> = emptyList()
    private var nearby: List<EventIndexEntry> = emptyList()
    /** Картку вже показували: порожній слот далі — не завантаження, а інший екран деталей поверх. */
    @Volatile private var shown = false
    private var carouselFrom: Pair<Event, List<EventIndexEntry>>? = null
    /** Події закладу, з яких порахували [nearby]: приїхали — перераховуємо «Ще в цьому місці». */
    private var nearbyFrom: PlaceEvents? = null

    init {
        // Тут, а не з композиції чи `.task`: презентер переживає поворот і перестворення view, запит іде один раз.
        app.openEvent(openedId)
    }

    val state: StateFlow<DetailScreenState> = app.state
        .distinctUntilChanged { old, new -> sameInputs(old, new) }
        .map { derive(it) }
        .flowOn(compute)
        .stateIn(scope, SharingStarted.Eagerly, DetailScreenState.Empty)

    /** Інша дата в каруселі прокату. Спершу [pendingId], потім запит: згортка має впізнати картку нового вечора. */
    fun pickSession(id: String) {
        if (id == sessionId) return
        pendingId = id
        app.openEvent(id)
    }

    /** Екран знову зверху після іншого екрана деталей: той перебрав єдиний слот відкритої події. */
    fun reopen() {
        if (shown && state.value.event == null) app.openEvent(sessionId)
    }

    /** Потяг вниз: перечитати місця, членство й запити. */
    suspend fun refresh() = app.reloadEvent(sessionId)

    /** Id картки, під якою сеанс стоїть у видачі мапи: для другої дати прокату — представник. */
    fun cardId(): String = app.cardIdOf(sessionId)

    /**
     * Екран зняли. Картка людини належить екрану; слот відкритої події — теж, крім передачі мапі
     * ([keepSlot]: «На мапі» бере його як фокус) і коли слот уже в екрана поверх.
     */
    fun release(keepSlot: Boolean = false) {
        app.closePerson()
        if (!keepSlot && app.state.value.detail.event?.id == sessionId) app.dismissEvent()
        scope.cancel()
    }

    /** Для iOS: колбек на кожну зміну стану екрана, на головному потоці. */
    fun observe(onChange: (DetailScreenState) -> Unit): Subscription {
        val job = scope.launch { state.collect { onChange(it) } }
        return Subscription { job.cancel() }
    }

    private fun sameInputs(old: AppState, new: AppState): Boolean =
        old.detail === new.detail && old.library === new.library && old.session === new.session &&
            old.person === new.person && old.map.index === new.map.index && old.cards === new.cards &&
            old.mutating == new.mutating && old.createdCompanion == new.createdCompanion && old.invite === new.invite

    private fun derive(shared: AppState): DetailScreenState {
        pendingId?.let { pending ->
            if (shared.detail.event?.id == pending) { sessionId = pending; pendingId = null }
        }
        val eventId = sessionId
        val event = shared.detail.event?.takeIf { it.id == eventId }
        if (event != null && event.id == openedId) anchor = event
        // Перебудова лише при зміні картки або індексу: пошук прокату проходить увесь індекс.
        val source = anchor
        val from = carouselFrom
        if (source != null && (from == null || from.first !== source || from.second !== shared.map.index)) {
            carousel = shared.sessionsOf(source)
            nearby = shared.othersAt(source)
            carouselFrom = source to shared.map.index
            nearbyFrom = shared.detail.placeEvents
        } else if (source != null && nearbyFrom !== shared.detail.placeEvents) {
            nearby = shared.othersAt(source)
            nearbyFrom = shared.detail.placeEvents
        }
        if (event != null) shown = true
        val now = clock.now()
        return DetailScreenState(
            event = event,
            sessionId = eventId,
            // Скасування відоме з картки, навіть якщо карусель знала дату опублікованою.
            sessions = if (event?.isCancelled == true) carousel.map { if (it.id == event.id) it.copy(cancelled = true) else it } else carousel,
            sessionStarted = event != null && carousel.size > 1 && !event.isMultiDay && event.hasStarted(now),
            othersHere = nearby,
            attendees = shared.detail.attendees,
            // Картку вже показували, а слот порожній: його забрав інший екран деталей, і на повернення ми
            // попросимо його назад (`reopen`). Той кадр — завантаження, а не «подія недоступна».
            loading = shared.detail.loading || (shown && event == null),
            mutating = shared.mutating,
            signedIn = shared.signedIn,
            saved = shared.isSaved(eventId),
            waitlisted = shared.isWaitlisted(eventId),
            organizer = event != null && shared.organizes(event),
            requests = shared.detail.joinRequests,
            ended = event?.hasEnded(now) == true,
            started = event?.hasStarted(now) == true,
            canRate = event != null && RatingRules.canRate(event, now),
            ratings = shared.detail.ratings,
            person = shared.person,
            userId = shared.session.userId,
            organizerAvatar = shared.detail.organizerAvatar,
            safety = shared.detail.safety,
            curfew = shared.detail.curfewNote(now),
            companions = if (event != null) shared.detail.companions.orEmpty() else emptyList(),
            canSeekCompany = event != null && shared.detail.canSeekCompany(now),
            followingPlace = event?.placeId?.let { shared.isFollowing(FollowKind.PLACE, it) } == true,
            followedOrganizers = shared.library.follows.filter { it.kind == FollowKind.ORGANIZER }.mapTo(HashSet()) { it.targetId },
            createdCompanion = shared.createdCompanion?.takeIf { event != null },
            inviter = shared.invite?.takeIf { event != null && it.first == eventId }?.second,
            checked = CheckedLabel.of(event?.listing?.checkedAt, now, TimeZone.currentSystemDefault())
        )
    }
}
