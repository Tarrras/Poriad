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
    private val profiles: ProfileRepository?,
    private val follows: Follows?,
    private val taste: TasteStore?,
    private val store: AppStore,
    private val scope: CoroutineScope,
    /** Закладки гостя на телефоні (docs/guest-saves.md). Null — лише в стані до перезапуску. */
    private val guestSaves: GuestSavedStore? = null
) {
    private var detailJob: Job? = null
    private var listJob: Job? = null
    private var followJob: Job? = null
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

    /** Те саме для підписок: [load], що стартував до зміни «Стежити», не має її затерти. */
    private var followEdits = 0

    /**
     * Запитів «Стежити» у дорозі. Поки хоч один не завершився, список із сервера міг його не побачити: [load] і
     * [refreshFollows] стану не чіпають, а той, що завершився останнім, перечитує сам ([followFinished]).
     */
    private var followBusy = 0

    /** Подія й підпис, звідки її відкрито (`home_hero`, `home_poster`…): лише для `event_view`. */
    private var openedFrom: Pair<String, String>? = null

    /** Подія й токен запрошення, з яким її відкрили з посилання: її деталі кажуть, хто кличе (docs/invites.md). */
    private var invitedTo: Pair<String, String>? = null

    /** Подію [eventId] відкрито з посилання з запрошенням [token] чи без нього: звичайне посилання знімає попереднє. */
    fun openedFromLink(eventId: String, token: String?) {
        invitedTo = token?.let { eventId to it }
    }

    /**
     * Посилання для «Покликати» (docs/invites.md): з входом — особисте, з токеном. Гостю чи коли токен не вдався —
     * звичайне: ділитися не можна блокувати. Метрика петлі — `share` з `kind=invite` проти `kind=event`.
     */
    suspend fun inviteLink(eventId: String): String {
        val token = if (!store.value.signedIn) null else try {
            participation.invite(eventId)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PoruchLog.w("invite") { "plain link for ${eventId.shortId()}: ${e.asAppError()}" }
            null
        }
        PoruchAnalytics.track("share", "kind" to if (token != null) "invite" else "event")
        return EventLinks.url(eventId, token)
    }

    /**
     * Наводить застосунок на подію. [full] — відкриття екрана деталей, інакше підсвітка.
     * Підсвітка на кожен крок каруселі, тож мережу чіпаємо лише коли є що дізнатися: рядка нема
     * в пам'яті або деталі справді відкрито (місця й членство могли змінитися).
     */
    fun select(id: String, full: Boolean = false, from: String? = null) {
        // Звідки відкрили: ставить лише підсвітка, деталі приходять слідом. Підсвітка без джерела його скидає,
        // щоб «головна» не дісталась перегляду, що почався деінде.
        if (!full) openedFrom = from?.let { id to it }
        // Перегляд — відкриті деталі, а не крок каруселі: інакше метрика росла б від гортання.
        if (full && viewedId != id) PoruchAnalytics.track("event_view", "from" to openedFrom?.takeIf { it.first == id }?.second)
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
            val shown = known ?: it.detail.event?.takeIf { open -> open.id == id || stay }
            // Інша дата того ж закладу: «Ще в цьому місці» не блимає, поки події закладу перечитуються.
            val atPlace = it.detail.placeEvents?.takeIf { place -> shown?.placeId == place.placeId }
            // Перечитування тієї ж афіші (після запиту в супутник) не ховає секцію «Шукають компанію».
            val companions = it.detail.companions?.takeIf { _ -> it.detail.event?.id == id }
            val inviter = it.detail.inviter?.takeIf { _ -> it.detail.event?.id == id }
            it.copy(detail = DetailState(event = shown, loading = willLoad, placeEvents = atPlace, companions = companions, inviter = inviter))
        }
        if (!willLoad) {
            PoruchLog.d("detail") { "select ${id.shortId()} from memory, no request" }
            return
        }
        detailJob = scope.launch {
            try {
                // `event_details` віддає старий композит без закладу: беремо його з картки.
                val event = events.details(id)?.withPlaceOf(store.value.cards[id] ?: known)
                PoruchLog.d("detail") { "loaded ${id.shortId()} kind=${if (event?.isCommunity == true) "community" else "listing"} joined=${event?.gathering?.joined} attendees=${event?.gathering?.attendeeCount}/${event?.gathering?.capacity} status=${event?.status?.key}" }
                if (openEventId == id) {
                    detail { copy(event = event, loading = false) }
                    if (event == null) store.failed(AppError.EventUnavailable)
                }
                // Афішу відкрили без картки (посилання, пуш): заклад і артисти є лише в картці, тож беремо її окремо. Без
                // цього не було б ні «Стежити» на місці, ні «Ще в «…»» у деталях.
                if (event?.listing != null && event.placeId == null) {
                    val withPlace = event.withPlaceOf(optional { events.cards(listOf(id)).firstOrNull() })
                    if (openEventId == id && withPlace != event) detail { copy(event = withPlace) }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (openEventId == id) detail { copy(loading = false) }
                store.failed(e.asAppError())
            }
            // Відкрили з запрошення: хто кличе — на обкладинці, тож одразу після події. Збій лише ховає рядок.
            val invite = invitedTo?.takeIf { full && it.first == id && store.value.detail.event?.id == id }
            if (invite != null) {
                val inviter = optional { events.inviter(invite.second, id) }
                if (openEventId == id) detail { copy(inviter = inviter) }
            }
            // Події закладу для «Ще в цьому місці». Збій лишає секцію на індексі мапи.
            val placeId = store.value.detail.event?.takeIf { it.id == id }?.placeId
            if (full && placeId != null) {
                val atPlace = optional { events.placeEvents(placeId) }
                if (openEventId == id && atPlace != null) detail { copy(placeEvents = PlaceEvents(placeId, atPlace)) }
            }
            // Хто шукає компанію на цю афішу. Одразу після події: секція вище за згином, а збій лише її ховає.
            if (full && store.value.detail.event?.takeIf { it.id == id }?.let { CompanionRules.canOffer(it, Clock.System.now()) } == true) {
                val companions = optional { events.companions(id) }
                if (openEventId == id) detail { copy(companions = companions) }
            }
            // Учасники — доповнення до лічильника, тож збій лишає лише число. Афішу не питаємо:
            // ростер бачать організатор і учасники (`can_view_members`), а в неї нема ні тих, ні тих.
            if (store.value.signedIn && store.value.detail.event?.isCommunity == true) {
                val roster = try { events.attendees(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { emptyList() }
                PoruchLog.d("detail") { "roster for ${id.shortId()}: ${roster.size} visible" }
                if (openEventId == id) detail { copy(attendees = roster) }
            }
            // Фото організатора — з його картки. Best-effort, як ростер: без нього лишається літера.
            val organizerId = store.value.detail.event?.takeIf { it.id == id && it.isCommunity }?.organizerId
            if (store.value.signedIn && organizerId != null) {
                val avatar = optional { profiles?.profile(organizerId)?.avatarUrl }
                if (openEventId == id) detail { copy(organizerAvatar = avatar) }
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
            // Укриття поруч і комендантська для блоку «Безпека». Останнім: він під згином екрана,
            // а збій лише ховає блок.
            if (full) {
                val safety = optional { events.safety(id) }
                if (openEventId == id) detail { copy(safety = safety) }
            }
        }
    }

    /** Перечитує «Шукають компанію» відкритої афіші: після створення супутника чи запиту в нього. */
    fun refreshCompanions() {
        val id = openEventId ?: return
        if (store.value.detail.event?.takeIf { it.id == id }?.listing == null) return
        scope.launch {
            val companions = optional { events.companions(id) } ?: return@launch
            if (openEventId == id) detail { copy(companions = companions) }
        }
    }

    /** Те, що `event_details` не несе, а картка несе: заклад і склад артистів. */
    private fun Event.withPlaceOf(card: Event?): Event {
        val same = card?.takeIf { it.id == id } ?: return this
        val full = if (artists.isEmpty() && same.artists.isNotEmpty()) copy(artists = same.artists) else this
        val own = full.listing ?: return full
        val place = same.listing ?: return full
        if (own.placeId != null || place.placeId == null) return full
        return full.copy(listing = own.copy(placeId = place.placeId, placeName = place.placeName))
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
        val uid = auth.session.value?.userId ?: return loadGuest()
        listJob?.cancel()
        val edits = savedEdits
        val followsAtStart = followEdits
        listJob = scope.launch {
            store.update { it.copy(library = it.library.copy(loading = true)) }
            try {
                // До `my_events`: інакше збережене гостем зʼявилось би в «Моїх подіях» лише з наступним читанням.
                val unadopted = adoptGuestSaves()
                // Запити незалежні: паралельно, а не десять поспіль. Перший обов'язковий збій скасовує решту.
                coroutineScope {
                    val mine = async { events.myEvents() }
                    val savedEvents = async { (saved.savedIds() + unadopted).distinct() }
                    val interests = async { adoptInterests(uid) }
                    // Черга вирішує, яку кнопку показати на деталях, тому не best-effort.
                    val queued = async { participation.waitlistIds() }
                    // Решта — доповнення: збій лишає те, що вже знали (null), а не порожнечу. Порожні
                    // факти після 504 знову питали вік, і сервер відповідав AGE_ALREADY_SET.
                    val facts = async { optional { safety?.account() } }
                    val blocked = async { optional { safety?.blocked() } }
                    val profile = async { optional { profiles?.profile(uid) } }
                    // Стрічка запитів — без неї головна лише не покаже бейджів.
                    val pending = async { optional { requests.pendingRequests() } }
                    val unread = async { optional { chat.unread() } }
                    val ratings = async { optional { participation.myRatings() } }
                    val followed = async { optional { follows?.mine() } }
                    val followFeed = async { optional { follows?.upcoming() } }
                    val result = Loaded(
                        mine.await(), savedEvents.await(), interests.await(), queued.await(),
                        facts.await(), blocked.await(), pending.await(), unread.await(), profile.await(), ratings.await(),
                        followed.await(), followFeed.await()
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
                                myRatings = result.ratings ?: previous.myRatings,
                                account = result.facts ?: previous.account,
                                profile = result.profile ?: previous.profile,
                                blocked = result.blocked ?: previous.blocked,
                                // «Стежити» натиснули, поки їхала відповідь, чи його запит ще в дорозі: сервер його не бачив.
                                follows = if (followsAtStart == followEdits && followBusy == 0) result.follows ?: previous.follows else previous.follows,
                                followEvents = result.followFeed ?: previous.followEvents,
                                followsMade = previous.followsMade,
                                savesMade = previous.savesMade
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
        val mine: List<Event>, val saved: List<String>, val interests: List<EventCategory>, val queued: List<String>,
        val facts: AccountFacts?, val blocked: List<Attendee>?, val pending: List<JoinRequest>?, val unread: List<ChatUnread>?,
        val profile: Profile?, val ratings: Map<String, Int>?, val follows: List<Follow>?, val followFeed: List<Event>?
    )

    /** Best-effort: збій (чи сервер без міграції) — null, і стан лишає попереднє. */
    private suspend fun <T> optional(block: suspend () -> T?): T? =
        try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { null }

    /**
     * Гість: закладки живуть на телефоні, а картки до них — з сервера, щоб нагадування й «Мої події» бачили свіже.
     * `event_cards_by_ids` розгортає злиту подію в живу, тож надгробок замінюється живим id; зникла й минула випадають.
     * Збій мережі — лишаємо що є.
     */
    private fun loadGuest() {
        val stored = guestSaves ?: return
        val ids = stored.ids()
        listJob?.cancel()
        if (ids.isEmpty()) return store.update { it.copy(library = it.library.copy(myEvents = emptyList(), savedIds = emptyList())) }
        listJob = scope.launch {
            try {
                val cards = liveSaved(ids)
                if (auth.session.value != null) return@launch
                stored.write(cards.map { it.id })
                store.update { it.copy(library = it.library.copy(myEvents = cards, savedIds = cards.map { e -> e.id })) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("mine") { "guest saves not refreshed: ${e.asAppError()}" }
            }
        }
    }

    /** Картки закладок, що ще попереду; минулі гостю ні до чого, а в акаунт іти не мають. */
    private suspend fun liveSaved(ids: List<String>): List<Event> {
        val now = Clock.System.now()
        return events.cards(ids).filterNot { it.hasEnded(now) }.distinctBy { it.id }
    }

    /**
     * Закладки гостя переходять в акаунт, що ввійшов першим після гостя, як і інтереси ([adoptInterests]). Повертає
     * ті, що лишились на телефоні: збій — повтор на наступному [load], а до того вони в стані разом із серверними.
     */
    private suspend fun adoptGuestSaves(): List<String> {
        val stored = guestSaves ?: return emptyList()
        val ids = stored.ids().ifEmpty { return emptyList() }
        return try {
            // Рядок із неіснуючою подією валить увесь масив, тож лише живі.
            val live = liveSaved(ids).map { it.id }
            saved.saveAll(live)
            stored.write(emptyList())
            PoruchLog.i("mine") { "${live.size} guest saves adopted" }
            emptyList()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PoruchLog.w("mine") { "guest saves not adopted: ${e.asAppError()}" }
            ids
        }
    }

    /** Закладка гостя: стан одразу, список на диску, а картки перечитуються — без них нема нагадування. */
    fun setGuestSaved(id: String, saved: Boolean) {
        setSaved(id, saved)
        guestSaves?.write(store.value.library.savedIds)
        loadGuest()
    }

    /** Закладку поставлено: платформа бачить першу й питає про сповіщення, див. [LibraryState.savesMade]. */
    fun saveMade() = store.update { it.copy(library = it.library.copy(savesMade = it.library.savesMade + 1)) }

    /** Оптимістична закладка: стан одразу, і [load], що вже в дорозі, її не затре. */
    fun setSaved(id: String, saved: Boolean) {
        savedEdits++
        store.update {
            val ids = it.library.savedIds
            it.copy(library = it.library.copy(savedIds = if (saved) (ids + id).distinct() else ids - id))
        }
    }

    /**
     * Оптимістична підписка: кнопка перемикається одразу, і [load], що вже в дорозі, її не затре. [known] — підписка
     * з усіма даними, якщо вона була: відкат відписки повертає її, а не голе ім'я.
     */
    fun setFollow(kind: FollowKind, id: String, name: String, following: Boolean, known: Follow? = null) {
        followEdits++
        store.update {
            val current = it.library.follows
            val next = when {
                !following -> current.filterNot { f -> f.kind == kind && f.targetId == id }
                current.any { f -> f.kind == kind && f.targetId == id } -> current
                else -> listOf(known ?: Follow(kind, id, name)) + current
            }
            it.copy(library = it.library.copy(follows = next))
        }
    }

    /** Екран «Ви стежите» відкрито: нове гасне одразу, і [load], що вже в дорозі, його не поверне. */
    fun followsSeen() {
        followEdits++
        store.update { it.copy(library = it.library.copy(follows = it.library.follows.map { f -> f.copy(fresh = 0) })) }
    }

    /** Підписка вдалась: платформа бачить це й питає про сповіщення, див. [LibraryState.followsMade]. */
    fun followMade() = store.update { it.copy(library = it.library.copy(followsMade = it.library.followsMade + 1)) }

    /** Запит «Стежити» пішов: до [followFinished] список із сервера не пишемо в стан. */
    fun followStarted() { followBusy++ }

    /** Запит завершився (вдало чи ні). Хто завершився останнім, той і звіряє список із сервером. */
    fun followFinished() {
        followBusy--; followEdits++
        if (followBusy == 0) refreshFollows()
    }

    /**
     * Перечитує лише підписки й стрічку з них: після «Стежити» чи відписки, без десяти запитів [load].
     * Відповідь не пишемо, якщо за цей час змінилась підписка чи акаунт або хоч один запит іще в дорозі:
     * останній із них перечитає сам.
     */
    fun refreshFollows() {
        val repository = follows ?: return
        val uid = store.value.session.userId ?: return
        followJob?.cancel()
        val edits = followEdits
        followJob = scope.launch {
            val mine = optional { repository.mine() }
            val feed = optional { repository.upcoming() }
            if (edits != followEdits || followBusy > 0 || store.value.session.userId != uid) return@launch
            store.update {
                it.copy(library = it.library.copy(
                    follows = mine ?: it.library.follows, followEvents = feed ?: it.library.followEvents
                ))
            }
        }
    }

    /** Чекає, поки доїдуть «мої». Гість нічого не вантажить, тож повертається одразу. */
    suspend fun awaitList() { listJob?.join() }

    /**
     * Узгоджує інтереси пристрою з акаунтом [uid]. Акаунт перемагає, якщо має хоч щось; порожній
     * акаунт (звичний випадок, питання ставлять до реєстрації) отримує відповіді пристрою — але
     * лише гостьові чи свої: інтереси акаунта A, що лишились на телефоні після виходу, до B не йдуть.
     */
    private suspend fun adoptInterests(uid: String): List<EventCategory> {
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
        listJob?.cancel(); detailJob?.cancel(); followJob?.cancel(); openEventId = null
        events.clearPrivateCache()
    }
}
