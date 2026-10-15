package app.poruch.android.feature.account

import app.poruch.domain.Follow
import app.poruch.shared.PersonState

/** «Ви стежите»: заклади, організатори й артисти, нові першими. */
data class FollowsState(
    val follows: List<Follow> = emptyList(),
    /** Скільки нового було в кого, коли екран відкрили: `followsSeen` гасить лічильник, а тут він лишається до виходу. */
    val fresh: Map<String, Int> = emptyMap(),
    /** Картка організатора з рядка підписки. */
    val person: PersonState? = null
)

sealed interface FollowsIntent {
    data object Back : FollowsIntent
    /** Рядок: заклад відкриває мапу на ньому, організатор — свою картку. */
    data class Open(val follow: Follow) : FollowsIntent
    data class Unfollow(val follow: Follow) : FollowsIntent
    data object ClosePerson : FollowsIntent
    data class ToggleFollowPerson(val userId: String, val name: String) : FollowsIntent
}

sealed interface FollowsEffect {
    data object Back : FollowsEffect
    data object OpenMap : FollowsEffect
    data class OpenArtist(val id: String) : FollowsEffect
}
