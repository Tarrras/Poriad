package app.poruch.android.feature.account

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.FollowKind
import app.poruch.shared.PoruchApp

class FollowsViewModel(private val app: PoruchApp) :
    MviViewModel<FollowsState, FollowsIntent, FollowsEffect>(FollowsState()) {

    init {
        observe(app) { shared -> copy(follows = shared.library.follows, person = shared.person) }
    }

    override fun onIntent(intent: FollowsIntent) {
        when (intent) {
            FollowsIntent.Back -> send(FollowsEffect.Back)
            is FollowsIntent.Unfollow -> app.setFollowing(intent.follow.kind, intent.follow.targetId, intent.follow.name, false)
            is FollowsIntent.Open -> when (intent.follow.kind) {
                FollowKind.PLACE -> intent.follow.place?.let { app.focusPlace(it); send(FollowsEffect.OpenMap) }
                FollowKind.ORGANIZER -> app.openPerson(intent.follow.targetId)
                FollowKind.ARTIST -> with(intent.follow) {
                    app.openArtist(targetId, name, artistKind)
                    send(FollowsEffect.OpenArtist(targetId))
                }
            }
            FollowsIntent.ClosePerson -> app.closePerson()
            is FollowsIntent.ToggleFollowPerson -> app.setFollowing(
                FollowKind.ORGANIZER, intent.userId, intent.name,
                state.value.follows.none { it.kind == FollowKind.ORGANIZER && it.targetId == intent.userId }
            )
        }
    }
}
