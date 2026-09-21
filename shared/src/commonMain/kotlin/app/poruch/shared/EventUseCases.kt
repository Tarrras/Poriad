package app.poruch.shared

import app.poruch.domain.*
import app.poruch.events.EventActions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
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
    private val reloader: Reloader
) {
    /** Повтор непевного створення має взяти той самий id, інакше опублікує другу подію. */
    private var pendingCreation: Pair<EventDraft, String>? = null

    /** Інший акаунт — чернетка вже не його. */
    fun forgetPendingCreation() {
        pendingCreation = null
    }

    fun join(id: String) = store.mutate {
        PoruchLog.i("action") { "joinEvent ${id.shortId()}" }
        // Подія з підтвердженням відповідає запитом, а не місцем, тож і повідомлення інше.
        val byRequest = (store.value.selectedEvent?.takeIf { it.id == id }
            ?: store.value.events.firstOrNull { it.id == id })?.gathering?.approvalRequired == true
        actions.join(id); reloader.changed(id)
        PoruchAnalytics.track("event_join", "by_request" to byRequest)
        store.tell(if (byRequest) AppMessage.REQUEST_SENT else AppMessage.JOINED_EVENT)
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

    fun rate(id: String, score: Int, comment: String?) = store.mutate {
        PoruchLog.i("action") { "rateEvent ${id.shortId()} score=$score" }
        participation.rate(id, score, comment?.trim()?.take(RatingRules.COMMENT_MAX)?.ifEmpty { null })
        reloader.changed(id)
        store.tell(AppMessage.RATING_SENT)
    }

    fun cancel(id: String) = store.mutate {
        PoruchLog.i("action") { "cancelEvent ${id.shortId()}" }
        actions.cancel(id); reloader.changed(id)
    }

    /**
     * Закладка змінюється оптимістично, поза [AppStore.mutate]: стан одразу, запит окремо, при
     * збої повертаємо як було й показуємо помилку.
     */
    fun toggleSaved(id: String) {
        if (!store.value.signedIn) return store.failed(AppError.SessionRequired)
        val wasSaved = store.value.isSaved(id)
        PoruchLog.i("action") { "toggleSaved ${id.shortId()} saved=${!wasSaved}" }
        store.update { it.copy(savedIds = it.savedIds.toggling(id, add = !wasSaved)) }
        store.scope.launch {
            try {
                if (wasSaved) saved.unsave(id) else saved.save(id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("action") { "toggleSaved ${id.shortId()} failed: $error" }
                store.update { it.copy(savedIds = it.savedIds.toggling(id, add = wasSaved)) }
                store.failed(error)
            }
        }
    }

    private fun List<String>.toggling(id: String, add: Boolean) =
        if (add) (this + id).distinct() else this - id

    @OptIn(ExperimentalUuidApi::class)
    fun create(draft: EventDraft) = store.mutate {
        val id = creationIdentity?.idFor(draft)
            ?: pendingCreation?.takeIf { it.first == draft }?.second
            ?: Uuid.random().toString().also { pendingCreation = draft to it }
        PoruchLog.i("action") { "createEvent ${id.shortId()} category=${draft.category} capacity=${draft.capacity}" }
        val created = actions.create(id, draft)
        pendingCreation = null; creationIdentity?.clear()
        PoruchAnalytics.track(
            "event_create",
            "category" to draft.category,
            "approval" to draft.approvalRequired
        )
        reloader.changed(created); library.select(created)
        store.update {
            it.copy(
                notice = AppNotice.Told(AppMessage.EVENT_PUBLISHED),
                completedEventId = created
            )
        }
    }

    fun update(id: String, draft: EventDraft) = store.mutate {
        PoruchLog.i("action") { "updateEvent ${id.shortId()} capacity=${draft.capacity}" }
        actions.update(id, draft); reloader.changed(id)
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
        authoring.update(
            eventId,
            EventDraft(
                event.title, event.description, event.category, event.city, event.address,
                event.latitude, event.longitude, event.startsAt, event.endsAt, event.timeZone,
                room.capacity, url, room.minAge, room.maxAge, room.approvalRequired, room.contactUrl
            )
        )
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
