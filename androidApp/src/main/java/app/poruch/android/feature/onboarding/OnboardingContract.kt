package app.poruch.android.feature.onboarding

import app.poruch.domain.EventCategory
import app.poruch.domain.Crowd
import app.poruch.domain.PopularArtist
import app.poruch.domain.TimeSlot

/** Кроки онбордингу: те, що читає ранжування, і артисти — привід повернутись. Кожен зайвий екран — привід піти. */
enum class OnboardingStep { WELCOME, INTERESTS, TIMES, CROWD, ARTISTS }

data class OnboardingState(
    val step: OnboardingStep = OnboardingStep.WELCOME,
    val interests: List<EventCategory> = emptyList(),
    val times: List<TimeSlot> = emptyList(),
    val crowd: Crowd = Crowd.ANY,
    /** «За ким стежити?»: хто гастролює країною (місто ще не відоме). Null — ще їде, порожньо — кроку нема. */
    val artists: List<PopularArtist>? = null,
    /** За ким уже стежать (повторне проходження з профілю): позначені й не знімаються. */
    val followed: Set<String> = emptySet(),
    /** Пошук на кроці артистів і його збіги по всій країні ([app.poruch.shared.AppState.artistMatches]). */
    val query: String = "",
    val matches: List<PopularArtist>? = null,
    /** Обрані на кроці, з пошуку теж: підписки ставимо разом з рештою відповідей, на «Готово». */
    val picked: Map<String, PopularArtist> = emptyMap()
) {
    /** Вітання — не питання, тому не рахується. */
    val questionNumber get() = OnboardingStep.entries.indexOf(step)
    val questionCount get() = OnboardingStep.entries.size - 1
    /** Артистів нема (збій, порожньо) — закінчуємо на «Який формат?». */
    val isLast get() = step == OnboardingStep.ARTISTS || (step == OnboardingStep.CROWD && artists?.isEmpty() == true)
}

sealed interface OnboardingIntent {
    data object Next : OnboardingIntent
    data object Back : OnboardingIntent
    data object Skip : OnboardingIntent
    data class ToggleInterest(val category: EventCategory) : OnboardingIntent
    data class ToggleTime(val slot: TimeSlot) : OnboardingIntent
    data class PickCrowd(val crowd: Crowd) : OnboardingIntent
    data class SearchArtists(val text: String) : OnboardingIntent
    data class ToggleArtist(val artist: PopularArtist) : OnboardingIntent
}
