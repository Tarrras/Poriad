package app.poruch.android.feature.onboarding

import app.poruch.android.mvi.MviViewModel
import app.poruch.shared.PoruchApp

/**
 * Holds the answers until the last step. Nothing is written on the way through: a person who backs
 * out halfway has not told the app anything, and a half-answered taste would rank on one third of
 * a question. The store learns the whole set at once, and it is the store that ends the flow — the
 * root shows the app again when the answers are in, so this screen needs no effect of its own.
 */
class OnboardingViewModel(private val app: PoruchApp) :
    MviViewModel<OnboardingState, OnboardingIntent, Nothing>(OnboardingState()) {

    init {
        // Reopened from the profile, the questions start from what was answered last time.
        val taste = app.state.value.taste
        reduce { copy(interests = taste.interests, times = taste.times, crowd = taste.crowd) }
    }

    override fun onIntent(intent: OnboardingIntent) {
        when (intent) {
            OnboardingIntent.Next -> {
                val current = state.value
                if (current.isLast) app.saveTaste(current.interests, current.times, current.crowd)
                else reduce { copy(step = OnboardingStep.entries[current.questionNumber + 1]) }
            }
            OnboardingIntent.Back -> reduce {
                copy(step = OnboardingStep.entries[(questionNumber - 1).coerceAtLeast(0)])
            }
            OnboardingIntent.Skip -> app.skipOnboarding()
            is OnboardingIntent.ToggleInterest -> reduce { copy(interests = interests.toggle(intent.category)) }
            is OnboardingIntent.ToggleTime -> reduce { copy(times = times.toggle(intent.slot)) }
            is OnboardingIntent.PickCrowd -> reduce { copy(crowd = intent.crowd) }
        }
    }

    private fun List<String>.toggle(value: String) = if (value in this) this - value else this + value
}
