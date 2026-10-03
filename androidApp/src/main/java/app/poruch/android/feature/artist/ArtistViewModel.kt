package app.poruch.android.feature.artist

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.FollowKind
import app.poruch.shared.PoruchApp

class ArtistViewModel(private val app: PoruchApp, private val artistId: String) :
    MviViewModel<ArtistUiState, ArtistIntent, ArtistEffect>(ArtistUiState(artistId)) {

    init {
        // Той, хто відкриває (пошук, підписки), вже кликав `openArtist` з ім'ям; без нього (пуш) питаємо тут.
        if (app.state.value.artist?.id != artistId) app.openArtist(artistId)
        observe(app) { shared ->
            val artist = shared.artist?.takeIf { it.id == artistId }
            copy(
                name = artist?.name ?: name, kind = artist?.kind ?: kind, events = artist?.events ?: events,
                loading = artist?.loading ?: loading,
                following = shared.isFollowing(FollowKind.ARTIST, artistId),
                waitlistedIds = shared.library.waitlistedIds
            )
        }
    }

    override fun onIntent(intent: ArtistIntent) {
        when (intent) {
            ArtistIntent.Back -> send(ArtistEffect.Back)
            ArtistIntent.ToggleFollow ->
                if (app.state.value.signedIn) app.setFollowing(FollowKind.ARTIST, artistId, state.value.name, !state.value.following)
                else send(ArtistEffect.SignIn)
            is ArtistIntent.OpenEvent -> {
                app.selectEvent(intent.id, "artist")
                send(ArtistEffect.OpenEvent(intent.id))
            }
            ArtistIntent.Reopen -> if (app.state.value.artist?.id != artistId) app.openArtist(artistId, state.value.name.ifBlank { null }, state.value.kind)
        }
    }

    override fun onCleared() {
        // Слот один на всіх: не закриваємо чужий екран артиста, якщо той уже перебрав його.
        if (app.state.value.artist?.id == artistId) app.closeArtist()
        super.onCleared()
    }
}
