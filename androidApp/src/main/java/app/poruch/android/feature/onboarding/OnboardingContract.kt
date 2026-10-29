package app.poruch.android.feature.onboarding

import app.poruch.domain.EventCategory
import app.poruch.domain.Crowd
import app.poruch.domain.District
import app.poruch.domain.PopularArtist
import app.poruch.domain.TimeSlot

/**
 * Кроки онбордингу: те, що читає ранжування, і [FOLLOW] — привід повернутись. Кожен зайвий екран — привід піти, тож
 * артисти й райони («Мої місця», docs/my-places.md) — один крок «Про що сказати?» з двома секціями, а не два прохання поспіль.
 */
enum class OnboardingStep { WELCOME, INTERESTS, TIMES, CROWD, FOLLOW }

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
    val picked: Map<String, PopularArtist> = emptyMap(),
    /** Адміністративні райони міста (без місцевостей) для секції «Райони». Порожньо — секції нема. */
    val districts: List<District> = emptyList(),
    /** Місто цих районів: підписом над чипами — людина зі Львова бачить, що це не Київ. */
    val city: String = "",
    /** Райони, що вже в «Моїх місцях» (повторне проходження): позначені й не знімаються. */
    val followedDistricts: Set<Long> = emptySet(),
    /** Обрані райони: стежимо разом з рештою відповідей, на «Готово». */
    val pickedDistricts: Set<Long> = emptySet()
) {
    /** Секція артистів є: ще їдуть (null — індикатор) чи прийшли непорожні. Збій чи порожньо — секції нема. */
    val hasArtists get() = artists?.isEmpty() != true
    /** Кроки, що є: ні артистів, ні районів — «Про що сказати?» пропускаємо. */
    val steps: List<OnboardingStep>
        get() = OnboardingStep.entries.filter { it != OnboardingStep.FOLLOW || hasArtists || districts.isNotEmpty() }
    /** Скільки підписок поставить «Готово»: артисти й райони разом. */
    val followCount get() = picked.size + pickedDistricts.count { it !in followedDistricts }
    /** Вітання — не питання, тому не рахується. */
    val questionNumber get() = steps.count { it < step }
    val questionCount get() = steps.size - 1
    val isLast get() = steps.none { it > step }
    val next get() = steps.firstOrNull { it > step } ?: step
    val previous get() = steps.lastOrNull { it < step } ?: OnboardingStep.WELCOME
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
    data class ToggleDistrict(val id: Long) : OnboardingIntent
}
