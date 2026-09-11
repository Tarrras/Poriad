package app.poruch.android.feature.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.Crowd
import app.poruch.domain.TimeSlot

/**
 * The way in.
 *
 * Three questions on the app's own paper, each one a single decision with an answer visible without
 * scrolling. It is a survey only in the sense that it asks — there is no progress bar to endure and
 * no question that must be answered: «Пропустити» is on every step, because a person who wants to
 * see what is on tonight should be allowed to, and the app ranks by time until they say otherwise.
 */
@Composable
fun OnboardingScreen(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.fillMaxSize().background(heroGradient()).statusBarsPadding().navigationBarsPadding()
            .padding(horizontal = Spacing.page)
    ) {
        TopRow(state, onIntent)
        AnimatedContent(
            targetState = state.step,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            modifier = Modifier.weight(1f),
            label = "onboarding-step"
        ) { step ->
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(Spacing.xl)
            ) {
                when (step) {
                    OnboardingStep.WELCOME -> Welcome()
                    OnboardingStep.INTERESTS -> Interests(state, onIntent)
                    OnboardingStep.TIMES -> Times(state, onIntent)
                    OnboardingStep.CROWD -> CrowdStep(state, onIntent)
                }
            }
        }
        Column(
            Modifier.fillMaxWidth().padding(vertical = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            PrimaryButton(
                stringResource(
                    when {
                        state.step == OnboardingStep.WELCOME -> R.string.onboarding_start
                        state.isLast -> R.string.onboarding_finish
                        else -> R.string.next
                    }
                ),
                { onIntent(OnboardingIntent.Next) }, Modifier.fillMaxWidth()
            )
            GhostButton(stringResource(R.string.onboarding_skip), { onIntent(OnboardingIntent.Skip) }, tone = colors.inkSecondary)
        }
    }
}

/** Where you are and how to go back. The step count appears only once there is a step to count. */
@Composable
private fun TopRow(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().height(56.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        if (state.step != OnboardingStep.WELCOME) {
            IconPill(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back), size = 40.dp) {
                onIntent(OnboardingIntent.Back)
            }
            Text(
                stringResource(R.string.onboarding_step, state.questionNumber, state.questionCount),
                style = MaterialTheme.typography.labelMedium, color = colors.inkSecondary
            )
        }
        Spacer(Modifier.weight(1f))
        StepDots(state)
    }
}

/** Four dots rather than a bar: the flow is short enough to count, and a bar promises a form. */
@Composable
private fun StepDots(state: OnboardingState) {
    val colors = Poruch.colors
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
        OnboardingStep.entries.forEach { step ->
            val here = step == state.step
            val width by animateFloatAsState(if (here) 18f else 6f, label = "dot")
            Box(
                Modifier.width(width.dp).height(6.dp)
                    .background(if (here) colors.brand else colors.hairline, Radius.pill)
            )
        }
    }
}

@Composable
private fun Welcome() {
    val colors = Poruch.colors
    Column(Modifier.padding(top = Spacing.section), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        Box(
            Modifier.size(72.dp).background(colors.brandContainer, Radius.lg),
            contentAlignment = Alignment.Center
        ) { Icon(PoruchIcons.sparkle, null, Modifier.size(32.dp), tint = colors.brand) }
        Text(
            stringResource(R.string.onboarding_welcome_title),
            style = MaterialTheme.typography.displaySmall, color = colors.ink
        )
        Text(
            stringResource(R.string.onboarding_welcome_body),
            style = PoruchType.lead, color = colors.inkSecondary
        )
    }
}

@Composable
private fun Question(title: String, hint: String, content: @Composable ColumnScope.() -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.padding(top = Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(title, style = MaterialTheme.typography.headlineMedium, color = colors.ink)
            Text(hint, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
        }
        content()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Interests(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    Question(stringResource(R.string.onboarding_interests_title), stringResource(R.string.onboarding_interests_hint)) {
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            categories.forEach { category ->
                CategoryTile(category, category in state.interests) { onIntent(OnboardingIntent.ToggleInterest(category)) }
            }
        }
    }
}

@Composable
private fun Times(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    Question(stringResource(R.string.onboarding_times_title), stringResource(R.string.onboarding_times_hint)) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            timeSlots.forEach { (slot, labels) ->
                ChoiceRow(
                    stringResource(labels.first), stringResource(labels.second), slot in state.times,
                    multiple = true
                ) { onIntent(OnboardingIntent.ToggleTime(slot)) }
            }
        }
    }
}

@Composable
private fun CrowdStep(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    Question(stringResource(R.string.onboarding_crowd_title), stringResource(R.string.onboarding_crowd_hint)) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            crowds.forEach { (crowd, labels) ->
                ChoiceRow(
                    stringResource(labels.first), stringResource(labels.second), crowd == state.crowd,
                    multiple = false
                ) { onIntent(OnboardingIntent.PickCrowd(crowd)) }
            }
        }
    }
}

/**
 * One answer on a card. The mark says which kind of question it is before the answer is given: a
 * square for the ones that take several, a circle for the one that takes exactly one.
 */
@Composable
private fun ChoiceRow(title: String, hint: String, selected: Boolean, multiple: Boolean, onClick: () -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().cardSurface(Radius.md).border(
            if (selected) 2.dp else 0.dp, if (selected) colors.ink else colors.surface, Radius.md
        ).pressable(onClick = onClick).padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = colors.ink)
            Text(hint, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        Box(
            Modifier.size(24.dp)
                .background(if (selected) colors.brand else colors.surfaceMuted, if (multiple) Radius.xs else Radius.pill),
            contentAlignment = Alignment.Center
        ) {
            if (selected) Icon(Icons.Outlined.Check, null, Modifier.size(14.dp), tint = colors.onBrand)
        }
    }
}

/** The vocabulary of the shared module, given words. Order is the order a week is lived in. */
private val timeSlots = listOf(
    TimeSlot.WEEKDAY_EVENING to (R.string.slot_weekday_evening to R.string.slot_weekday_evening_hint),
    TimeSlot.WEEKEND_DAY to (R.string.slot_weekend_day to R.string.slot_weekend_day_hint),
    TimeSlot.WEEKEND_EVENING to (R.string.slot_weekend_evening to R.string.slot_weekend_evening_hint),
    TimeSlot.WEEKDAY_DAY to (R.string.slot_weekday_day to R.string.slot_weekday_day_hint)
)

private val crowds = listOf(
    Crowd.INTIMATE to (R.string.crowd_intimate to R.string.crowd_intimate_hint),
    Crowd.MEDIUM to (R.string.crowd_medium to R.string.crowd_medium_hint),
    Crowd.ANY to (R.string.crowd_any to R.string.crowd_any_hint)
)
