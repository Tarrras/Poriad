package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * «Стежити» на закладі, організаторі й артисті (docs/follows.md). Кнопка перемикається одразу, а запит іде
 * окремо, як у закладки: при збої повертаємо як було й кажемо про помилку. Заклад і організатор — лише з акаунтом:
 * гостя ведемо на вхід, як у `join`. За артистом гість стежить без акаунта — радар (docs/artist-radar.md).
 */
internal class FollowUseCases(
    private val follows: Follows?,
    private val events: EventDiscovery,
    private val store: AppStore,
    private val library: UserLibrary,
    private val discovery: DiscoveryEngine,
    private val guestArtists: GuestArtistStore? = null
) {
    /** Запити на сервер — по черзі: швидкі «Стежити» і «Не стежити» не мають розминутись на дорозі. */
    private val serial = Mutex()

    /** [from] — звідки «Стежити» для аналітики: `hint`, `picker`; null — кнопка на екрані. */
    fun set(kind: FollowKind, targetId: String, name: String, following: Boolean, from: String? = null) {
        if (!store.value.signedIn) {
            if (kind == FollowKind.ARTIST) return setGuestArtist(targetId, name, following, from)
            return store.failed(AppError.SessionRequired, byPerson = true)
        }
        val repository = follows ?: return store.failed(AppError.ServiceUnavailable, byPerson = true)
        if (store.value.isFollowing(kind, targetId) == following) return
        change(repository, kind, targetId, name, following, report = true, from = from)
    }

    /**
     * Артист гостя: стан одразу, список на телефоні. Сервер дізнається від [PushSync] разом із токеном пуша, а після входу
     * артисти переїжджають в акаунт ([UserLibrary.load]).
     */
    private fun setGuestArtist(artistId: String, name: String, following: Boolean, from: String?) {
        if (store.value.isFollowing(FollowKind.ARTIST, artistId) == following) return
        PoruchLog.i("action") { "guest follow artist ${artistId.shortId()} on=$following" }
        library.setFollow(FollowKind.ARTIST, artistId, name, following)
        guestArtists?.saveArtists(store.value.library.follows.filter { it.kind == FollowKind.ARTIST }.map { GuestArtist(it.targetId, it.name) })
        if (!following) return
        // Платформа бачить першу підписку й питає дозвіл на сповіщення: радар без пушів марний.
        library.followMade()
        PoruchAnalytics.track("follow", "target" to FollowKind.ARTIST.key, "from" to (from ?: "artist"), "guest" to true)
    }

    /**
     * Підписка з шторки оцінки. Оцінку вже надіслано, і збій підписки її не псує: кнопка просто повертається як була,
     * без помилки для людини.
     */
    fun afterRating(organizerId: String, name: String, following: Boolean) {
        val repository = follows ?: return
        if (!store.value.signedIn || store.value.isFollowing(FollowKind.ORGANIZER, organizerId) == following) return
        change(repository, FollowKind.ORGANIZER, organizerId, name, following, report = false)
    }

    private fun change(
        repository: Follows, kind: FollowKind, targetId: String, name: String, following: Boolean, report: Boolean, from: String? = null
    ) {
        PoruchLog.i("action") { "follow ${kind.key} ${targetId.shortId()} on=$following" }
        val uid = store.value.session.userId
        // Що було: відкат відписки повертає підписку з її даними (місто, координати, фото), а не голе ім'я.
        val before = store.value.library.follows.firstOrNull { it.kind == kind && it.targetId == targetId }
        library.setFollow(kind, targetId, name, following)
        library.followStarted()
        store.scope.launch {
            try {
                serial.withLock { send(repository, kind, targetId, following, from) }
                if (following && store.value.session.userId == uid) library.followMade()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("action") { "follow ${kind.key} failed: $error" }
                // Інший акаунт уже бачить свій стан: чужий збій йому нічого не каже.
                if (store.value.session.userId == uid) {
                    // Назад лише якщо з того часу ніхто не перемкнув: інакше відкотили б чужу зміну.
                    if (store.value.isFollowing(kind, targetId) == following) library.setFollow(kind, targetId, name, !following, before)
                    if (report) store.failed(error, byPerson = true)
                }
            } finally {
                library.followFinished()
            }
        }
    }

    /**
     * Екран «Ви стежите» відкрито: лічильник нового гасне одразу, сервер дізнається окремо. Збій нічого не каже людині:
     * [UserLibrary.followFinished] перечитає підписки, і непереглянуте лишиться новим до наступного разу.
     */
    fun seen() {
        val repository = follows ?: return
        if (!store.value.signedIn || store.value.library.newFollowEvents == 0) return
        library.followsSeen()
        library.followStarted()
        store.scope.launch {
            try {
                serial.withLock { repository.seen() }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("action") { "follows seen failed: ${e.asAppError()}" }
            } finally {
                library.followFinished()
            }
        }
    }

    private suspend fun send(repository: Follows, kind: FollowKind, targetId: String, following: Boolean, from: String?) {
        if (following) {
            repository.follow(kind, targetId)
            // Метрика лише про успішну підписку: чи є на що повертати людей (docs/analytics.md).
            if (from != null) PoruchAnalytics.track("follow", "target" to kind.key, "from" to from)
            else PoruchAnalytics.track("follow", "target" to kind.key)
        } else repository.unfollow(kind, targetId)
    }

    /**
     * «Ваші артисти» (docs/artist-radar.md): перечитуємо, коли змінився список артистів чи місто. Збій лишає що було:
     * секція тоді покаже імена з підписок без дат.
     */
    fun startRadar() {
        store.scope.launch {
            store.state.map { s -> s.library.follows.filter { it.kind == FollowKind.ARTIST }.map { it.targetId }.sorted() to radarCity(s) }
                .distinctUntilChanged()
                .collectLatest { (ids, city) ->
                    if (ids.isEmpty()) return@collectLatest store.update { it.copy(radar = emptyList()) }
                    try {
                        val rows = events.artistRadar(ids, city)
                        store.update { it.copy(radar = rows) }
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        PoruchLog.w("follows") { "radar not loaded: ${e.asAppError()}" }
                    }
                }
        }
    }

    /** «За ким стежити?»: хто їде в місто людини. Своє місце на мапі чи збій — порожньо, шторка скаже, що анонсів нема. */
    fun loadPopular() {
        val city = radarCity(store.value) ?: return store.update { it.copy(popularArtists = emptyList()) }
        store.scope.launch {
            val list = try {
                events.popularArtists(city)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("follows") { "popular artists not loaded: ${e.asAppError()}" }
                emptyList()
            }
            store.update { it.copy(popularArtists = list) }
        }
    }

    /**
     * Тап по пушу про кілька подій закладу: мапа переходить до нього й відкриває його стос. Заклад беремо з
     * підписок, а коли їх ще не завантажено (холодний старт) — з карток його подій.
     */
    fun openPlace(placeId: String) {
        store.scope.launch {
            val known = store.value.library.follows.firstOrNull { it.kind == FollowKind.PLACE && it.targetId == placeId }?.place
            val place = known ?: try {
                placeFrom(placeId, events.placeEvents(placeId))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("action") { "open place failed: ${e.asAppError()}" }
                null
            }
            if (place != null) discovery.focusPlace(place) else store.failed(AppError.EventUnavailable)
        }
    }

    private var artistJob: Job? = null

    /**
     * Екран артиста в [AppState.artist]: що знаємо (з пошуку, підписок) показуємо одразу, події їдуть окремо. Лише за [artistId]
     * (пуш) ім'я й вид беремо з підписок, а коли їх нема — з карток подій, де артист названий.
     */
    fun openArtist(artistId: String, name: String? = null, kind: ArtistKind? = null) {
        artistJob?.cancel()
        val known = store.value.library.follows.firstOrNull { it.kind == FollowKind.ARTIST && it.targetId == artistId }
        PoruchLog.i("action") { "open artist ${artistId.shortId()}" }
        store.update {
            it.copy(artist = ArtistState(artistId, name ?: known?.name.orEmpty(), kind ?: known?.artistKind))
        }
        artistJob = store.scope.launch {
            try {
                val cards = events.artistEvents(artistId).foldedRuns()
                val named = cards.firstNotNullOfOrNull { card -> card.artists.firstOrNull { it.id == artistId } }
                store.update { state ->
                    state.artist?.takeIf { it.id == artistId }?.let {
                        state.copy(artist = it.copy(
                            name = it.name.ifBlank { named?.name.orEmpty() }, kind = it.kind ?: named?.kind,
                            events = cards, loading = false
                        ))
                    } ?: state
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("action") { "open artist failed: ${e.asAppError()}" }
                store.update { state -> state.artist?.takeIf { it.id == artistId }?.let { state.copy(artist = it.copy(loading = false)) } ?: state }
                store.failed(e.asAppError())
            }
        }
    }

    fun closeArtist() {
        artistJob?.cancel()
        if (store.value.artist != null) store.update { it.copy(artist = null) }
    }

    /**
     * Прокат — одна картка, як на мапі й головній: інакше три сеанси однієї вистави стоять трьома рядками, а «Підписки»
     * рахують її однією подією. Спершу дублі між продавцями, потім прокат (порядок обов'язковий, див. [EventSeries]).
     */
    private fun List<Event>.foldedRuns(): List<Event> {
        val byId = associateBy { it.id }
        return EventSeries.fold(DuplicateEvents.fold(map { it.asIndexEntry() })).mapNotNull { entry ->
            byId[entry.id]?.copy(sessions = entry.sessions)
        }
    }

    private fun placeFrom(placeId: String, cards: List<Event>): Place? =
        cards.firstOrNull { it.placeId == placeId }?.let {
            Place(placeId, it.placeName ?: it.placeLabel, it.city, it.address, it.latitude, it.longitude, cards.size)
        }
}

/** Місто радару: обране з п'яти міст афіші; своє місце на мапі — null (сервер тоді не фільтрує за містом). */
internal fun radarCity(state: AppState): String? =
    state.city.name.takeIf { name -> !state.city.custom && HomeLocation.covered.any { it.city == name } }
