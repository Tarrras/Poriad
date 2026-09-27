package app.poruch.android.feature.onboarding

import app.poruch.domain.EventCategory
import app.poruch.domain.Crowd
import app.poruch.domain.TimeSlot

/** Кроки онбордингу. Лише те, що читає ранжування: кожен зайвий екран — привід піти. */
enum class OnboardingStep { WELCOME, INTERESTS, TIMES, CROWD }

data class OnboardingState(
    val step: OnboardingStep = OnboardingStep.WELCOME,
    val interests: List<EventCategory> = emptyList(),
    val times: List<TimeSlot> = emptyList(),
    val crowd: Crowd = Crowd.ANY
) {
    /** Вітання — не питання, тому не рахується. */
    val questionNumber get() = OnboardingStep.entries.indexOf(step)
    val questionCount get() = OnboardingStep.entries.size - 1
    val isLast get() = step == OnboardingStep.CROWD
}

sealed interface OnboardingIntent {
    data object Next : OnboardingIntent
    data object Back : OnboardingIntent
    data object Skip : OnboardingIntent
    data class ToggleInterest(val category: EventCategory) : OnboardingIntent
    data class ToggleTime(val slot: TimeSlot) : OnboardingIntent
    data class PickCrowd(val crowd: Crowd) : OnboardingIntent
}
