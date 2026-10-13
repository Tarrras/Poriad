package app.poruch.shared

import app.poruch.domain.Event
import app.poruch.domain.FollowKind
import app.poruch.domain.JoinRequest
import app.poruch.domain.MyEventsBoard
import kotlin.time.Clock
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Стан «Моїх подій»: три розрізи з секціями за часом (docs/my-events.md) і все, що рядкам треба поруч. */
data class MyEventsScreenState(
    val board: MyEventsBoard = MyEventsBoard(),
    /** Свої події як є: шторка оцінки бере подію за id звідси. */
    val myEvents: List<Event> = emptyList(),
    val waitlistedIds: List<String> = emptyList(),
    /** Мої бали за id події: «Оцінити» чи «Ваша оцінка ★ N». */
    val myRatings: Map<String, Int> = emptyMap(),
    /** Запити на участь до моїх подій: перший — на панелі найближчої. */
    val requests: List<JoinRequest> = emptyList(),
    val signedIn: Boolean = false,
    val loading: Boolean = false,
    val mutating: Boolean = false,
    /** Непрочитані повідомлення за id події: бейдж на рядку. */
    val unread: Map<String, Int> = emptyMap(),
    /** Люди, за якими стежу: початковий стан перемикача в шторці оцінки. */
    val followedOrganizers: Set<String> = emptySet()
) {
    fun isWaitlisted(id: String): Boolean = id in waitlistedIds
    fun myScore(id: String): Int? = myRatings[id]
    fun requestsFor(id: String): List<JoinRequest> = requests.filter { it.eventId == id }

    companion object {
        val Empty = MyEventsScreenState()
    }
}

/**
 * Згортає [PoruchApp.state] у [MyEventsScreenState] — та сама логіка на Android та iOS. Розклад рахує
 * `MyEventsRules` лише коли змінились `library`, `session`, `chatUnread` або минула хвилина (секції йдуть за часом).
 */
class MyEventsPresenter(
    private val app: PoruchApp,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
    compute: CoroutineDispatcher = Dispatchers.Default,
    private val clock: Clock = Clock.System
) {
    /** Для iOS: без диспетчерів і годинника. */
    constructor(app: PoruchApp) : this(app, CoroutineScope(SupervisorJob() + Dispatchers.Main))

    private val minutes = flow { while (true) { emit(Unit); delay(MINUTE_MS) } }

    init {
        app.loadMyEvents()
    }

    val state: StateFlow<MyEventsScreenState> = combine(
        app.state.distinctUntilChanged { old, new -> sameInputs(old, new) }, minutes
    ) { shared, _ -> derive(shared) }
        .flowOn(compute)
        .stateIn(scope, SharingStarted.Eagerly, MyEventsScreenState.Empty)

    /** Для iOS: колбек на кожну зміну стану екрана, на головному потоці. */
    fun observe(onChange: (MyEventsScreenState) -> Unit): Subscription {
        val job = scope.launch { state.collect { onChange(it) } }
        return Subscription { job.cancel() }
    }

    fun close() = scope.cancel()

    private fun sameInputs(old: AppState, new: AppState): Boolean =
        old.library === new.library && old.session === new.session && old.chatUnread === new.chatUnread &&
            old.mutating == new.mutating

    private fun derive(shared: AppState): MyEventsScreenState = MyEventsScreenState(
        board = shared.myEventsBoard(clock.now()),
        myEvents = shared.library.myEvents,
        waitlistedIds = shared.library.waitlistedIds,
        myRatings = shared.library.myRatings,
        requests = shared.library.pendingRequests,
        signedIn = shared.signedIn,
        loading = shared.library.loading,
        mutating = shared.mutating,
        unread = shared.chatUnread.associate { it.eventId to it.unread },
        followedOrganizers = shared.library.follows.filter { it.kind == FollowKind.ORGANIZER }.mapTo(HashSet()) { it.targetId }
    )

    private companion object {
        const val MINUTE_MS = 60_000L
    }
}
