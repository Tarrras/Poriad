package app.poruch.android.feature.mine

import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
import app.poruch.shared.MyEventsPresenter
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.launch

/** Тонка обгортка над [MyEventsPresenter]: розклад збирає спільний код, тут — розріз, «Минулі», шторка оцінки й навігація. */
class MyEventsViewModel(private val app: PoruchApp) :
    MviViewModel<MyEventsState, MyEventsIntent, MyEventsEffect>(MyEventsState()) {
    private val presenter = MyEventsPresenter(app, viewModelScope)

    init {
        viewModelScope.launch { presenter.state.collect { screen -> reduce { copy(screen = screen) } } }
    }

    override fun onIntent(intent: MyEventsIntent) {
        when (intent) {
            is MyEventsIntent.PickTab -> reduce { copy(tab = intent.tab, allPast = false) }
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
            is MyEventsIntent.Decline -> app.declineMember(intent.eventId, intent.userId)
            is MyEventsIntent.Unsave -> app.toggleSaved(intent.id)
            MyEventsIntent.SignIn -> send(MyEventsEffect.SignIn)
            MyEventsIntent.CreateEvent -> { app.createStarted("mine"); send(MyEventsEffect.CreateEvent) }
        }
    }
}
