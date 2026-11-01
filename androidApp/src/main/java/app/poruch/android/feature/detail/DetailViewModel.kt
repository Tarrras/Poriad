package app.poruch.android.feature.detail

import app.poruch.android.navigation.AuthReason
import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
import app.poruch.android.platform.NotificationPermission
import app.poruch.domain.AppError
import app.poruch.domain.FollowKind
import app.poruch.shared.AppMessage
import app.poruch.shared.AppNotice
import app.poruch.shared.DetailAction
import app.poruch.shared.DetailPresenter
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.launch

/**
 * Тонка обгортка над [DetailPresenter]: стан екрана складає спільний код, тут — листи й прапорці цього
 * екрана, переклад інтентів у дії стору та навігацію.
 */
class DetailViewModel(
    private val app: PoruchApp,
    private val notifications: NotificationPermission,
    openedId: String
) : MviViewModel<DetailState, DetailIntent, DetailEffect>(DetailState()) {
    private val presenter = DetailPresenter(app, openedId, viewModelScope)

    /** На кого скарга з картки: картка вже закрита, коли людина обирає причину. */
    private var reportedUser: String? = null

    /** «На мапі»: слот відкритої події переходить мапі як фокус, і при знятті екрана ми його не чистимо. */
    private var handedOff = false

    /** Запис з цього екрана, який сервер може спинити `AGE_REQUIRED`: повторюємо його, щойно дату збережено. */
    private var join: (() -> Unit)? = null
    private var declaring = false
    /** Банер, що вже висів до запису: він не відповідь на нього. */
    private var staleNotice: AppNotice? = null

    init {
        viewModelScope.launch {
            presenter.state.collect { screen ->
                // Супутник створено: «Поділитися» один раз, прапорець гасимо в сторі.
                val created = screen.createdCompanion
                val event = screen.event
                if (created != null && event != null) {
                    app.clearCreatedCompanion(); send(DetailEffect.ShareCompanion(event, created))
                }
                // Збіг «Піти разом»: сервер уже записав обох у супутник — відкриваємо його, там чат.
                screen.matchedCompanion?.let { app.clearMatchedCompanion(); send(DetailEffect.OpenEvent(it)) }
                // Записались (чи в черзі, чи запит пішов): повтор більше не потрібен.
                if (screen.room?.joined == true || screen.room?.awaitingApproval == true || screen.waitlisted) join = null
                val detail = app.state.value.detail
                val detailed = !screen.loading && detail.failure == null && detail.event?.id == screen.event?.id
                reduce { copy(screen = screen, detailed = detailed) }
            }
        }
        viewModelScope.launch {
            app.state.collect { shared ->
                // Помилку не показуємо банером «вкажіть у профілі»: шторка дати тут же, і запис іде після неї.
                val notice = shared.notice
                if (join != null && !declaring && notice != staleNotice) when {
                    notice == AppNotice.Failed(AppError.AgeRequired) -> {
                        app.clearNotice()
                        reduce { copy(askingBirthDate = true) }
                    }
                    // Запис відмовлено з іншої причини: повторювати нема чого (і інший екран деталей не перехопить чужу помилку).
                    notice is AppNotice.Failed -> join = null
                }
                if (declaring && shared.notice == AppNotice.Told(AppMessage.AGE_CONFIRMED)) {
                    declaring = false
                    join?.invoke()
                }
                // Дату не прийняли (молодше 18, уже вказана): банер скаже чому, повтору не буде.
                if (declaring && shared.notice is AppNotice.Failed) { declaring = false; join = null }
            }
        }
    }

    /** Запис, що пам'ятає себе для повтору після дати народження. */
    private fun joining(action: () -> Unit) {
        join = action
        staleNotice = app.state.value.notice
        action()
        offerReminders()
    }

    private val eventId get() = presenter.sessionId
    private val screen get() = state.value.screen

    /**
     * Перше приєднання — природний момент спитати про сповіщення: без них нагадування за годину не прийде.
     * Хто вимкнув нагадування в профілі, того не питаємо: його вибір лишається.
     */
    private fun offerReminders() {
        if (!app.state.value.remindersEnabled || notifications.granted()) return
        send(DetailEffect.AskNotificationPermission)
    }

    override fun onIntent(intent: DetailIntent) {
        val event = screen.event
        when (intent) {
            DetailIntent.Back -> send(DetailEffect.Back)
            is DetailIntent.NotificationPermissionAnswered -> if (intent.granted) app.setRemindersEnabled(
                true
            )

            DetailIntent.Refresh -> refresh(
                { refreshing },
                { copy(refreshing = it) }) { presenter.refresh() }

            is DetailIntent.PickSession -> if (intent.id != eventId) {
                reduce { copy(confirmingCancel = false, confirmingBlock = false, reporting = null) }
                presenter.pickSession(intent.id)
            }

            // Квитки на афішу купують у джерела: акаунт не потрібен, тому до перевірки входу.
            DetailIntent.PrimaryAction -> if (screen.action == DetailAction.TICKETS) {
                event?.listing?.let { listing ->
                    listing.canonicalUrl?.let {
                        send(DetailEffect.OpenLink(app.ticketOpened(eventId, listing.sourceName, "bar", it)))
                    }
                }
            } else authenticated(AuthReason.JOIN) {
                when (screen.action) {
                    DetailAction.JOIN, DetailAction.REQUEST -> joining { app.joinEvent(eventId) }

                    DetailAction.LEAVE -> app.leaveEvent(eventId)
                    DetailAction.JOIN_WAITLIST -> joining { app.joinWaitlist(eventId) }

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

            is DetailIntent.OpenSeller -> intent.offer.url?.let {
                send(DetailEffect.OpenLink(app.ticketOpened(eventId, intent.offer.sourceName, intent.from, it)))
            }

            is DetailIntent.ShowMeetTime -> reduce { copy(movingMeet = intent.from) }
            is DetailIntent.MoveMeet -> {
                reduce { copy(movingMeet = null) }
                app.moveCompanion(eventId, intent.meetAt)
            }

            is DetailIntent.BoughtPromptAnswered -> if (state.value.boughtPrompt) {
                reduce { copy(boughtPrompt = false) }
                app.boughtPromptAnswered(intent.saved, intent.ticket)
                // Гість теж: закладка лягає на телефон (docs/guest-saves.md).
                if (intent.saved && !intent.ticket && !screen.saved) app.toggleSaved(eventId)
            }

            DetailIntent.ToggleSaved -> app.toggleSaved(eventId)
            DetailIntent.Share -> event?.let {
                if (!screen.canInvite) send(DetailEffect.ShareEvent(it))
                else if (!state.value.inviting) viewModelScope.launch {
                    // Посилання дає спільний шар — особисте з входом, звичайне гостю чи при збої — і сам рахує `share`.
                    reduce { copy(inviting = true) }
                    val link = app.inviteLink(it.id)
                    reduce { copy(inviting = false) }
                    send(DetailEffect.Invite(it, link))
                }
            }

            DetailIntent.AddToCalendar -> event?.let { send(DetailEffect.OpenCalendar(it)) }
            DetailIntent.OpenInMaps -> event?.let { send(DetailEffect.OpenMaps(it)) }
            // Для другої дати прокату — картка представника: окремого піна в сеансу нема.
            DetailIntent.OpenMap -> {
                handedOff = true; send(DetailEffect.OpenMap(presenter.cardId()))
            }

            is DetailIntent.OpenEvent -> send(DetailEffect.OpenEvent(intent.id))
            is DetailIntent.OpenArtist -> {
                app.openArtist(intent.artist.id, intent.artist.name, intent.artist.kind)
                send(DetailEffect.OpenArtist(intent.artist.id))
            }

            is DetailIntent.OpenShelter -> send(DetailEffect.OpenShelter(intent.shelter))
            is DetailIntent.SeekCompany -> if (intent.open) authenticated(AuthReason.COMPANY) {
                reduce {
                    copy(
                        seekingCompany = true
                    )
                }
            }
            else reduce { copy(seekingCompany = false) }

            is DetailIntent.CreateCompanion -> {
                reduce { copy(seekingCompany = false) }
                app.createCompanion(eventId, intent.meetAt, intent.note, intent.capacity)
            }

            is DetailIntent.JoinCompanion -> authenticated(AuthReason.JOIN) { joining { app.joinEvent(intent.id) } }
            // Гостю намір ставить спільний шар після входу, тож спершу кажемо йому, а тоді ведемо на вхід.
            DetailIntent.WantCompany -> { app.wantCompany(); authenticated(AuthReason.COMPANY) { offerReminders() } }
            DetailIntent.DropCompany -> app.dropCompany()
            is DetailIntent.SayCompanyYes -> authenticated { app.sayCompanyYes(intent.userId) }
            // ON_RESUME: і повернення з іншого екрана, і з сайту продавця — тоді, можливо, «Купили?» (раз на подію).
            DetailIntent.Reopen -> {
                presenter.reopen()
                if (app.takeBoughtPrompt(eventId)) reduce { copy(boughtPrompt = true) }
            }

            is DetailIntent.FollowArtist -> intent.artist.let {
                if (intent.following) app.followArtist(it.id, it.name, "hint")
                else app.setFollowing(FollowKind.ARTIST, it.id, it.name, false)
            }

            DetailIntent.ToggleFollowPlace -> authenticated(AuthReason.FOLLOW) {
                event?.let { e ->
                    e.placeId?.let {
                        app.setFollowing(
                            FollowKind.PLACE,
                            it,
                            e.placeLabel,
                            !screen.followingPlace
                        )
                    }
                }
            }

            is DetailIntent.ToggleFollowPerson -> authenticated(AuthReason.FOLLOW) {
                app.setFollowing(
                    FollowKind.ORGANIZER,
                    intent.userId,
                    intent.name,
                    intent.userId !in screen.followedOrganizers
                )
            }

            DetailIntent.Edit -> if (state.value.detailed) send(DetailEffect.Edit(eventId))
            is DetailIntent.ConfirmCancel -> reduce { copy(confirmingCancel = intent.open) }
            DetailIntent.CancelEvent -> {
                reduce { copy(confirmingCancel = false) }
                app.cancelEvent(eventId)
            }

            is DetailIntent.ShowReport -> if (intent.target != null && !screen.signedIn) {
                send(DetailEffect.RequireSignIn())
            } else reduce { copy(reporting = intent.target) }

            is DetailIntent.SendReport -> {
                reduce { copy(reporting = null) }
                when (intent.target) {
                    ReportTarget.EVENT -> app.reportEvent(eventId, intent.reason, intent.details)
                    ReportTarget.PERSON -> reportedUser?.let {
                        app.reportUser(
                            it,
                            intent.reason,
                            intent.details
                        )
                    }
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

            is DetailIntent.ConfirmBlock -> if (intent.open && !screen.signedIn) {
                send(DetailEffect.RequireSignIn())
            } else reduce { copy(confirmingBlock = intent.open) }

            DetailIntent.BlockOrganizer -> {
                reduce { copy(confirmingBlock = false) }
                // Блокування прибирає подію з мапи, тож і екран за нею.
                event?.organizerId?.let { app.blockUser(it); send(DetailEffect.Back) }
            }

            DetailIntent.OpenChat -> authenticated { send(DetailEffect.OpenChat(eventId)) }
            is DetailIntent.OpenQuestion -> authenticated {
                (intent.askerId ?: screen.userId)?.let { send(DetailEffect.OpenChat(eventId, it)) }
            }
            is DetailIntent.ConfirmContact -> reduce { copy(confirmingContact = intent.open) }
            DetailIntent.OpenContact -> {
                reduce { copy(confirmingContact = false) }
                screen.contactUrl?.let { send(DetailEffect.OpenLink(it)) }
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
            is DetailIntent.DeclareBirthDate -> {
                reduce { copy(askingBirthDate = false) }
                if (intent.date == null) join = null
                else { declaring = true; app.declareBirthDate(intent.date.toString()) }
            }
            DetailIntent.ThreadsPost -> event?.let { send(DetailEffect.ThreadsPost(it, app.threadsPost(it))) }
            is DetailIntent.Rate -> app.rateEvent(
                eventId,
                intent.score,
                intent.comment,
                intent.tags,
                intent.follow
            )
        }
    }

    override fun onCleared() {
        presenter.release(keepSlot = handedOff)
        super.onCleared()
    }

    /** Гостя ведемо на вхід, а не на дію, яку сервер відхилить. */
    private inline fun authenticated(reason: AuthReason = AuthReason.GENERAL, block: () -> Unit) {
        if (screen.signedIn) block() else send(DetailEffect.RequireSignIn(reason))
    }
}
