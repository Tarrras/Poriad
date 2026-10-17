package app.poruch.android.feature.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.domain.EventCategory
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
            val scroll = rememberScrollState()
            BoxWithConstraints(Modifier.fillMaxSize().moreBelow(scroll, colors.canvas)) {
                Column(
                    // Вміст не нижчий за вікно, інакше центрувати нема в чому: вітання — по центру, питання — від верху.
                    Modifier.fillMaxWidth().verticalScroll(scroll).heightIn(min = maxHeight).padding(top = Spacing.lg),
                    verticalArrangement = if (step == OnboardingStep.WELCOME) Arrangement.Center
                    else Arrangement.spacedBy(Spacing.xl)
                ) {
                    when (step) {
                        OnboardingStep.WELCOME -> Welcome()
                        OnboardingStep.INTERESTS -> Interests(state, onIntent)
                        OnboardingStep.TIMES -> Times(state, onIntent)
                        OnboardingStep.CROWD -> CrowdStep(state, onIntent)
                    }
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
            IconPill(PoruchIcons.arrowLeft, stringResource(R.string.back), size = 40.dp) {
                onIntent(OnboardingIntent.Back)
            }
            Row(
                Modifier.weight(1f).clearAndSetSemantics { contentDescription = stepLabel },
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
            ) {
                (1..state.questionCount).forEach { index ->
                    Box(
                        Modifier.weight(1f).height(4.dp)
                            .background(if (index <= state.questionNumber) colors.brand else colors.inkTertiary.copy(alpha = 0.5f), Radius.pill)
                    )
                }
            }
        } else Spacer(Modifier.weight(1f))
        GhostButton(stringResource(R.string.onboarding_skip), { onIntent(OnboardingIntent.Skip) }, tone = colors.inkSecondary)
    }
}

/** Вітання: перший квиток «Поряд» — слоган надруковано, решта ще порожня, корінці фарбують жанри. */
@Composable
private fun Welcome() {
    val colors = Poruch.colors
    Column(
        Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.section)
    ) {
        WelcomeTicket()
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            Text(
                stringResource(R.string.onboarding_welcome_title), style = PoruchType.brandTitle2, color = colors.ink,
                modifier = Modifier.semantics { heading() }
            )
            Text(
                stringResource(R.string.onboarding_welcome_body),
                style = PoruchType.lead, color = colors.inkSecondary, textAlign = TextAlign.Center
            )
        }
    }
}

/**
 * Перший квиток: вертикальний, як «Від людей». Слоган надруковано, нижче — незадруковані рядки: решту допишуть відповіді.
 * Корінець розрізано на п'ять, кожен залитий кольором жанру з його гліфом — видно, про що застосунок.
 */
@Composable
private fun WelcomeTicket() {
    val colors = Poruch.colors
    Ticket(
        colors.canvas,
        stub = {
            Row(Modifier.fillMaxSize().clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                welcomeGenres.forEach { genre ->
                    Box(Modifier.weight(1f).fillMaxHeight().background(categoryStub(genre)), contentAlignment = Alignment.Center) {
                        Icon(categoryIcon(genre), null, Modifier.size(22.dp), tint = Color.White)
                    }
                }
            }
        },
        modifier = Modifier.widthIn(max = 320.dp).fillMaxWidth().height(IntrinsicSize.Min),
        vertical = true, stubLength = 64.dp, radius = Corner.lg
    ) {
        Column(Modifier.padding(Spacing.xl), verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
            Text(stringResource(R.string.onboarding_slogan), style = PoruchType.brandDisplay, color = colors.ink)
            Column(Modifier.clearAndSetSemantics { }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(112.dp, 6.dp).background(colors.hairline, Radius.pill))
                Box(Modifier.size(68.dp, 6.dp).background(colors.hairline, Radius.pill))
            }
        }
    }
}

private val welcomeGenres = listOf(
    EventCategory.MUSIC, EventCategory.FOOD, EventCategory.SOCIAL, EventCategory.OUTDOORS, EventCategory.GAMES
)

/** Нижче є ще вміст — край над кнопкою тане в полотно, щоб останній ряд не здавався кінцем. */
private fun Modifier.moreBelow(scroll: ScrollState, canvas: Color) = drawWithContent {
    drawContent()
    if (scroll.canScrollForward) {
        val fade = 32.dp.toPx()
        drawRect(Brush.verticalGradient(listOf(Color.Transparent, canvas), startY = size.height - fade, endY = size.height),
            topLeft = Offset(0f, size.height - fade))
    }
}

@Composable
private fun Question(title: String, hint: String, content: @Composable ColumnScope.() -> Unit) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(title, style = PoruchType.brandDisplay, color = colors.ink)
            Text(hint, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
        }
        content()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Interests(state: OnboardingState, onIntent: (OnboardingIntent) -> Unit) {
    Question(stringResource(R.string.onboarding_interests_title), stringResource(R.string.onboarding_interests_hint)) {
        // Ті самі плитки, що в шторці категорій. Плитка сама тримає 8 dp ціллю зверху й знизу, тож рядам проміжок не
        // потрібен: на 360 dp чотири в ряд — усі одинадцять видно без прокрутки.
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            categories.forEach { category ->
                CategoryTile(category, category in state.interests) { onIntent(OnboardingIntent.ToggleInterest(category)) }
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
        // Радіус явний, не токен: `Radius.xs` = 12 робив із квадрата 24 dp коло, і «кілька» не відрізнялось від «одну».
        val mark = if (multiple) RoundedCornerShape(7.dp) else Radius.pill
        Box(
            Modifier.size(24.dp)
                // Невибране — контуром: тиха заливка вночі зливалась із рядком (1,2:1), і не було видно, що тут щось обирають.
                .then(if (selected) Modifier.background(colors.brand, mark) else Modifier.border(1.5.dp, colors.inkTertiary, mark)),
            contentAlignment = Alignment.Center
        ) {
            if (selected) Icon(PoruchIcons.check, null, Modifier.size(14.dp), tint = colors.onBrand)
        }
    }
}

/** Слоти зі спільного модуля з підписами, у порядку тижня: будні, потім вихідні, у кожних — день, потім вечір. */
private val timeSlots = listOf(
    TimeSlot.WEEKDAY_DAY to (R.string.slot_weekday_day to R.string.slot_weekday_day_hint),
    TimeSlot.WEEKDAY_EVENING to (R.string.slot_weekday_evening to R.string.slot_weekday_evening_hint),
    TimeSlot.WEEKEND_DAY to (R.string.slot_weekend_day to R.string.slot_weekend_day_hint),
    TimeSlot.WEEKEND_EVENING to (R.string.slot_weekend_evening to R.string.slot_weekend_evening_hint)
)

private val crowds = listOf(
    Crowd.INTIMATE to (R.string.crowd_intimate to R.string.crowd_intimate_hint),
    Crowd.MEDIUM to (R.string.crowd_medium to R.string.crowd_medium_hint),
    Crowd.ANY to (R.string.crowd_any to R.string.crowd_any_hint)
)
