package app.poruch.android.feature.mine

import app.poruch.android.mvi.MviViewModel
import app.poruch.shared.AppState
import app.poruch.shared.PoruchApp

class MyEventsViewModel(private val app: PoruchApp) :
    MviViewModel<MyEventsState, MyEventsIntent, MyEventsEffect>(MyEventsState()) {

    private var shared = AppState()

    init {
        observe(app) { latest ->
            shared = latest
            copy(
                visible = latest.forTab(tab),
                savedIds = latest.savedIds,
                waitlistedIds = latest.waitlistedIds,
                signedIn = latest.signedIn,
                loading = latest.loading
            )
        }
        app.loadMyEvents()
    }

    override fun onIntent(intent: MyEventsIntent) {
        when (intent) {
            is MyEventsIntent.PickTab -> reduce { copy(tab = intent.tab, visible = shared.forTab(intent.tab)) }
            MyEventsIntent.Refresh -> app.loadMyEvents()
            is MyEventsIntent.OpenEvent -> {
                app.selectEvent(intent.id)
                send(MyEventsEffect.OpenDetail(intent.id))
            }
            MyEventsIntent.SignIn -> send(MyEventsEffect.SignIn)
            MyEventsIntent.CreateEvent -> send(MyEventsEffect.CreateEvent)
        }
    }

    /** «Saved» draws on the same list: an event can be saved without being joined or organised. */
    private fun AppState.forTab(tab: MyEventsTab) = myEvents.filter { event ->
        when (tab) {
            MyEventsTab.ATTENDING -> event.gathering?.joined == true
            MyEventsTab.ORGANIZING -> organizes(event)
            MyEventsTab.SAVED -> isSaved(event.id)
        }
    }
}
