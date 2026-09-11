package app.poruch.android.feature.onboarding

import app.poruch.domain.Crowd

/**
 * The opening questions. Four steps and not one more: every extra screen between a person and the
 * events is a screen they can leave the app on, so this asks only what the ranking actually reads.
 */
enum class OnboardingStep { WELCOME, INTERESTS, TIMES, CROWD }

data class OnboardingState(
    val step: OnboardingStep = OnboardingStep.WELCOME,
    val interests: List<String> = emptyList(),
    val times: List<String> = emptyList(),
    val crowd: String = Crowd.ANY
) {
    /** The welcome screen is not a question, so it is not counted as one. */
    val questionNumber get() = OnboardingStep.entries.indexOf(step)
    val questionCount get() = OnboardingStep.entries.size - 1
    val isLast get() = step == OnboardingStep.CROWD
}

sealed interface OnboardingIntent {
    data object Next : OnboardingIntent
    data object Back : OnboardingIntent
    data object Skip : OnboardingIntent
    data class ToggleInterest(val category: String) : OnboardingIntent
    data class ToggleTime(val slot: String) : OnboardingIntent
    data class PickCrowd(val crowd: String) : OnboardingIntent
}
