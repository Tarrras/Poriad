package app.poruch.android.feature.onboarding

import androidx.lifecycle.viewModelScope
import app.poruch.android.feature.home.toggle
import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.Crowd
import app.poruch.domain.FollowKind
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** Тримає відповіді до останнього кроку і пише в стор усе разом. Потік завершує стор, тому ефектів тут нема. */
class OnboardingViewModel(private val app: PoruchApp) :
    MviViewModel<OnboardingState, OnboardingIntent, Nothing>(OnboardingState()) {

    init {
        // Відкрито з профілю: починаємо з минулих відповідей і одразу з питань — знайомі вже знайомі.
        val taste = app.state.value.taste
        val answered = taste.interests.isNotEmpty() || taste.times.isNotEmpty() || taste.crowd != Crowd.ANY
        reduce {
            copy(
                step = if (answered) OnboardingStep.INTERESTS else step,
                interests = taste.interests, times = taste.times, crowd = taste.crowd
            )
        }
        // Місто ще не відоме (геолокацію питаємо після туру), тож артисти — ті, хто гастролює країною.
        app.loadPopularArtists(true)
        viewModelScope.launch {
            app.state.map { shared ->
                Triple(shared.popularArtists, shared.artistMatches, shared.library.follows.filter { it.kind == FollowKind.ARTIST }.map { it.targetId }.toSet())
            }.distinctUntilChanged().collect { (artists, matches, followed) ->
                reduce { copy(artists = artists, matches = matches, followed = followed) }
            }
        }
    }

    override fun onIntent(intent: OnboardingIntent) {
        when (intent) {
            OnboardingIntent.Next -> {
                val current = state.value
                if (current.isLast) finish(current)
                else reduce { copy(step = OnboardingStep.entries[current.questionNumber + 1]) }
            }
            OnboardingIntent.Back -> reduce {
                copy(step = OnboardingStep.entries[(questionNumber - 1).coerceAtLeast(0)])
            }
            OnboardingIntent.Skip -> app.skipOnboarding()
            is OnboardingIntent.ToggleInterest -> reduce { copy(interests = interests.toggle(intent.category)) }
            is OnboardingIntent.ToggleTime -> reduce { copy(times = times.toggle(intent.slot)) }
            is OnboardingIntent.PickCrowd -> reduce { copy(crowd = intent.crowd) }
            is OnboardingIntent.SearchArtists -> {
                reduce { copy(query = intent.text) }
                app.searchArtists(intent.text)
            }
            is OnboardingIntent.ToggleArtist -> reduce { copy(picked = picked.toggle(intent.artist)) }
        }
    }

    private fun finish(current: OnboardingState) {
        if (current.step == OnboardingStep.ARTISTS) {
            app.followArtists(current.picked.values.toList(), "onboarding")
            app.radarPickerClosed(current.artists.orEmpty().size, current.picked.size, "onboarding")
        }
        app.saveTaste(current.interests, current.times, current.crowd)
    }

    private fun <T> List<T>.toggle(value: T) = if (value in this) this - value else this + value
}
