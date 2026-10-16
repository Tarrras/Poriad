package app.poruch.android.feature.mine

import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
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
                    val ready = !tabChosen && b.goingAhead + b.organizingAhead + b.savedAhead > 0
                    if (ready) copy(screen = screen, tab = b.openingTab, tabChosen = true) else copy(screen = screen)
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
            MyEventsIntent.Refresh -> refresh({ refreshing }, { copy(refreshing = it) }) { app.reloadMyEvents() }
            is MyEventsIntent.OpenEvent -> {
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
        }
    }

    private companion object {
        /** Скільки чекає відхилений запит, поки його можна повернути. */
        const val DECLINE_UNDO_MS = 5_000L
    }
}
