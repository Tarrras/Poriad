package app.poruch.android.feature.onboarding

import app.poruch.android.mvi.MviViewModel
import app.poruch.shared.PoruchApp

/** Тримає відповіді до останнього кроку і пише в стор усе разом. Потік завершує стор, тому ефектів тут нема. */
class OnboardingViewModel(private val app: PoruchApp) :
    MviViewModel<OnboardingState, OnboardingIntent, Nothing>(OnboardingState()) {

    init {
        // Відкрито з профілю: починаємо з минулих відповідей.
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
