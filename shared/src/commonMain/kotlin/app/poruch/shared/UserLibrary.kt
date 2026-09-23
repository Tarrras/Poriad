package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.*
import kotlin.time.Clock

/**
 * Стан, прив'язаний до акаунта: відкрита подія з учасниками і списки «мої». Окремо від пошуку,
 * бо все це має зникнути при зміні акаунта, і [clear] — єдине місце, яке це гарантує.
 */
internal class UserLibrary(
    private val events: EventDiscovery,
    private val saved: SavedEvents,
    private val participation: EventParticipation,
    private val requests: EventRequests,
    private val chat: EventChat,
    private val auth: AuthRepository,
    private val preferences: PreferencesRepository?,
    private val safety: SafetyRepository?,
    private val taste: TasteStore?,
    private val store: AppStore,
    private val scope: CoroutineScope
) {
    private var detailJob: Job? = null
    private var listJob: Job? = null
    /** Id відкритої події. Запізніла відповідь для іншого id відкидається. */
    var openEventId: String? = null
        private set
    /** Подія, чиї деталі вже порахували в `event_view`: перечитування й потяг униз — не новий перегляд. */
    private var viewedId: String? = null
    /**
     * Лічильник оптимістичних змін закладок. [load], що стартував до зміни, приносить список
     * з сервера без неї: тоді лишаємо закладки зі стану.
     */
    private var savedEdits = 0

    /**
     * Наводить застосунок на подію. [full] — відкриття екрана деталей, інакше підсвітка.
     * Підсвітка на кожен крок каруселі, тож мережу чіпаємо лише коли є що дізнатися: рядка нема
     * в пам'яті або деталі справді відкрито (місця й членство могли змінитися).
     */
    fun select(id: String, full: Boolean = false) {
        // Перегляд — відкриті деталі, а не крок каруселі: інакше метрика росла б від гортання.
        if (full && viewedId != id) PoruchAnalytics.track("event_view")
        if (full) viewedId = id
        openEventId = id
        detailJob?.cancel()
        // Показуємо те, що вже знаємо, поки їдуть деталі. `cards` теж: сеанс прокату, обраний
        // у каруселі дат, у стрічці згорнуто.
        val known = store.value.let {
            (it.map.events + it.library.myEvents).firstOrNull { event -> event.id == id } ?: it.cards[id]
        }
        // Інша дата того ж прокату без картки: лишаємо поточну до відповіді. Порожній екран
        // гірший за секунду старої дати, а при 504 людина лишається з банером, а не спінером.
        val stay = known == null && store.value.let { current ->
            val open = current.detail.event
            open != null && open.id != id && current.sessionsOf(open).any { it.id == id }
        }
        val willLoad = full || known == null
        store.update {
            it.copy(detail = DetailState(event = known ?: it.detail.event?.takeIf { open -> open.id == id || stay }, loading = willLoad))
        }
        if (!willLoad) {
            PoruchLog.d("detail") { "select ${id.shortId()} from memory, no request" }
            return
        }
        detailJob = scope.launch {
            try {
                val event = events.details(id)
                PoruchLog.d("detail") { "loaded ${id.shortId()} kind=${if (event?.isCommunity == true) "community" else "listing"} joined=${event?.gathering?.joined} attendees=${event?.gathering?.attendeeCount}/${event?.gathering?.capacity} status=${event?.status}" }
                if (openEventId == id) {
                    detail { copy(event = event, loading = false) }
                    if (event == null) store.failed(AppError.EventUnavailable)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (openEventId == id) detail { copy(loading = false) }
                store.failed(e.asAppError())
            }
            // Учасники — доповнення до лічильника, тож збій лишає лише число. Афішу не питаємо:
            // ростер бачать організатор і учасники (`can_view_members`), а в неї нема ні тих, ні тих.
            if (store.value.signedIn && store.value.detail.event?.isCommunity == true) {
                val roster = try { events.attendees(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
                PoruchLog.d("detail") { "roster for ${id.shortId()}: ${roster.size} visible" }
                if (openEventId == id) detail { copy(attendees = roster) }
            }
            // Запити є лише в організатора і лише для своєї події.
            val mine = store.value.detail.event?.let { it.id == id && store.value.organizes(it) } == true
            val requests = if (mine) {
                try { requests.joinRequests(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
            } else emptyList()
            if (openEventId == id) detail { copy(joinRequests = requests) }
            // Оцінки — лише завершеної кімнати і лише своїм: організатору й учасникам.
            val ended = store.value.detail.event?.takeIf {
                it.id == id && it.isCommunity && it.hasEnded(Clock.System.now()) && store.value.concerns(it)
            }
            val ratings = if (ended != null) {
                try { participation.ratings(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
            } else emptyList()
            if (openEventId == id) detail { copy(ratings = ratings) }
        }
    }

    private fun detail(change: DetailState.() -> DetailState) = store.update { it.copy(detail = it.detail.change()) }

    /** Чекає, поки доїдуть деталі відкритої події разом з учасниками й запитами. */
    suspend fun awaitDetail() { detailJob?.join() }

    fun dismiss() {
        openEventId = null; viewedId = null
        detailJob?.cancel()
        store.update { it.copy(detail = DetailState()) }
    }

    fun load() {
        val uid = auth.session.value?.userId ?: return
        listJob?.cancel()
        val edits = savedEdits
        listJob = scope.launch {
            store.update { it.copy(library = it.library.copy(loading = true)) }
            try {
                // Запити незалежні: паралельно, а не десять поспіль. Перший обов'язковий збій скасовує решту.
                coroutineScope {
                    val mine = async { events.myEvents() }
                    val savedEvents = async { saved.savedIds() }
                    val interests = async { adoptInterests(uid) }
                    // Черга вирішує, яку кнопку показати на деталях, тому не best-effort.
                    val queued = async { participation.waitlistIds() }
                    // Решта — доповнення: збій лишає те, що вже знали (null), а не порожнечу. Порожні
                    // факти після 504 знову питали вік, і сервер відповідав AGE_ALREADY_SET.
                    val facts = async { optional { safety?.account() } }
                    val blocked = async { optional { safety?.blocked() } }
                    // Стрічка запитів — без неї головна лише не покаже бейджів.
                    val pending = async { optional { requests.pendingRequests() } }
                    val unread = async { optional { chat.unread() } }
                    val result = Loaded(
                        mine.await(), savedEvents.await(), interests.await(), queued.await(),
                        facts.await(), blocked.await(), pending.await(), unread.await()
                    )
                    PoruchLog.i("mine") { "${result.mine.size} of mine, ${result.saved.size} saved, ${result.queued.size} queued, ${result.pending?.size} requests, ${result.interests.size} interests" }
                    store.update {
                        val previous = it.library
                        it.copy(
                            library = LibraryState(
                                myEvents = result.mine,
                                // Закладку поставили, поки їхала відповідь: сервер її ще не бачив.
                                savedIds = if (edits == savedEdits) result.saved else previous.savedIds,
                                waitlistedIds = result.queued,
                                pendingRequests = result.pending ?: previous.pendingRequests,
                                account = result.facts ?: previous.account,
                                blocked = result.blocked ?: previous.blocked
                            ),
                            // Відкритий чат уже прочитаний: сервер міг ще не знати.
                            chatUnread = result.unread?.filterNot { u -> u.eventId == it.chat?.eventId } ?: it.chatUnread,
                            taste = it.taste.copy(interests = result.interests, interestsOwner = uid)
                        ).rankedIfTasteChanged(it.taste)
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                store.update { it.copy(library = it.library.copy(loading = false)) }
                store.failed(e.asAppError())
            }
        }
    }

    private class Loaded(
        val mine: List<Event>, val saved: List<String>, val interests: List<String>, val queued: List<String>,
        val facts: AccountFacts?, val blocked: List<Attendee>?, val pending: List<JoinRequest>?, val unread: List<ChatUnread>?
    )

    /** Best-effort: збій (чи сервер без міграції) — null, і стан лишає попереднє. */
    private suspend fun <T> optional(block: suspend () -> T?): T? =
        try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { null }

    /** Оптимістична закладка: стан одразу, і [load], що вже в дорозі, її не затре. */
    fun setSaved(id: String, saved: Boolean) {
        savedEdits++
        store.update {
            val ids = it.library.savedIds
            it.copy(library = it.library.copy(savedIds = if (saved) (ids + id).distinct() else ids - id))
        }
    }

    /** Чекає, поки доїдуть «мої». Гість нічого не вантажить, тож повертається одразу. */
    suspend fun awaitList() { listJob?.join() }

    /**
     * Узгоджує інтереси пристрою з акаунтом [uid]. Акаунт перемагає, якщо має хоч щось; порожній
     * акаунт (звичний випадок, питання ставлять до реєстрації) отримує відповіді пристрою — але
     * лише гостьові чи свої: інтереси акаунта A, що лишились на телефоні після виходу, до B не йдуть.
     */
    private suspend fun adoptInterests(uid: String): List<String> {
        val local = store.value.taste
        val remote = preferences?.interests().orEmpty()
        if (remote.isEmpty() && local.interests.isNotEmpty() && (local.interestsOwner == null || local.interestsOwner == uid)) {
            runCatching { preferences?.setInterests(local.interests) }
            if (local.interestsOwner != uid) taste?.write(local.copy(interestsOwner = uid))
            return local.interests
        }
        if (remote != local.interests || local.interestsOwner != uid) taste?.write(store.value.taste.copy(interests = remote, interestsOwner = uid))
        return remote
    }

    /** Зупиняє читання для попереднього акаунта і чистить його кеш на диску. Стан чистить [forAccount]. */
    fun clear() {
        listJob?.cancel(); detailJob?.cancel(); openEventId = null
        events.clearPrivateCache()
    }
}
