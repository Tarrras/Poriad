package app.poruch.shared

import app.poruch.domain.*
import app.poruch.events.EventActions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.time.Clock
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
    private val goodDays: SeenRequestStore? = null
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

    @OptIn(ExperimentalUuidApi::class)
    fun create(draft: EventDraft) = store.mutate {
        val id = creationIdentity?.idFor(draft)
            ?: pendingCreation?.takeIf { it.first == draft }?.second
            ?: Uuid.random().toString().also { pendingCreation = draft to it }
        PoruchLog.i("action") { "createEvent ${id.shortId()} category=${draft.category?.key} capacity=${draft.capacity}" }
        val created = try {
            actions.create(id, draft)
        } catch (e: Exception) {
            // Останній крок воронки: без цього «дійшов до кінця й не опублікував» не відрізнити від «передумав».
            if (e !is CancellationException) PoruchAnalytics.track("create_failed", "reason" to ((e as? AppFailure)?.error ?: AppError.ServiceUnavailable)::class.simpleName)
            throw e
        }
        pendingCreation = null; creationIdentity?.clear()
        PoruchAnalytics.track(
            "event_create",
            "category" to draft.category?.key,
            "approval" to draft.approvalRequired
        )
        reloader.changed(created, index = true); library.select(created)
        store.update {
            it.copy(
                notice = AppNotice.Told(AppMessage.EVENT_PUBLISHED),
                completedEventId = created
            )
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

    fun update(id: String, draft: EventDraft) = store.mutate {
        PoruchLog.i("action") { "updateEvent ${id.shortId()} capacity=${draft.capacity}" }
        actions.update(id, draft); reloader.changed(id, index = true)
        store.update {
            it.copy(
                notice = AppNotice.Told(AppMessage.CHANGES_SAVED),
                completedEventId = id
            )
        }
    }

    fun uploadImage(eventId: String, bytes: ByteArray, contentType: String) = store.mutate {
        val event = events.details(eventId) ?: fail(AppError.EventUnavailable)
        // Фото має лише кімната: в афіші нема власника.
        val room = event.gathering ?: fail(AppError.NotOwner)
        if (room.organizerId != auth.session.value?.userId) fail(AppError.NotOwner)
        val url = authoring.uploadImage(eventId, bytes, contentType)
        try {
            authoring.update(
                eventId,
                EventDraft(
                    event.title, event.description, event.category, event.city, event.address,
                    event.latitude, event.longitude, event.startsAt, event.endsAt, event.timeZone,
                    room.capacity, url, room.minAge, room.maxAge, room.approvalRequired, room.contactUrl
                )
            )
        } catch (e: Exception) {
            // Подія фото не отримала: файл у Storage лишився б сиротою, видимою за прямим посиланням.
            // `NonCancellable`, бо прибирати треба і тоді, коли дію скасовано.
            withContext(NonCancellable) {
                try { authoring.deleteImage(url) } catch (cleanup: Exception) { PoruchLog.w("action") { "orphan photo not removed: ${cleanup.asAppError()}" } }
            }
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
}
