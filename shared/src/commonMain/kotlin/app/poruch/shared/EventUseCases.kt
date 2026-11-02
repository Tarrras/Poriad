package app.poruch.shared

import app.poruch.domain.*
import app.poruch.events.EventActions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.time.Clock
import kotlin.time.Instant
import kotlin.time.TimeSource
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * Дії з подією від імені людини: участь, черга, закладка, створення й редагування, запити
 * на участь. Кожна йде через [AppStore.mutate] і після успіху перечитує все, чого торкнулась.
 */
internal class EventUseCases(
    private val events: EventDiscovery,
    private val saved: SavedEvents,
    private val authoring: EventAuthoring,
    private val participation: EventParticipation,
    private val requests: EventRequests,
    private val auth: AuthRepository,
    private val actions: EventActions,
    private val creationIdentity: CreationIdentityStore?,
    private val store: AppStore,
    private val library: UserLibrary,
    private val reloader: Reloader,
    private val follows: FollowUseCases? = null,
    /** Дні з закладкою, приєднанням чи доброю оцінкою: чи пора просити відгук. Null — лише після оцінки. */
    private val goodDays: SeenRequestStore? = null,
    /** Де читати файли чернетки. Порожньо в тестах; [AppGraph] через [PoruchApp] дає фоновий диспетчер. */
    private val compute: CoroutineContext = EmptyCoroutineContext
) {
    /** Повтор непевного створення має взяти той самий id, інакше опублікує другу подію. */
    private var pendingCreation: Pair<EventDraft, String>? = null

    /** Інший акаунт — чернетка вже не його. */
    fun forgetPendingCreation() {
        pendingCreation = null
    }

    fun join(id: String) = store.mutate {
        PoruchLog.i("action") { "joinEvent ${id.shortId()}" }
        // Супутник — з картки на сторінці афіші або зі своєї сторінки. Завжди за запитом.
        val fromCard = store.value.detail.companions?.any { it.id == id } == true
        val companion = fromCard || store.value.detail.event?.takeIf { it.id == id }?.gathering?.companionOf != null
        // Подія з підтвердженням відповідає запитом, а не місцем, тож і повідомлення інше.
        val byRequest = fromCard || (store.value.detail.event?.takeIf { it.id == id }
            ?: store.value.map.events.firstOrNull { it.id == id })?.gathering?.approvalRequired == true
        actions.join(id); reloader.changed(id)
        if (fromCard) library.refreshCompanions()
        PoruchAnalytics.track("event_join", "by_request" to byRequest)
        if (companion) PoruchAnalytics.track("companion_join")
        store.tell(if (byRequest) AppMessage.REQUEST_SENT else AppMessage.JOINED_EVENT)
        goodMoment()
    }

    fun joinWaitlist(id: String) = store.mutate {
        PoruchLog.i("action") { "joinWaitlist ${id.shortId()}" }
        participation.joinWaitlist(id); reloader.changed(id); store.tell(AppMessage.JOINED_WAITLIST)
        PoruchAnalytics.track("waitlist_join")
    }

    fun leaveWaitlist(id: String) = store.mutate {
        PoruchLog.i("action") { "leaveWaitlist ${id.shortId()}" }
        participation.leaveWaitlist(id); reloader.changed(id)
    }

    fun leave(id: String) = store.mutate {
        PoruchLog.i("action") { "leaveEvent ${id.shortId()}" }
        actions.leave(id); reloader.changed(id)
    }

    /**
     * Оцінка й, якщо шторка це попросила, «Стежити за організатором»: [follow] null — перемикача не було,
     * true/false — що він показував. Підписка йде після оцінки й не може її зіпсувати.
     */
    fun rate(id: String, score: Int, comment: String?, tags: List<RatingTag>, follow: Boolean? = null) = store.mutate {
        PoruchLog.i("action") { "rateEvent ${id.shortId()} score=$score tags=${tags.size} follow=$follow" }
        // Організатор — з події, що оцінюється, поки вона ще під рукою.
        val room = if (follow != null) ratedEvent(id)?.gathering else null
        participation.rate(id, score, comment?.trim()?.take(RatingRules.COMMENT_MAX)?.ifEmpty { null }, tags)
        reloader.changed(id)
        store.tell(AppMessage.RATING_SENT)
        if (score >= RatingRules.REVIEW_PROMPT_MIN) goodMoment(sure = true)
        // Підписка окремо й після: запит на неї не тримає ні оцінку, ні шторку.
        if (room != null && follow != null) follows?.afterRating(room.organizerId, room.organizerName, follow)
    }

    /**
     * Добра дія: запам'ятовуємо день і просимо відгук, коли таких днів уже [RatingRules.REVIEW_PROMPT_DAYS]. [sure] —
     * оцінка 4–5: людина сходила й задоволена, днів не чекаємо. Чи справді питати, вирішує платформа (раз на версію).
     */
    private fun goodMoment(sure: Boolean = false) {
        goodDays?.markSeen(setOf(Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date.toString()))
        if (sure || (goodDays?.seen()?.size ?: 0) >= RatingRules.REVIEW_PROMPT_DAYS) store.update { it.copy(reviewMoment = true) }
    }

    /** Подія, яку оцінюють: відкрита, зі «Моїх подій» або з завантажених карток. */
    private fun ratedEvent(id: String): Event? = store.value.let { state ->
        state.detail.event?.takeIf { it.id == id } ?: state.library.myEvents.firstOrNull { it.id == id } ?: state.cards[id]
    }

    fun cancel(id: String) = store.mutate {
        PoruchLog.i("action") { "cancelEvent ${id.shortId()}" }
        actions.cancel(id); reloader.changed(id, index = true)
    }

    /**
     * Закладка змінюється оптимістично, поза [AppStore.mutate]: стан одразу, запит окремо, при
     * збої повертаємо як було й показуємо помилку.
     */
    fun toggleSaved(id: String) {
        val wasSaved = store.value.isSaved(id)
        val guest = !store.value.signedIn
        PoruchLog.i("action") { "toggleSaved ${id.shortId()} saved=${!wasSaved} guest=$guest" }
        if (!wasSaved) {
            PoruchAnalytics.track("save", "guest" to guest)
            library.saveMade()
            goodMoment()
        }
        // Гість зберігає на телефоні, сервер дізнається після входу (docs/guest-saves.md).
        if (guest) return library.setGuestSaved(id, !wasSaved)
        library.setSaved(id, !wasSaved)
        store.scope.launch {
            try {
                if (wasSaved) saved.unsave(id) else saved.save(id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("action") { "toggleSaved ${id.shortId()} failed: $error" }
                library.setSaved(id, wasSaved)
                store.failed(error, byPerson = true)
            }
        }
    }

    /** Чернетка гостя, що чекає на вхід: після нього публікується сама ([publishPending]). */
    private var awaitingSignIn: EventDraft? = null

    /**
     * «Опублікувати». Гість проходить редактор до кінця, а вхід — тут (docs/organizers-1.5.md, «Редактор без входу»):
     * чернетку перевіряємо, як для всіх, і ставимо [AppState.publishAfterSignIn] — платформа відкриває вхід з причиною
     * `create`, а подія публікується сама після входу. Фото й відео гостя досі лише на телефоні: вантажаться з публікацією.
     */
    fun create(draft: EventDraft) = store.mutate {
        if (!store.value.signedIn) {
            actions.validate(draft)
            PoruchLog.i("action") { "createEvent waits for sign-in, media=${draft.media?.size}" }
            awaitingSignIn = draft
            PoruchAnalytics.track("auth_wall", "action" to "create")
            store.update { it.copy(publishAfterSignIn = true) }
            return@mutate
        }
        publish(draft)
    }

    /**
     * Відкладена гостем публікація — після входу ([UserLibrary.afterAccountLoad]) чи галочки віку. Новий акаунт без віку
     * ще на кроці галочки: чекаємо на неї. Сервер не знайшов віку, хоч ми його не питали (факти акаунта не прочитались), —
     * питаємо галочку тепер ([SessionState.askBirthDate]). Повтор — той самий id чернетки.
     */
    fun publishPending() {
        if (awaitingSignIn == null || !store.value.signedIn) return
        store.mutate(queued = true) {
            val draft = awaitingSignIn ?: return@mutate
            if (!store.value.signedIn || store.value.session.askBirthDate) return@mutate
            try {
                publish(draft, afterSignIn = true)
            } catch (e: AppFailure) {
                if (e.error == AppError.AgeRequired) {
                    store.update { it.copy(session = it.session.copy(askBirthDate = true)) }
                    return@mutate
                }
                dropPendingPublish()
                throw e
            }
        }
    }

    /**
     * Вхід, відкритий через «Опублікувати», закрили. Гість — лишається в редакторі з тією самою чернеткою, і сама публікація
     * вже не чекає; так само, якщо закрили крок галочки. Уже ввійшов і віку не питаємо — публікація саме йде, нічого не чіпаємо.
     */
    fun cancelPendingPublish() {
        if (store.value.signedIn && !store.value.session.askBirthDate) return
        dropPendingPublish()
    }

    /** Вихід з акаунта чи закритий вхід: чернетка гостя більше не публікується сама. */
    fun dropPendingPublish() {
        awaitingSignIn = null
        store.update { it.copy(publishAfterSignIn = false) }
    }

    @OptIn(ExperimentalUuidApi::class)
    private suspend fun publish(draft: EventDraft, afterSignIn: Boolean = false) {
        val id = creationIdentity?.idFor(draft)
            ?: pendingCreation?.takeIf { it.first == draft }?.second
            ?: Uuid.random().toString().also { pendingCreation = draft to it }
        PoruchLog.i("action") { "createEvent ${id.shortId()} category=${draft.category?.key} capacity=${draft.capacity} media=${draft.media?.size}" }
        val created = try {
            actions.create(id, draft)
        } catch (e: Exception) {
            // Останній крок воронки: без цього «дійшов до кінця й не опублікував» не відрізнити від «передумав». Гість без
            // віку — не відмова, а крок галочки попереду.
            val error = (e as? AppFailure)?.error ?: AppError.ServiceUnavailable
            if (e !is CancellationException && !(afterSignIn && error == AppError.AgeRequired)) {
                PoruchAnalytics.track("create_failed", "reason" to error::class.simpleName)
            }
            throw e
        }
        PoruchAnalytics.track(
            "event_create",
            "category" to draft.category?.key,
            "approval" to draft.approvalRequired
        )
        // Подія вже опублікована: файли далі, і збій котрогось її не скасовує. Ключ чернетки живе до кінця цього кроку:
        // перезапуск посеред вивантаження повторить `create_event` з тим самим id, і сервер віддасть ту саму подію.
        val failed = attach(created, draft)?.let { attached ->
            // Жоден файл не ліг — `create_event` уже поставив `[]`, і другий запит нічого б не змінив.
            if (attached.uploaded.isEmpty()) attached.failed
            else saveMedia(attached) { authoring.update(created, attached.draft) }
        } ?: 0
        pendingCreation = null; creationIdentity?.clear()
        awaitingSignIn = null
        reloader.changed(created, index = true); library.select(created)
        store.update {
            it.copy(
                notice = if (failed == 0) AppNotice.Told(AppMessage.EVENT_PUBLISHED) else AppNotice.MediaFailed(failed),
                completedEventId = created,
                published = published(created, draft),
                publishAfterSignIn = false
            )
        }
    }

    /** «Подію створено» з чернетки: картка події ще їде, а екран потрібен одразу. */
    private fun published(id: String, draft: EventDraft): PublishedEvent {
        val place = listOf(draft.address.trim(), draft.city.trim()).filter { it.isNotEmpty() }.distinct()
            .let { parts -> if (parts.size == 2 && parts[1] in parts[0]) parts.take(1) else parts }.joinToString(", ")
        return PublishedEvent(
            id = id, link = EventLinks.url(id),
            post = ThreadsPost.text(id, TitleRules.display(draft.title.trim()), draft.startsAt, draft.timeZone, draft.address.trim(), null, draft.description, draft.price),
            // Звичайна подія свого організатора: саме вона щойно опублікована, тож завжди анонс.
            shareMode = ShareMode.PROMOTE,
            title = draft.title.trim(),
            startMillis = Instant.parse(draft.startsAt).toEpochMilliseconds(),
            endMillis = Instant.parse(draft.endsAt).toEpochMilliseconds(),
            timeZone = draft.timeZone, location = place
        )
    }

    /**
     * `update_event` з файлами, що вже в теці події. Повертає, скільки файлів подія так і не взяла. Сервер відмовив — файли
     * прибираємо; відповіді не дочекались (мережа, скасування) — лишаємо: сервер міг їх зберегти.
     */
    private suspend fun saveMedia(attached: Attached, save: suspend () -> Unit): Int = try {
        save(); attached.failed
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        val error = e.asAppError()
        PoruchLog.w("action") { "media not saved: $error" }
        if (error != AppError.Network) discard(attached.uploaded)
        attached.total
    }

    /**
     * «Вставити анонс»: поля з тексту, і гостю (вхід — лише на «Опублікувати»). Не розібрали — запасні назва й опис з
     * тексту ([AnnouncementRules.fallback]) і причина: банер «Текст уже в описі — допишіть назву» показує платформа.
     * Не через [AppStore.mutate]: це не дія над подією, і чернетку з редактора вона не блокує.
     */
    suspend fun announce(text: String, city: String, timeZone: String): AnnouncementFill {
        // Межа не різатиме емодзі навпіл: непарний сурогат функція викинула б, а запасний опис — ні.
        val body = AnnouncementRules.clean(text).trim().take(AnnouncementRules.TEXT_MAX).let { if (it.lastOrNull()?.isHighSurrogate() == true) it.dropLast(1) else it }
        if (body.isEmpty()) return AnnouncementFill(null, null, failure = AnnounceFailure.ERROR)
        val zone = runCatching { TimeZone.of(timeZone) }.getOrDefault(TimeZone.currentSystemDefault())
        val started = TimeSource.Monotonic.markNow()
        return try {
            authoring.announcement(body, city.trim(), Clock.System.now().toLocalDateTime(zone).date.toString(), zone.id).also {
                PoruchAnalytics.track(
                    "announce_fill", "filled" to it.filled.joinToString(",") { field -> field.key },
                    "ms" to started.elapsedNow().inWholeMilliseconds
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val failure = when (e.asAppError()) {
                AppError.TooManyAttempts -> AnnounceFailure.LIMIT
                AppError.Network -> AnnounceFailure.NETWORK
                else -> AnnounceFailure.ERROR
            }
            PoruchLog.w("action") { "announcement not parsed: ${failure.key}" }
            PoruchAnalytics.track("announce_failed", "reason" to failure.key)
            AnnouncementRules.fallback(body, failure)
        }
    }

    /** Нові файли вже в теці події: [draft] — з ними як [DraftMedia.Remote]; [uploaded] — що прибрати, якщо подія їх не візьме. */
    private class Attached(val draft: EventDraft, val uploaded: List<String>, val failed: Int, val total: Int)

    /**
     * Нові фото й відео чернетки — у теку наявної події [id], по черзі, з «Завантажуємо N з M» ([AppState.mediaUpload]).
     * Файл, що не вантажиться, пропускаємо: подія лишається без нього, а [Attached.failed] каже скільки. Null — нового нема.
     */
    private suspend fun attach(id: String, draft: EventDraft): Attached? {
        val items = draft.media ?: return null
        val total = items.count { it !is DraftMedia.Remote }
        if (total == 0) return null
        val uploaded = mutableListOf<String>()
        var current = 0
        var failed = 0
        val media = try {
            items.mapNotNull { item ->
                if (item is DraftMedia.Remote) return@mapNotNull item
                current++
                store.update { it.copy(mediaUpload = MediaUpload(current, total)) }
                try {
                    DraftMedia.Remote(upload(id, item).also { uploaded += listOfNotNull(it.url, it.poster) })
                } catch (e: CancellationException) {
                    discard(uploaded); throw e
                } catch (e: Exception) {
                    PoruchLog.w("action") { "media ${item.kind.key} $current/$total not added to ${id.shortId()}: ${e.asAppError()}" }
                    failed++
                    null
                }
            }
        } finally {
            store.update { it.copy(mediaUpload = null) }
        }
        return Attached(draft.copy(media = media), uploaded, failed, total)
    }

    /** Один файл у теку події [id]. Відео — спершу постер: без нього сервер відео не прийме. */
    private suspend fun upload(id: String, item: DraftMedia): EventMedia = when (item) {
        is DraftMedia.Remote -> item.media
        is DraftMedia.Copied -> {
            val poster = item.media.poster?.takeIf { item.kind == MediaKind.VIDEO }?.let { authoring.copyMedia(it, id) }
            EventMedia(item.kind, discardingOnFailure(poster) { authoring.copyMedia(item.media.url, id) }, poster)
        }
        is DraftMedia.Local -> when (item.kind) {
            MediaKind.PHOTO -> EventMedia(MediaKind.PHOTO, authoring.uploadImage(id, read(item.bytes), JPEG))
            MediaKind.VIDEO -> {
                val poster = authoring.uploadImage(id, read(item.poster ?: fail(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)))), JPEG)
                EventMedia(MediaKind.VIDEO, discardingOnFailure(poster) { authoring.uploadVideo(id, read(item.bytes)) }, poster)
            }
        }
    }

    /** Файл з диска платформи — поза головним потоком: відео до 8 МБ, а на iOS ще й копія в `KotlinByteArray`. */
    private suspend fun read(bytes: MediaBytes): ByteArray = withContext(compute) { bytes.read() }

    /**
     * Медіа правки проти медіа події на сервері (`event_details`, щойно прочитаних): що зберегти і які файли видалити.
     * - Видаляємо лише файли, з якими редактор відкрився ([EventDraft.mediaBase]) і яких у чернетці вже нема: те, чого
     *   редактор не бачив, не зникне.
     * - Файли сервера, яких редактор не бачив (додали в кабінеті, поки він був відкритий), — у кінець. Редактор з картки
     *   (бази нема) не бачив нічого: серверні медіа лишаються першими, нове — за ними.
     * - Файли з чернетки, яких на сервері вже нема (прибрали в кабінеті), викидаємо: інакше лишилось би мертве посилання.
     *   Крім старої обкладинки без медіа — вона стає першим фото.
     * Порівнюємо адреси й постери: обкладинка події з самими відео — постер першого, і редактор з картки не має її
     * дублювати фото. Деталі не прочитались чи файлів стало б понад 5 — помилка до вивантаження, без запису.
     */
    private suspend fun reconcile(id: String, draft: EventDraft, media: List<DraftMedia>): Pair<EventDraft, List<String>> {
        val full = events.details(id) ?: fail(AppError.EventUnavailable)
        val server = full.media.takeIf { full.mediaLoaded }.orEmpty()
        fun files(m: EventMedia) = listOfNotNull(m.url, m.poster)
        val onServer = server.flatMap(::files).toSet() + listOfNotNull(full.imageUrl)
        val base = draft.mediaBase
        val alive = media.filter { it !is DraftMedia.Remote || it.media.url in onServer }
        val (merged, removed) = if (base == null) {
            val known = server.flatMap(::files).toSet()
            server.map { DraftMedia.Remote(it) } + alive.filterNot { it is DraftMedia.Remote && files(it.media).any { f -> f in known } } to emptyList()
        } else {
            val kept = alive.mapNotNull { (it as? DraftMedia.Remote)?.media }.flatMap(::files).toSet()
            val unseen = server.filter { m -> files(m).none { it in base || it in kept } }
            alive + unseen.map { DraftMedia.Remote(it) } to (onServer intersect base).filterNot { it in kept }
        }
        // До вивантаження: інакше файли лягли б у теку, а `update_event` відмовив би.
        if (merged.size > MediaRules.MAX_ITEMS) fail(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)))
        // Обкладинку з медіа ставить сервер; запасна — лише для редактора з картки, коли медіа без фото й відео.
        return draft.copy(media = merged, imageUrl = if (base == null) full.imageUrl else null) to removed
    }

    /** Постер без свого відео нікому не потрібен. */
    private suspend fun <T> discardingOnFailure(url: String?, block: suspend () -> T): T = try {
        block()
    } catch (e: Exception) {
        discard(listOfNotNull(url)); throw e
    }

    /**
     * Файли, які подія так і не взяла: інакше лишились би сиротами за прямим посиланням. `NonCancellable` — прибирати
     * треба й тоді, коли дію скасовано. Збій — лише запис у журнал.
     */
    private suspend fun discard(urls: List<String>) = withContext(NonCancellable) {
        urls.forEach { url ->
            try { authoring.deleteImage(url) } catch (e: Exception) { PoruchLog.w("action") { "orphan file not removed: ${e.asAppError()}" } }
        }
    }

    /**
     * Супутник «Йдемо разом» на відкриту афішу [parentId]. Після успіху — [AppState.createdCompanion]:
     * платформа відкриває «Поділитися», бо без поширення пошук компанії нікого не знайде.
     */
    fun createCompanion(parentId: String, meetAt: String, note: String?, capacity: Int) = store.mutate {
        val parent = store.value.detail.event?.takeIf { it.id == parentId } ?: fail(AppError.EventUnavailable)
        val invalid = CompanionRules.validate(parent.startsAt, meetAt, note, capacity, Clock.System.now())
        if (invalid.isNotEmpty()) fail(AppError.InvalidDraft(invalid))
        PoruchLog.i("action") { "createCompanion for ${parentId.shortId()} capacity=$capacity" }
        val id = authoring.createCompanion(parentId, meetAt, note?.trim()?.ifEmpty { null }, capacity)
        PoruchAnalytics.track("companion_create", "category" to parent.category.key, "capacity" to capacity)
        reloader.changed(id, index = true); library.refreshCompanions()
        store.update { it.copy(createdCompanion = id) }
    }

    /**
     * «Хочу піти з компанією» на відкриту афішу (docs/return-hooks.md). Гість — спершу вхід: платформа відкриває його з
     * причиною «компанія», а намір ставить [UserLibrary.consumePendingCompany] після входу.
     */
    fun wantCompany() {
        val event = store.value.detail.event ?: return
        if (!store.value.signedIn) return store.update { it.copy(pendingCompany = event.id) }
        setCompanyIntent(true)
    }

    fun setCompanyIntent(on: Boolean) = store.mutate {
        val event = store.value.detail.event ?: fail(AppError.EventUnavailable)
        if (on && !CompanyRules.canIntend(event, Clock.System.now())) fail(AppError.EventUnavailable)
        PoruchLog.i("action") { "companyIntent ${event.id.shortId()} on=$on" }
        val others = participation.setCompanyIntent(event.id, on)
        PoruchAnalytics.track("company_intent", "on" to on, "others" to others)
        library.refreshCompany()
    }

    /** «Піти разом» з [userId]. Збіг — сервер уже зібрав супутник: [AppState.matchedCompanion], там чат. */
    fun sayCompanyYes(userId: String) = store.mutate {
        val event = store.value.detail.event ?: fail(AppError.EventUnavailable)
        PoruchLog.i("action") { "companyYes ${event.id.shortId()}" }
        val match = participation.companyYes(event.id, userId)
        PoruchAnalytics.track("company_yes", "matched" to match.matched)
        library.refreshCompany()
        val companion = match.companionId?.takeIf { match.matched } ?: return@mutate
        PoruchAnalytics.track("company_match")
        reloader.changed(companion, index = true); library.refreshCompanions()
        store.update { it.copy(matchedCompanion = companion) }
    }

    /** Новий час збору (R7б) чи відповідь на питання після переносу афіші (R7а). */
    fun moveCompanion(id: String, meetAt: String) = store.mutate {
        val parent = store.value.detail.event?.takeIf { it.id == id }?.gathering?.companionOf ?: fail(AppError.EventUnavailable)
        val start = parent.startsAt ?: fail(AppError.EventUnavailable)
        if (!CompanionRules.canMoveTo(start, meetAt, Clock.System.now())) fail(AppError.InvalidDraft(listOf(DraftField.STARTS_AT)))
        PoruchLog.i("action") { "moveCompanion ${id.shortId()}" }
        authoring.moveCompanion(id, meetAt)
        reloader.changed(id, index = true); library.refreshCompanions()
        store.update { it.copy(notice = AppNotice.Told(AppMessage.CHANGES_SAVED)) }
    }

    /**
     * Правка: нові фото й відео вантажаться до збереження, і все йде одним `update_event`. Медіа звіряємо з повними
     * деталями ([reconcile]); файли, які з події справді прибрали, після збереження видаляємо зі сховища: інакше вони й далі
     * відкривались би за прямим посиланням.
     */
    fun update(id: String, draft: EventDraft) = store.mutate {
        PoruchLog.i("action") { "updateEvent ${id.shortId()} capacity=${draft.capacity} media=${draft.media?.size}" }
        // До файлів: відмова чернетки після завантаження лишила б їх сиротами.
        actions.validate(draft)
        val (reconciled, removed) = draft.media?.let { reconcile(id, draft, it) } ?: (draft to emptyList())
        val attached = attach(id, reconciled)
        try {
            actions.update(id, attached?.draft ?: reconciled)
        } catch (e: Exception) {
            // Відповіді не дочекались — сервер міг зберегти: тоді ці файли вже в події.
            if (e !is CancellationException && e.asAppError() != AppError.Network) discard(attached?.uploaded.orEmpty())
            throw e
        }
        discard(removed)
        reloader.changed(id, index = true)
        val failed = attached?.failed ?: 0
        store.update {
            it.copy(
                notice = if (failed == 0) AppNotice.Told(AppMessage.CHANGES_SAVED) else AppNotice.MediaFailed(failed),
                completedEventId = id
            )
        }
    }

    /**
     * Стара обкладинка з деталей (до 1.5). Подія з медіа: нове фото стає першим, тож і обкладинкою; без медіа — лише
     * обкладинка, як було. Хвиля 2 цей вибір прибирає.
     */
    fun uploadImage(eventId: String, bytes: ByteArray, contentType: String) = store.mutate {
        val event = events.details(eventId) ?: fail(AppError.EventUnavailable)
        // Фото має лише кімната: в афіші нема власника.
        val room = event.gathering ?: fail(AppError.NotOwner)
        if (room.organizerId != auth.session.value?.userId) fail(AppError.NotOwner)
        // До вивантаження: шостому файлу місця нема, а мовчки викинути останній — гірше за відмову.
        if (event.media.size >= MediaRules.MAX_ITEMS) fail(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)))
        val url = authoring.uploadImage(eventId, bytes, contentType)
        try {
            authoring.update(
                eventId,
                EventDraft(
                    event.title, event.description, event.category, event.city, event.address,
                    event.latitude, event.longitude, event.startsAt, event.endsAt, event.timeZone,
                    room.capacity, url, room.minAge, room.maxAge, room.approvalRequired, room.contactUrl,
                    event.media.takeIf { it.isNotEmpty() }?.let { (listOf(EventMedia(MediaKind.PHOTO, url)) + it).map { m -> DraftMedia.Remote(m) } }
                )
            )
        } catch (e: Exception) {
            // Подія фото не отримала: файл у Storage лишився б сиротою, видимою за прямим посиланням.
            if (e !is CancellationException && e.asAppError() != AppError.Network) discard(listOf(url))
            throw e
        }
        reloader.changed(eventId); store.tell(AppMessage.PHOTO_ADDED)
    }

    fun approveMember(eventId: String, userId: String) = store.mutate {
        PoruchLog.i("safety") { "approve ${userId.shortId()} for ${eventId.shortId()}" }
        requests.approveMember(eventId, userId); reloader.changed(eventId)
    }

    fun declineMember(eventId: String, userId: String) = store.mutate {
        PoruchLog.i("safety") { "decline ${userId.shortId()} for ${eventId.shortId()}" }
        requests.declineMember(eventId, userId); reloader.changed(eventId)
    }

    private companion object {
        /** Фото й постери платформи вже перекодували в JPEG без метаданих (`pickedJPEG`, `PhotoPicker`). */
        const val JPEG = "image/jpeg"
    }
}
