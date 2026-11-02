package app.poruch.android.feature.mine

import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
import app.poruch.android.feature.withMedia
import app.poruch.domain.MyEventsTab
import app.poruch.shared.MyEventsPresenter
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Тонка обгортка над [MyEventsPresenter]: розклад збирає спільний код, тут — розріз, «Минулі», шторка оцінки й навігація. */
class MyEventsViewModel(private val app: PoruchApp) :
    MviViewModel<MyEventsState, MyEventsIntent, MyEventsEffect>(MyEventsState()) {
    private val presenter = MyEventsPresenter(app, viewModelScope)

    private var declineJob: Job? = null

    init {
        viewModelScope.launch {
            presenter.state.collect { screen ->
                reduce {
                    // Відкриваємося там, де щось попереду: організатор без власних планів не бачить порожнє «Іду».
                    // Рішення — з першою дошкою, де щось є; порожній знімок до завантаження інакше закріпив би «Іду».
                    val b = screen.board
                    // Гість лише зберігає й додає квитки (docs/guest-saves.md): «Іду» й «Організовую» в нього нема.
                    val tabs = if (screen.signedIn) MyEventsTab.entries else MyEventsTab.guest
                    when {
                        !tabChosen && b.anythingAhead && b.openingTab in tabs -> copy(screen = screen, tab = b.openingTab, tabChosen = true)
                        tab !in tabs -> copy(screen = screen, tab = MyEventsTab.SAVED)
                        else -> copy(screen = screen)
                    }
                }
            }
        }
    }

    /** Попередній відхилений іде одразу: «Повернути» — лише для останнього. */
    private fun commitDecline() {
        declineJob?.cancel()
        val request = state.value.declining ?: return
        reduce { copy(declining = null) }
        app.declineMember(request.eventId, request.userId)
    }

    override fun onCleared() {
        // Екран пішов — відмова, яку не повернули, іде зараз.
        state.value.declining?.let { app.declineMember(it.eventId, it.userId) }
        super.onCleared()
    }

    override fun onIntent(intent: MyEventsIntent) {
        when (intent) {
            is MyEventsIntent.PickTab -> reduce { copy(tab = intent.tab, allPast = false, tabChosen = true) }
            MyEventsIntent.ToggleTickets -> reduce {
                // Гостю «Іду» нема: квитки він міг відкрити не кнопкою, а першою дошкою чи щойно доданим квитком.
                val back = beforeTickets.takeIf { screen.signedIn || it in MyEventsTab.guest } ?: MyEventsTab.SAVED
                if (tab == MyEventsTab.TICKETS) copy(tab = back, tabChosen = true)
                else copy(tab = MyEventsTab.TICKETS, beforeTickets = tab, allPast = false, tabChosen = true)
            }
            MyEventsIntent.Refresh -> refresh({ refreshing }, { copy(refreshing = it) }) { app.reloadMyEvents() }
            is MyEventsIntent.OpenEvent -> {
                // Людина вже в розрізі: розріз за замовчуванням більше не перемикаємо під нею.
                reduce { copy(tabChosen = true) }
                app.selectEvent(intent.id)
                send(MyEventsEffect.OpenDetail(intent.id))
            }
            is MyEventsIntent.OpenChat -> send(MyEventsEffect.OpenChat(intent.id))
            MyEventsIntent.FindNearby -> send(MyEventsEffect.OpenMap)
            MyEventsIntent.ShowAllPast -> reduce { copy(allPast = true) }
            is MyEventsIntent.StartRating -> reduce { copy(rating = intent.event) }
            MyEventsIntent.DismissRating -> reduce { copy(rating = null) }
            is MyEventsIntent.Rate -> {
                app.rateEvent(intent.id, intent.score, intent.comment, intent.tags, intent.follow)
                reduce { copy(rating = null) }
            }
            is MyEventsIntent.Approve -> app.approveMember(intent.eventId, intent.userId)
            is MyEventsIntent.Decline -> {
                commitDecline()
                reduce { copy(declining = intent.request) }
                declineJob = viewModelScope.launch {
                    delay(DECLINE_UNDO_MS)
                    commitDecline()
                }
            }
            MyEventsIntent.UndoDecline -> {
                declineJob?.cancel()
                reduce { copy(declining = null) }
            }
            is MyEventsIntent.Unsave -> app.toggleSaved(intent.id)
            MyEventsIntent.SignIn -> send(MyEventsEffect.SignIn)
            MyEventsIntent.CreateEvent -> { app.createStarted("mine"); send(MyEventsEffect.CreateEvent) }
            // Картка «Моїх подій» медіа може не нести: спершу повні деталі, інакше повтор вийде без фото й відео.
            is MyEventsIntent.Repeat -> withMedia(intent.event) { send(MyEventsEffect.Repeat(it.id)) }
            is MyEventsIntent.ThreadsPost -> withMedia(intent.event) { send(MyEventsEffect.ThreadsPost(it, app.threadsPost(it))) }
        }
    }

    /** Деталі дозавантажуються: повторний тап не починає ще одне. Не вдалось — банер спільного шару, дія не йде. */
    private var loadingMedia: Job? = null

    private fun withMedia(event: app.poruch.domain.Event, then: (app.poruch.domain.Event) -> Unit) {
        if (loadingMedia?.isActive == true) return
        loadingMedia = viewModelScope.launch { app.withMedia(event)?.let(then) }
    }

    private companion object {
        /** Скільки чекає відхилений запит, поки його можна повернути. */
        const val DECLINE_UNDO_MS = 5_000L
    }
}
