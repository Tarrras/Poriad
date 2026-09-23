package app.poruch.android.feature.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.Crowd
import app.poruch.domain.TimeSlot

/** Онбординг: три питання, кожне одним рішенням. «Пропустити» на кожному кроці, вгорі праворуч. */
@Composable
fun OnboardingScreen(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    val colors = Poruch.colors
    BackHandler(state.step != OnboardingStep.WELCOME) { onIntent(OnboardingIntent.Back) }
    Column(
        Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding().navigationBarsPadding()
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
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = Spacing.lg),
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
        // Одна дія внизу: «Пропустити» живе вгорі праворуч і не сперечається з нею.
        PrimaryButton(
            stringResource(
                when {
                    state.step == OnboardingStep.WELCOME -> R.string.onboarding_start
                    state.isLast -> R.string.onboarding_finish
                    else -> R.string.next
                }
            ),
            { onIntent(OnboardingIntent.Next) }, Modifier.fillMaxWidth().padding(vertical = Spacing.lg)
        )
    }
}

/** Назад, прогрес трьома сегментами і «Пропустити». На вітанні прогресу ще нема чого показувати. */
@Composable
private fun TopRow(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    val colors = Poruch.colors
    val stepLabel = stringResource(R.string.onboarding_step, state.questionNumber, state.questionCount)
    Row(
        Modifier.fillMaxWidth().height(56.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        if (state.step != OnboardingStep.WELCOME) {
            IconPill(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back), size = 40.dp) {
                onIntent(OnboardingIntent.Back)
            }
            Row(
                Modifier.weight(1f).clearAndSetSemantics { contentDescription = stepLabel },
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
            ) {
                (1..state.questionCount).forEach { index ->
                    Box(
                        Modifier.weight(1f).height(4.dp)
                            .background(if (index <= state.questionNumber) colors.brand else colors.brandContainer, Radius.pill)
                    )
                }
            }
        } else Spacer(Modifier.weight(1f))
        GhostButton(stringResource(R.string.onboarding_skip), { onIntent(OnboardingIntent.Skip) }, tone = colors.inkSecondary)
    }
}

/** Вітання по центру: мозаїка плиток категорій замість одного значка — одразу видно, про що застосунок. */
@Composable
private fun Welcome() {
    val colors = Poruch.colors
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        Row(
            Modifier.padding(top = Spacing.section, bottom = Spacing.lg).clearAndSetSemantics { },
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
        ) {
            MosaicTile("music", 52.dp, Modifier.offset(y = 18.dp))
            MosaicTile("food", 68.dp, Modifier.offset(y = (-6).dp))
            MosaicTile("social", 96.dp)
            MosaicTile("outdoors", 68.dp, Modifier.offset(y = (-6).dp))
            MosaicTile("games", 52.dp, Modifier.offset(y = 18.dp))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            Text(stringResource(R.string.onboarding_welcome_title), style = MaterialTheme.typography.displaySmall, color = colors.ink)
            Text(
                stringResource(R.string.onboarding_welcome_body),
                style = PoruchType.lead, color = colors.inkSecondary, textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun MosaicTile(category: String, size: Dp, modifier: Modifier = Modifier) {
    Box(
        modifier.size(size).background(categoryGradient(category), RoundedCornerShape(size * 0.3f)),
        contentAlignment = Alignment.Center
    ) { Icon(categoryIcon(category), null, Modifier.size(size * 0.42f), tint = categoryInk(category)) }
}

@Composable
private fun Question(title: String, hint: String, content: @Composable ColumnScope.() -> Unit) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(title, style = MaterialTheme.typography.displaySmall, color = colors.ink)
            Text(hint, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
        }
        content()
    }
}

@Composable
private fun Interests(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    Question(stringResource(R.string.onboarding_interests_title), stringResource(R.string.onboarding_interests_hint)) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            categories.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    row.forEach { category ->
                        CategoryCard(category, category in state.interests, Modifier.weight(1f)) {
                            onIntent(OnboardingIntent.ToggleInterest(category))
                        }
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun Times(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    Question(stringResource(R.string.onboarding_times_title), stringResource(R.string.onboarding_times_hint)) {
        GroupedRows {
            timeSlots.forEachIndexed { index, (slot, labels) ->
                ChoiceRow(
                    stringResource(labels.first), stringResource(labels.second), slot in state.times,
                    multiple = true
                ) { onIntent(OnboardingIntent.ToggleTime(slot)) }
                if (index < timeSlots.lastIndex) HairLine(Modifier.padding(start = Spacing.lg))
            }
        }
    }
}

@Composable
private fun CrowdStep(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    Question(stringResource(R.string.onboarding_crowd_title), stringResource(R.string.onboarding_crowd_hint)) {
        GroupedRows {
            crowds.forEachIndexed { index, (crowd, labels) ->
                ChoiceRow(
                    stringResource(labels.first), stringResource(labels.second), crowd == state.crowd,
                    multiple = false
                ) { onIntent(OnboardingIntent.PickCrowd(crowd)) }
                if (index < crowds.lastIndex) HairLine(Modifier.padding(start = Spacing.lg))
            }
        }
    }
}

/** Одна відповідь рядком групового списку. Квадрат — можна кілька, коло — рівно одну. */
@Composable
private fun ChoiceRow(title: String, hint: String, selected: Boolean, multiple: Boolean, onClick: () -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth()
            .selectable(selected, role = if (multiple) Role.Checkbox else Role.RadioButton, onClick = onClick)
            .padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = colors.ink)
            Text(hint, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        Box(
            Modifier.size(24.dp)
                // Радіус явний, не токен: `Radius.xs` = 12 робив із квадрата 24 dp коло, і «кілька» не відрізнялось від «одну».
                .background(if (selected) colors.brand else colors.surfaceMuted, if (multiple) RoundedCornerShape(7.dp) else Radius.pill),
            contentAlignment = Alignment.Center
        ) {
            if (selected) Icon(Icons.Outlined.Check, null, Modifier.size(14.dp), tint = colors.onBrand)
        }
    }
}

/** Слоти зі спільного модуля з підписами, у порядку тижня. */
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
