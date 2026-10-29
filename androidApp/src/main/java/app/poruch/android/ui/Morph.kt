package app.poruch.android.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.lerp
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Constraints
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/*
 * «Квиток морфиться в екран» — один рух на весь застосунок: квиток, на який натиснули, розгортається на весь екран, і вже
 * під ним з'являється наступний екран; назад — квиток проступає над екраном і складається на своє місце. Квиток гаманця
 * стає квитком на весь екран, квиток головної — деталями. Квиток не збільшується картинкою, а перемірюється на кожному
 * кадрі: папір і корінець справді ростуть, назва лишається читабельною.
 *
 * Новий екран з'являється під уже непрозорим квитком, а не одночасно з рухом: перший кадр деталей чи головної важкий
 * (на емуляторі — сотні мілісекунд), і перехід, що йшов би з ним, просто з'їдався. Без `SharedTransitionLayout`: його
 * lookahead на всю головну зациклював розмітку, і застосунок не відкривався.
 */

/** Квиток у польоті: [key] — чий (подія чи квиток гаманця), [from] — його межі в корені, [ticket] — як він виглядає. */
class TicketFlight(val key: String, val from: Rect, val ticket: @Composable () -> Unit)

/** Пружина морфу — та сама «одна пружина» застосунку (DESIGN.md, Motion). */
val MorphSpring: FiniteAnimationSpec<Float> =
    spring(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow, visibilityThreshold = 0.001f)

/** Межі квитка в корені: звідки він розгорнеться. Простий тримач, а не стан — позиція не перескладає список. */
class Bounds { var rect: Rect = Rect.Zero }

fun Modifier.trackBounds(bounds: Bounds): Modifier = onGloballyPositioned { bounds.rect = it.boundsInRoot() }

/**
 * Розгортання й складання квитка. Живе на процес, як `WalletUi`: квиток на весь екран і деталі відкривають з різних
 * місць, а шар з квитком один ([UnfoldLayer]). Анімації йдуть у його області, з годинником кадрів.
 */
object Unfold {
    /** Квиток, що зараз видно над усім: розгортається, складається чи проступає під жестом «Назад». */
    var flight by mutableStateOf<TicketFlight?>(null)
        private set
    /** Розгорнутий екран і квиток, з якого він виріс: на «Назад» квиток складеться туди. */
    var parked: TicketFlight? = null
        private set
    /** Квиток головної, натиснутий, поки модель ще не сказала відкрити деталі. */
    var pending: TicketFlight? = null
    internal val progress = Animatable(0f)
    internal val alpha = Animatable(0f)
    internal var scope: CoroutineScope? = null
    internal var reduced = false
    private var job: Job? = null
    /** Що лишилось зробити, якщо шар зник посеред руху (поворот): показати чи прибрати екран. */
    private var owed: (() -> Unit)? = null

    /** Квиток складеться на «Назад» у [key]. */
    fun canFold(key: String?): Boolean = key != null && !reduced && scope != null && (parked?.key == key || flight?.key == key)

    /** Квиток [key] зараз над усім: перехід під ним має бути миттєвим. */
    fun covers(key: String): Boolean = flight?.key == key

    fun forget() {
        if (flight == null) parked = null
        pending = null
    }

    /** Розгорнути [ticket] на весь екран; коли він майже екран, [show] відкриває наступний екран під ним. */
    fun open(ticket: TicketFlight, show: () -> Unit) {
        val scope = scope
        pending = null
        if (reduced || scope == null || ticket.from.isEmpty) { parked = null; show(); return }
        finish()
        flight = ticket
        parked = null
        owed = show
        job = scope.launch {
            alpha.snapTo(1f)
            progress.snapTo(0f)
            var reveal: Job? = null
            // Екран під квитком — щойно той майже на весь екран; перший кадр нового екрана важкий, тож квиток гасне,
            // коли той уже намалювався, і поки сам ще доростає.
            fun revealOnce() {
                if (reveal != null) return
                pay()
                reveal = launch { repeat(2) { withFrameNanos { } }; alpha.animateTo(0f, tween(Motion.QUICK_MS)) }
            }
            progress.animateTo(1f, MorphSpring) { if (value >= REVEAL_AT) revealOnce() }
            revealOnce()
            reveal?.join()
            flight = null
            parked = ticket
        }
    }

    /** Жест «Назад» на розгорнутому екрані: квиток проступає над ним і трохи складається за пальцем. */
    suspend fun preview(fraction: Float) {
        val ticket = parked ?: flight ?: return
        if (flight == null) { job?.cancel(); flight = ticket }
        progress.snapTo(1f - PREVIEW_FOLD * fraction)
        alpha.snapTo((fraction / PREVIEW_OPAQUE_AT).coerceIn(0f, 1f))
    }

    /** Жест скасували: квиток зникає, екран лишається. */
    suspend fun cancelPreview() {
        alpha.animateTo(0f, tween(Motion.QUICK_MS))
        progress.snapTo(1f)
        flight = null
    }

    /**
     * Скласти квиток [key] назад: він стає непрозорим на весь екран, [hide] прибирає екран під ним, і квиток лягає на
     * своє місце в списку. False — складати нема куди (інший шлях, «зменшити рух»): закрий звичайно.
     */
    fun fold(key: String, hide: () -> Unit): Boolean {
        val scope = scope
        val ticket = (parked ?: flight)?.takeIf { it.key == key }
        if (reduced || scope == null || ticket == null) return false
        job?.cancel()
        flight = ticket
        owed = hide
        job = scope.launch {
            if (alpha.value < 1f) alpha.animateTo(1f, tween((COVER_MS * (1f - alpha.value)).roundToInt()))
            pay()
            repeat(2) { withFrameNanos { } }
            progress.animateTo(0f, MorphSpring)
            flight = null
            parked = null
        }
        return true
    }

    private fun pay() {
        owed?.also { owed = null }?.invoke()
    }

    /** Шар зник посеред руху: те, що обіцяли, робимо одразу, квиток прибираємо. */
    internal fun finish() {
        job?.cancel()
        pay()
        flight = null
    }

    /** Наступний екран з'являється під квитком, коли той уже майже на весь екран. */
    private const val REVEAL_AT = 0.92f
    /** Наскільки квиток складається за пальцем і коли стає непрозорим. */
    private const val PREVIEW_FOLD = 0.12f
    private const val PREVIEW_OPAQUE_AT = 0.35f
    /** За скільки квиток накриває екран, коли «Назад» натиснули, а не повели жестом. */
    private const val COVER_MS = 120
}

/**
 * Шар з квитком над усім застосунком. Квиток між своїм місцем і цілим екраном: читається в розмітці й малюванні, не в
 * композиції, тож рух не перескладає ні екран, ні квиток. Для TalkBack його нема: екрани під ним кажуть самі.
 */
@Composable
fun UnfoldLayer() {
    val scope = rememberCoroutineScope()
    val reduced = Poruch.reducedMotion
    DisposableEffect(scope, reduced) {
        Unfold.scope = scope
        Unfold.reduced = reduced
        onDispose { Unfold.scope = null; Unfold.finish() }
    }
    val flight = Unfold.flight ?: return
    Box(
        Modifier.fillMaxSize().clearAndSetSemantics { }
            .layout { measurable, constraints ->
                val p = Unfold.progress.value.coerceIn(0f, 1f)
                val screen = Rect(0f, 0f, constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
                val rect = lerp(flight.from, screen, p)
                val placeable = measurable.measure(
                    Constraints.fixed(rect.width.roundToInt().coerceAtLeast(1), rect.height.roundToInt().coerceAtLeast(1))
                )
                layout(constraints.maxWidth, constraints.maxHeight) { placeable.place(rect.left.roundToInt(), rect.top.roundToInt()) }
            }
            .graphicsLayer { alpha = Unfold.alpha.value },
        // Квиток бере рівно межі кадру, а не свій природний розмір.
        propagateMinConstraints = true
    ) { flight.ticket() }
}
