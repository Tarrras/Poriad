package app.poruch.android.feature.artist

import app.poruch.domain.ArtistKind
import app.poruch.domain.Event

/** Екран артиста: ім'я, вид словом, «Стежити» і майбутні події. Ім'я й вид можуть доїхати з карток, якщо відкрили лише за id (пуш). */
data class ArtistUiState(
    val id: String,
    val name: String = "",
    val kind: ArtistKind? = null,
    val events: List<Event> = emptyList(),
    val loading: Boolean = true,
    val following: Boolean = false,
    val waitlistedIds: List<String> = emptyList()
)

sealed interface ArtistIntent {
    data object Back : ArtistIntent
    /** «Стежити» / «Ви стежите». Гостя веде на вхід. */
    data object ToggleFollow : ArtistIntent
    data class OpenEvent(val id: String) : ArtistIntent
    /** Екран знову зверху після іншого екрана артиста: той перебрав єдиний слот стану. */
    data object Reopen : ArtistIntent
}

sealed interface ArtistEffect {
    data object Back : ArtistEffect
    data object SignIn : ArtistEffect
    data class OpenEvent(val id: String) : ArtistEffect
}
