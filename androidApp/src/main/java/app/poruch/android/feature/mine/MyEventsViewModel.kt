package app.poruch.android.feature.mine

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.Event
import app.poruch.shared.AppState
import app.poruch.shared.PoruchApp
import kotlin.time.Clock

class MyEventsViewModel(private val app: PoruchApp) :
    MviViewModel<MyEventsState, MyEventsIntent, MyEventsEffect>(MyEventsState()) {

    private var shared = AppState()

    init {
        observe(app) { latest ->
            shared = latest
            copy(
                visible = latest.forTab(tab),
                savedIds = latest.library.savedIds,
                waitlistedIds = latest.library.waitlistedIds,
                signedIn = latest.signedIn,
                loading = latest.map.loading
            )
        }
        app.loadMyEvents()
    }

    override fun onIntent(intent: MyEventsIntent) {
        when (intent) {
            is MyEventsIntent.PickTab -> reduce { copy(tab = intent.tab, visible = shared.forTab(intent.tab)) }
            MyEventsIntent.Refresh -> refresh({ refreshing }, { copy(refreshing = it) }) { app.reloadMyEvents() }
            is MyEventsIntent.OpenEvent -> {
                app.selectEvent(intent.id)
                send(MyEventsEffect.OpenDetail(intent.id))
            }
            MyEventsIntent.SignIn -> send(MyEventsEffect.SignIn)
            MyEventsIntent.CreateEvent -> send(MyEventsEffect.CreateEvent)
        }
    }

    /**
     * «Збережені» з того ж списку: зберегти можна, не приєднуючись. Завершене йде лише в
     * «Завершено», свіжіше першим; збережене, куди людина не йшла, просто зникає.
     */
    private fun AppState.forTab(tab: MyEventsTab): List<Event> {
        val now = Clock.System.now()
        if (tab == MyEventsTab.ENDED) return library.myEvents.filter { concerns(it) && it.hasEnded(now) }.asReversed()
        return library.myEvents.filter { event ->
            !event.hasEnded(now) && when (tab) {
                MyEventsTab.ATTENDING -> event.gathering?.joined == true
                MyEventsTab.ORGANIZING -> organizes(event)
                MyEventsTab.SAVED, MyEventsTab.ENDED -> isSaved(event.id)
            }
        }
    }
}
