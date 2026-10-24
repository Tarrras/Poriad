package app.poruch.android.ui

import android.content.Context
import android.view.HapticFeedbackConstants
import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateRectAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.toSize
import androidx.core.content.edit
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import app.poruch.android.R
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.delay
import org.koin.compose.koinInject
import kotlin.math.max
import kotlin.math.min

/**
 * Підказки першого знайомства (docs/coach-marks.md): прожектор на справжньому елементі екрана й картка
 * з одним реченням про нього. Ніяких закликів — лише що це і що станеться після тапу.
 */
enum class CoachTip(val key: String, @StringRes val title: Int, @StringRes val body: Int) {
    CITY("city", R.string.tip_city_title, R.string.tip_city_body),
    MAP("map", R.string.tip_map_title, R.string.tip_map_body),
    CREATE("create", R.string.tip_create_title, R.string.tip_create_body),
    COMPANION("companion", R.string.tip_companion_title, R.string.tip_companion_body),
    INVITE("invite", R.string.tip_invite_title, R.string.tip_invite_body),
    SHEET("sheet", R.string.tip_sheet_title, R.string.tip_sheet_body)
}

/**
 * Де зараз елементи з підказками, у координатах вікна. Пише [coachTarget], читає лише відкритий прожектор:
 * прокрутка головної не перескладає нічого, поки підказки не видно. Власник — щоб зникнення старих деталей
 * не стерло рамку нових, що вже зʼявились на тому самому місці.
 */
private data class Placed(val owner: Any, val rect: Rect, val whole: Boolean, val corner: Dp?)

private val frames = mutableStateMapOf<CoachTip, Placed>()

/** Ціль цілком на екрані: підказка ніколи не вказує на те, що прокрутили чи сховали. */
private fun visible(tip: CoachTip, width: Int, height: Int): Boolean {
    val placed = frames[tip] ?: return false
    val rect = placed.rect
    return placed.whole && rect.width > 0 && rect.left >= 0 && rect.top >= 0 && rect.right <= width && rect.bottom <= height
}

/**
 * Елемент, на який може вказати підказка [tip]. `null` — нічого не робить (пункт таббару без підказки).
 * [cornerRadius] — для прямокутної цілі (картка, рядок); без нього виріз — капсула, як у кнопки.
 */
@Composable
fun Modifier.coachTarget(tip: CoachTip?, cornerRadius: Dp? = null): Modifier {
    if (tip == null) return this
    val owner = remember { Any() }
    DisposableEffect(tip) { onDispose { if (frames[tip]?.owner === owner) frames.remove(tip) } }
    return onGloballyPositioned {
        val size = it.size.toSize()
        // Обрізана батьком (стрічка прокрутила шапку під край) — не ціла, підказка її пропустить.
        val bounds = it.boundsInWindow()
        frames[tip] = Placed(
            owner,
            Rect(it.positionInWindow(), size),
            bounds.width >= size.width - 1 && bounds.height >= size.height - 1,
            cornerRadius
        )
    }
}

/** Той самий файл, що й питання застосунку в `MainActivity`: усе «показано раз» лежить разом. */
private const val PREFS = "prompts"
private fun Context.seen(tip: CoachTip) =
    getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("tip.${tip.key}", false)

private fun Context.markSeen(tips: List<CoachTip>) =
    getSharedPreferences(
        PREFS,
        Context.MODE_PRIVATE
    ).edit { tips.forEach { putBoolean("tip.${it.key}", true) } }

/**
 * Показує [tips] по черзі над екраном, поки [enabled]: за 1,2 с після появи, лише коли застосунок на
 * передньому плані (не під системним питанням про геолокацію), без уже бачених і тих, чиєї цілі не видно.
 * Перерваний тур (екран сховали) продовжується з тієї ж підказки. «Назад» — пропустити.
 * Кладеться останнім у `Box` на весь екран.
 */
@Composable
fun CoachMarks(tips: List<CoachTip>, enabled: Boolean, onFinish: () -> Unit = {}) {
    val context = LocalContext.current
    val view = LocalView.current
    val app = koinInject<PoruchApp>()
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val active = enabled && lifecycle.isAtLeast(Lifecycle.State.RESUMED)
    var tour by remember { mutableStateOf(emptyList<CoachTip>()) }
    var step by remember { mutableIntStateOf(0) }
    // Раз, коли тур пройдено, пропущено чи нема що показати: після нього можна ставити наступне питання.
    var finished by remember { mutableStateOf(false) }
    val onFinished by rememberUpdatedState(onFinish)
    val finish = {
        if (!finished) {
            finished = true; onFinished()
        }
    }
    LaunchedEffect(active) {
        if (!active || tour.isNotEmpty() || finished) return@LaunchedEffect
        delay(1_200)
        tour = tips.filter {
            !context.seen(it) && visible(
                it,
                view.rootView.width,
                view.rootView.height
            )
        }
        if (tour.isEmpty()) finish()
    }
    val next = next@{
        // Другий тап по притемненню, що вже тане, приходить, коли тур скінчився.
        if (step >= tour.size) return@next
        val tip = tour[step]
        context.markSeen(listOf(tip))
        app.tipAnswered(tip.key, if (step == tour.lastIndex) "done" else "next")
        // Ціль наступної могла зникнути, поки читали цю: пропускаємо, а не вказуємо в порожнечу.
        var following = step + 1
        while (following < tour.size && !visible(
                tour[following],
                view.rootView.width,
                view.rootView.height
            )
        ) following++
        if (following < tour.size) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) else finish()
        step = following
    }
    val skip = skip@{
        if (step >= tour.size) return@skip
        context.markSeen(tour.drop(step))
        app.tipAnswered(tour[step].key, "skip")
        step = tour.size
        finish()
    }
    val shown = enabled && step < tour.size
    BackHandler(shown, skip)
    AnimatedVisibility(shown, enter = fadeIn(tween(300)), exit = fadeOut(tween(250))) {
        // На виході `step` уже за краєм: дограємо останню підказку.
        CoachOverlay(tour, step.coerceAtMost(tour.lastIndex), next, skip)
    }
}

/** Притемнення з вирізом під ціль, кільце, що мʼяко розходиться, і картка зі стрілкою до цілі. */
@Composable
private fun CoachOverlay(tour: List<CoachTip>, step: Int, next: () -> Unit, skip: () -> Unit) {
    val colors = Poruch.colors
    val reducedMotion = Poruch.reducedMotion
    val density = LocalDensity.current
    val onNext by rememberUpdatedState(next)
    var origin by remember { mutableStateOf(Offset.Zero) }
    // Перший кадр: виріз ширший за ціль і стягується на неї, картка виринає зі стрілки.
    var focused by remember { mutableStateOf(reducedMotion) }
    LaunchedEffect(Unit) { focused = true }
    val placed = frames[tour[step]]
    val hole = (placed?.rect ?: Rect.Zero).translate(-origin).inflate(with(density) { 6.dp.toPx() })
    // Виріз на 6 dp ширший за ціль, тож і кут на 6 dp більший: краї лишаються паралельні.
    val corner = placed?.corner?.let { with(density) { (it + 6.dp).toPx() } } ?: (hole.height / 2)
    val reach = with(density) { 56.dp.toPx() }
    val motion = if (reducedMotion) tween<Float>(250) else spring(
        dampingRatio = 0.8f,
        stiffness = Spring.StiffnessLow
    )
    val spot by animateRectAsState(
        if (focused) hole else hole.inflate(reach),
        if (reducedMotion) tween(250) else spring(
            dampingRatio = 0.8f,
            stiffness = Spring.StiffnessLow
        ),
        label = "spotlight"
    )
    val spotCorner by animateFloatAsState(
        if (focused) corner else corner + reach,
        motion,
        label = "corner"
    )
    val pulse by rememberInfiniteTransition(label = "ring").animateFloat(
        0f,
        1f,
        infiniteRepeatable(tween(1_500, easing = FastOutSlowInEasing), RepeatMode.Restart),
        label = "pulse"
    )
    val dim = Color.Black.copy(alpha = if (colors.dark) 0.62f else 0.45f)
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned { origin = it.positionInWindow() }) {
        Canvas(
            Modifier
                .fillMaxSize()
                .pointerInput(Unit) { detectTapGestures { onNext() } }
                .clearAndSetSemantics { }
        ) {
            val cutout = Path().apply {
                fillType = PathFillType.EvenOdd
                addRect(Rect(Offset.Zero, size))
                addRoundRect(RoundRect(spot, CornerRadius(spotCorner)))
            }
            drawPath(cutout, dim)
            // Кільце довкола вирізу: розходиться й тане, як коло на воді. Показує, куди дивитись, без миготіння.
            if (!reducedMotion && focused) {
                val spread = 12.dp.toPx() * pulse
                val ring = spot.inflate(spread)
                drawRoundRect(
                    Color.White.copy(alpha = 0.7f * (1 - pulse)), ring.topLeft, ring.size,
                    CornerRadius(spotCorner + spread), Stroke(2.dp.toPx())
                )
            }
        }
        val page = with(density) { Spacing.page.toPx() }
        val width = min(with(density) { 340.dp.toPx() }, constraints.maxWidth - 2 * page)
        AnimatedContent(
            step,
            Modifier.fillMaxSize(),
            transitionSpec = {
                (fadeIn(tween(220, delayMillis = 90)) + scaleIn(
                    tween(220, delayMillis = 90),
                    initialScale = 0.94f
                )) togetherWith
                        fadeOut(tween(120)) using SizeTransform(clip = false)
            },
            label = "tip"
        ) { shownStep ->
            val shownHole = (frames[tour[shownStep]]?.rect ?: Rect.Zero).translate(-origin)
                .inflate(with(density) { 6.dp.toPx() })
            val below = shownHole.center.y < constraints.maxHeight / 2
            // Запасу менше за поле — картка стоїть по центру, а не з'їжджає на кілька dp від кроку до кроку.
            val free = constraints.maxWidth - 2 * page - width
            val x = if (free < page) (constraints.maxWidth - width) / 2
            else shownHole.center.x.minus(width / 2).coerceIn(page, max(page, constraints.maxWidth - page - width))
            // Стрілка навпроти центру цілі, але на прямому краї, а не на заокругленні кута картки.
            val corner = with(density) { 31.dp.toPx() }
            val arrowX = (shownHole.center.x - x).coerceIn(corner, width - corner)
            val gap = with(density) { 10.dp.toPx() }
            val appear by animateFloatAsState(
                if (focused) 1f else 0f,
                spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow),
                label = "appear"
            )
            CoachBubble(
                tour[shownStep],
                shownStep,
                tour.size,
                with(density) { arrowX.toDp() },
                below,
                next,
                skip,
                Modifier
                    .layout { measurable, _ ->
                        val placeable = measurable.measure(Constraints.fixedWidth(width.toInt()))
                        val y =
                            if (below) shownHole.bottom + gap else shownHole.top - gap - placeable.height
                        layout(
                            constraints.maxWidth,
                            constraints.maxHeight
                        ) { placeable.place(x.toInt(), y.toInt()) }
                    }
                    .graphicsLayer {
                        val scale = if (reducedMotion) 1f else 0.9f + 0.1f * appear
                        scaleX = scale; scaleY = scale
                        alpha = if (reducedMotion) 1f else appear
                        transformOrigin = TransformOrigin(arrowX / width, if (below) 0f else 1f)
                    }
            )
        }
    }
}

/** Картка підказки: назва кондензом, одне речення, риски кроків, «Пропустити» і «Далі». Одна підказка — лише «Зрозуміло». */
@Composable
private fun CoachBubble(
    tip: CoachTip, index: Int, count: Int, arrowX: Dp, below: Boolean,
    next: () -> Unit, skip: () -> Unit, modifier: Modifier
) {
    val colors = Poruch.colors
    val last = index == count - 1
    Column(modifier) {
        if (below) Arrow(up = true, arrowX)
        Column(
            Modifier
                .shadow(
                    Elevation.overlay,
                    Radius.md,
                    clip = false,
                    ambientColor = colors.shadowAmbient,
                    spotColor = colors.shadowSpot
                )
                .background(colors.surfaceRaised, Radius.md)
                .padding(Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(
                    stringResource(tip.title),
                    style = PoruchType.brandTitle3,
                    color = colors.ink,
                    modifier = Modifier.semantics { heading() })
                Text(
                    stringResource(tip.body),
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.inkSecondary
                )
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                if (count > 1) Steps(index, count)
                Spacer(Modifier.weight(1f))
                if (!last) GhostButton(
                    stringResource(R.string.onboarding_skip),
                    skip,
                    tone = colors.inkSecondary
                )
                Box(
                    Modifier
                        .heightIn(min = 40.dp)
                        // Кут квитка, як у кожної кнопки застосунку: пігулки — лише чипи, бейджі, пошук і таббар.
                        .background(colors.brand, ButtonShape)
                        .pressable(shape = ButtonShape, pressedScale = 0.95f, onClick = next)
                        .padding(horizontal = Spacing.xl, vertical = Spacing.sm),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        stringResource(if (last) R.string.tip_done else R.string.next),
                        style = MaterialTheme.typography.labelLarge,
                        color = colors.onBrand
                    )
                }
            }
        }
        if (!below) Arrow(up = false, arrowX)
    }
}

/** Поточна — довшою рискою, як прогрес онбордингу. */
@Composable
private fun Steps(index: Int, count: Int) {
    val colors = Poruch.colors
    val description = stringResource(R.string.tip_step, index + 1, count)
    Row(
        Modifier.clearAndSetSemantics { contentDescription = description },
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        repeat(count) { position ->
            Box(
                Modifier
                    .size(width = if (position == index) 16.dp else 6.dp, height = 6.dp)
                    .background(
                        // Решта — притишеним третім чорнилом: тонова плашка на піднятій картці вночі зливалась.
                        if (position == index) colors.brand else colors.inkTertiary.copy(alpha = 0.5f),
                        Radius.pill
                    )
            )
        }
    }
}

/** Вістря до цілі; −1 dp заходить під картку, без волосяної щілини між ними. */
@Composable
private fun Arrow(up: Boolean, x: Dp) {
    val fill = Poruch.colors.surfaceRaised
    Canvas(
        Modifier
            .padding(start = x - 9.dp)
            .width(18.dp)
            .height(9.dp)
            .graphicsLayer {
                translationY = (if (up) 1 else -1).dp.toPx(); rotationZ = if (up) 180f else 0f
            }
    ) {
        val path = Path().apply {
            moveTo(0f, 0f)
            quadraticTo(size.width / 2, size.height * 2, size.width, 0f)
            close()
        }
        drawPath(path, fill)
    }
}
