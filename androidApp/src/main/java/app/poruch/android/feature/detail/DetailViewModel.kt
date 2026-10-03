package app.poruch.android.feature.detail

import app.poruch.android.mvi.MviViewModel
import app.poruch.android.platform.NotificationPermission
import app.poruch.domain.Event
import app.poruch.domain.FollowKind
import app.poruch.domain.EventIndexEntry
import app.poruch.domain.EventSession
import app.poruch.domain.RatingRules
import app.poruch.shared.PlaceEvents
import app.poruch.shared.PoruchApp
import kotlin.time.Clock

class DetailViewModel(
    private val app: PoruchApp,
    private val notifications: NotificationPermission,
    private val openedId: String
) :
    MviViewModel<DetailState, DetailIntent, DetailEffect>(DetailState(sessionId = openedId)) {

    /**
     * Сеанс на екрані. Карусель дат перемикає його, і всі дії (збереження, участь, скарга, мапа)
     * ідуть на нього. Ключ моделі лишається [openedId], щоб не губити прокрутку й карусель.
     */
    private var eventId = openedId

    /** Дата, обрана в каруселі, чиєї картки ще нема. Стане обраною, коли картка приїде; до того дії йдуть на попередню. */
    private var pendingId: String? = null

    /**
     * Перше приєднання — природний момент увімкнути нагадування. Той, хто вимкнув їх у профілі, дозвіл
     * системи вже має, і сюди не потрапляє: його вибір лишається.
     */
    private fun offerReminders() {
        if (app.state.value.remindersEnabled || notifications.granted()) return
        send(DetailEffect.AskNotificationPermission)
    }

    /** Картка, з якою відкрили екран. Карусель будується від неї: скасованого вечора в індексі нема. */
    private var anchor: Event? = null

    // Не `sessions`: у згортці нижче отримувач — DetailState, і те саме ім'я читало б старий стан.
    private var carousel: List<EventSession> = emptyList()
    private var nearby: List<EventIndexEntry> = emptyList()
    /** Картку вже показували: порожній слот далі — не завантаження, а інший екран деталей поверх. */
    private var shown = false
    private var carouselFrom: Pair<Event, List<EventIndexEntry>>? = null
    /** Події закладу, з яких порахували [nearby]: приїхали — перераховуємо «Ще в цьому місці». */
    private var nearbyFrom: PlaceEvents? = null
    /** На кого скарга з картки: картка вже закрита, коли людина обирає причину. */
    private var reportedUser: String? = null

    init {
        // openEvent, а не selectEvent: лише цей екран показує місця й членство. Тут, а не з
        // композиції: модель переживає поворот, запит іде один раз.
        app.openEvent(openedId)
        observe(app) { shared ->
            if (pendingId != null && shared.detail.event?.id == pendingId) {
                eventId = pendingId!!
                pendingId = null
            }
            val event = shared.detail.event?.takeIf { it.id == eventId }
            if (event != null && event.id == openedId) anchor = event
            // Перебудова лише при зміні картки або індексу: пошук прокату проходить увесь індекс.
            val source = anchor
            val from = carouselFrom
            if (source != null && (from == null || from.first !== source || from.second !== shared.map.index)) {
                carousel = app.sessionsOf(source)
                nearby = app.othersAt(source)
                carouselFrom = source to shared.map.index
                nearbyFrom = shared.detail.placeEvents
            } else if (source != null && nearbyFrom !== shared.detail.placeEvents) {
                nearby = app.othersAt(source)
                nearbyFrom = shared.detail.placeEvents
            }
            if (event != null) shown = true
            // Супутник створено: «Поділитися» один раз, прапорець гасимо в сторі.
            shared.createdCompanion?.let { created ->
                if (event != null) { app.clearCreatedCompanion(); send(DetailEffect.ShareCompanion(event, created)) }
            }
            val now = Clock.System.now()
            copy(
                event = event,
                sessionId = eventId,
                // Скасування відоме з картки, навіть якщо карусель знала дату опублікованою.
                sessions = if (event?.isCancelled == true) {
                    carousel.map { if (it.id == event.id) it.copy(cancelled = true) else it }
                } else carousel,
                sessionStarted = event != null && carousel.size > 1 && !event.isMultiDay &&
                        event.hasStarted(now),
                othersHere = nearby,
                attendees = shared.detail.attendees,
                loading = shared.detail.loading,
                mutating = shared.mutating,
                signedIn = shared.signedIn,
                saved = shared.isSaved(eventId),
                waitlisted = shared.isWaitlisted(eventId),
                organizer = event != null && shared.organizes(event),
                requests = shared.detail.joinRequests,
                ended = event?.hasEnded(now) == true,
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
                followedOrganizers = shared.library.follows.filter { it.kind == FollowKind.ORGANIZER }.mapTo(HashSet()) { it.targetId }
            )
        }
    }

    override fun onIntent(intent: DetailIntent) {
        val event = state.value.event
        when (intent) {
            DetailIntent.Back -> send(DetailEffect.Back)
            is DetailIntent.NotificationPermissionAnswered -> if (intent.granted) app.setRemindersEnabled(
                true
            )

            DetailIntent.Refresh -> refresh(
                { refreshing },
                { copy(refreshing = it) }) { app.reloadEvent(eventId) }

            // Спершу pendingId, потім запит: згортка вище має впізнати картку нового вечора.
            is DetailIntent.PickSession -> if (intent.id != eventId) {
                pendingId = intent.id
                reduce { copy(confirmingCancel = false, confirmingBlock = false, reporting = null) }
                app.openEvent(intent.id)
            }

            // Квитки на афішу купують у джерела: акаунт не потрібен, тому до перевірки входу.
            DetailIntent.PrimaryAction -> if (state.value.action == DetailAction.TICKETS) {
                event?.listing?.canonicalUrl?.let { send(DetailEffect.OpenLink(it)) }
            } else authenticated {
                when (state.value.action) {
                    DetailAction.JOIN, DetailAction.REQUEST -> {
                        app.joinEvent(eventId); offerReminders()
                    }

                    DetailAction.LEAVE -> app.leaveEvent(eventId)
                    DetailAction.JOIN_WAITLIST -> {
                        app.joinWaitlist(eventId); offerReminders()
                    }

                    DetailAction.LEAVE_WAITLIST -> app.leaveWaitlist(eventId)
                    else -> Unit
                }
            }

            DetailIntent.OpenSource -> event?.listing?.canonicalUrl?.let {
                send(
                    DetailEffect.OpenLink(
                        it
                    )
                )
            }

            DetailIntent.ToggleSaved -> authenticated { app.toggleSaved(eventId) }
            DetailIntent.Share -> event?.let { send(DetailEffect.ShareEvent(it)) }
            DetailIntent.AddToCalendar -> event?.let { send(DetailEffect.OpenCalendar(it)) }
            DetailIntent.OpenInMaps -> event?.let { send(DetailEffect.OpenMaps(it)) }
            // Для другої дати прокату — картка представника: окремого піна в сеансу нема.
            DetailIntent.OpenMap -> send(DetailEffect.OpenMap(app.cardIdOf(eventId)))
            is DetailIntent.OpenEvent -> send(DetailEffect.OpenEvent(intent.id))
            is DetailIntent.OpenArtist -> {
                app.openArtist(intent.artist.id, intent.artist.name, intent.artist.kind)
                send(DetailEffect.OpenArtist(intent.artist.id))
            }
            is DetailIntent.OpenShelter -> send(DetailEffect.OpenShelter(intent.shelter))
            is DetailIntent.SeekCompany -> if (intent.open) authenticated { reduce { copy(seekingCompany = true) } }
                else reduce { copy(seekingCompany = false) }
            is DetailIntent.CreateCompanion -> {
                reduce { copy(seekingCompany = false) }
                app.createCompanion(eventId, intent.meetAt, intent.note, intent.capacity)
            }
            is DetailIntent.JoinCompanion -> authenticated { app.joinEvent(intent.id); offerReminders() }
            DetailIntent.Reopen -> if (shown && event == null) app.openEvent(eventId)
            DetailIntent.ToggleFollowPlace -> authenticated {
                event?.let { e -> e.placeId?.let { app.setFollowing(FollowKind.PLACE, it, e.placeLabel, !state.value.followingPlace) } }
            }
            is DetailIntent.ToggleFollowPerson -> authenticated {
                app.setFollowing(FollowKind.ORGANIZER, intent.userId, intent.name, intent.userId !in state.value.followedOrganizers)
            }
            DetailIntent.Edit -> send(DetailEffect.Edit(eventId))
            is DetailIntent.ConfirmCancel -> reduce { copy(confirmingCancel = intent.open) }
            DetailIntent.CancelEvent -> {
                reduce { copy(confirmingCancel = false) }
                app.cancelEvent(eventId)
            }

            is DetailIntent.AttachPhoto -> app.uploadEventImage(
                eventId,
                intent.bytes,
                intent.contentType
            )

            is DetailIntent.ShowReport -> if (intent.target != null && !state.value.signedIn) {
                send(DetailEffect.RequireSignIn)
            } else reduce { copy(reporting = intent.target) }

            is DetailIntent.SendReport -> {
                reduce { copy(reporting = null) }
                when (intent.target) {
                    ReportTarget.EVENT -> app.reportEvent(eventId, intent.reason, intent.details)
                    ReportTarget.PERSON -> reportedUser?.let { app.reportUser(it, intent.reason, intent.details) }
                    // В афіші організатора нема; на саму подію скаржаться через ReportTarget.EVENT.
                    ReportTarget.ORGANIZER -> event?.organizerId?.let {
                        app.reportUser(
                            it,
                            intent.reason,
                            intent.details
                        )
                    }
                }
            }

            is DetailIntent.ConfirmBlock -> if (intent.open && !state.value.signedIn) {
                send(DetailEffect.RequireSignIn)
            } else reduce { copy(confirmingBlock = intent.open) }

            DetailIntent.BlockOrganizer -> {
                reduce { copy(confirmingBlock = false) }
                // Блокування прибирає подію з мапи, тож і екран за нею.
                event?.organizerId?.let { app.blockUser(it)
                send(DetailEffect.Back) }
            }

            DetailIntent.OpenChat -> authenticated { send(DetailEffect.OpenChat(eventId)) }
            is DetailIntent.ConfirmContact -> reduce { copy(confirmingContact = intent.open) }
            DetailIntent.OpenContact -> {
                reduce { copy(confirmingContact = false) }
                event?.gathering?.contactUrl?.let { send(DetailEffect.OpenLink(it)) }
            }

            is DetailIntent.OpenPerson -> authenticated { app.openPerson(intent.userId) }
            DetailIntent.ClosePerson -> app.closePerson()
            is DetailIntent.BlockPerson -> {
                // Організатор — разом із подією, як BlockOrganizer; учасник зникає лише з ростеру.
                val organizer = intent.userId == event?.organizerId
                app.blockUser(intent.userId)
                if (organizer) send(DetailEffect.Back)
            }
            is DetailIntent.ReportPerson -> {
                reportedUser = intent.userId
                reduce { copy(reporting = ReportTarget.PERSON) }
            }
            is DetailIntent.ApproveRequest -> app.approveMember(eventId, intent.userId)
            is DetailIntent.DeclineRequest -> app.declineMember(eventId, intent.userId)
            is DetailIntent.Rate -> app.rateEvent(eventId, intent.score, intent.comment, intent.tags, intent.follow)
        }
    }

    override fun onCleared() {
        // Картка належить екрану: інший екран не має відкритись із чужою шторкою.
        app.closePerson()
        super.onCleared()
    }

    /** Гостя ведемо на вхід, а не на дію, яку сервер відхилить. */
    private inline fun authenticated(block: () -> Unit) {
        if (state.value.signedIn) block() else send(DetailEffect.RequireSignIn)
    }
}
