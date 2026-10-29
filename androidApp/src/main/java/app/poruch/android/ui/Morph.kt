package app.poruch.android.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.node.LayoutAwareModifierNode
import androidx.compose.ui.node.ModifierNodeElement
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.toSize
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/*
 * «Квиток морфиться в екран» — один рух на весь застосунок: квиток, на який натиснули, розгортається на весь екран, і вже
 * під ним з'являється наступний екран; назад — квиток проступає над екраном і складається на своє місце. Квиток гаманця
 * стає квитком на весь екран, квиток події (будь-де: головна, мапа, «Мої події», артист, інші деталі) — деталями. Квиток не
 * збільшується картинкою, а перемірюється на кожному кадрі: папір і корінець справді ростуть, назва лишається читабельною.
 *
 * Новий екран з'являється під уже непрозорим квитком, а не одночасно з рухом: перший кадр деталей чи головної важкий
 * (на емуляторі — сотні мілісекунд), і перехід, що йшов би з ним, просто з'їдався. Без `SharedTransitionLayout`: його
 * lookahead на всю головну зациклював розмітку, і застосунок не відкривався.
 *
 * Куди складатись, квиток питає в самого джерела ([unfoldSource]) вже після того, як попередній екран розклався: межі з
 * моменту дотику після повороту, зміни списку чи прокрутки вели квиток повз його місце (аудит 1.4, Android, повторний).
 */

/**
 * Квиток у польоті: [id] — що він відкриває (подія чи квиток гаманця), [key] — його місце на екрані ([unfoldSource]): та сама
 * подія буває і в рейці, і в сітці. [ticket] — як він виглядає.
 */
class TicketFlight(val id: String, val key: String, val ticket: @Composable () -> Unit) {
    /** Де квиток лежав, коли його востаннє бачили. [Rect.Zero] — невідомо: розмітка інша (поворот). */
    internal var from = Rect.Zero
    /** Звідки квиток складається: де він був, коли почав (посеред жесту «Назад» — уже трохи складений). Null — весь екран. */
    internal var to: Rect? = null
}

/** Пружина морфу — та сама «одна пружина» застосунку (DESIGN.md, Motion). */
val MorphSpring: FiniteAnimationSpec<Float> =
    spring(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow, visibilityThreshold = 0.001f)

/**
 * Квиток-джерело морфу під ключем [key]. Тримає координати вузла, а межі [Unfold] рахує лише в мить польоту: не на кожен
 * кадр прокрутки, як `onGloballyPositioned`.
 */
fun Modifier.unfoldSource(key: String): Modifier = this then UnfoldSourceElement(key)

private data class UnfoldSourceElement(val key: String) : ModifierNodeElement<UnfoldSourceNode>() {
    override fun create() = UnfoldSourceNode(key)
    override fun update(node: UnfoldSourceNode) {
        // Той самий вузол тепер показує іншу подію (список перевикористав місце): реєстрація переїжджає за ним.
        Unfold.sources.remove(node.key)?.let { Unfold.sources[key] = it }
        node.key = key
    }
}

private class UnfoldSourceNode(var key: String) : Modifier.Node(), LayoutAwareModifierNode {
    private var placed: LayoutCoordinates? = null
    override fun onPlaced(coordinates: LayoutCoordinates) { placed = coordinates; Unfold.sources[key] = coordinates }
    // Лише свій запис: картка з тим самим ключем могла вже стати на місце (список перевикористав місце, повернення на екран).
    override fun onDetach() { placed?.let { Unfold.sources.remove(key, it) }; placed = null }
}

/**
 * Квиток події, що розгортається в деталі. [content] малює його з модифікатором-джерелом і тапом, який спершу кладе квиток у
 * [Unfold.pending]: деталі відкриває модель, і маршрут розгорне квиток, щойно вона скаже. Летить той самий [content] без тапу.
 * [origin] — звідки (рейка, сітка, мапа…). [bare] — рядок групи без свого паперу: летить на картці, як група.
 */
@Composable
fun UnfoldSource(
    id: String, origin: String, onClick: () -> Unit, bare: Boolean = false,
    content: @Composable (source: Modifier, open: () -> Unit) -> Unit
) {
    val key = "$origin:$id"
    content(Modifier.unfoldSource(key)) {
        Unfold.pending = TicketFlight(id, key) { if (bare) Box(Modifier.cardSurface()) { content(Modifier) {} } else content(Modifier) {} }
        onClick()
    }
}

/**
 * Розгортання й складання квитка. Живе на процес, як `WalletUi`: квиток на весь екран і деталі відкривають з різних
 * місць, а шар з квитком один ([UnfoldLayer]). Анімації йдуть у його області, з годинником кадрів.
 */
object Unfold {
    /** Квиток, що зараз видно над усім: розгортається, складається чи проступає під жестом «Назад». */
    var flight by mutableStateOf<TicketFlight?>(null)
        private set
    /**
     * Розгорнуті екрани й квитки, з яких вони виросли, за [TicketFlight.id]: на «Назад» квиток складеться туди. Кілька, бо
     * деталі відкривають з деталей, і кожні складаються у свій квиток. Найстаріші забуваються: ті просто закриються.
     */
    private val parked = LinkedHashMap<String, TicketFlight>()
    /** Квиток, натиснутий, поки модель ще не сказала відкрити деталі. */
    var pending: TicketFlight? = null
    /** Квитки-джерела на екрані за ключем ([unfoldSource]). */
    internal val sources = HashMap<String, LayoutCoordinates>()
    /** Де шар намалював квиток востаннє: складання починається звідти. */
    internal var drawn = Rect.Zero
    internal val progress = Animatable(0f)
    internal val alpha = Animatable(0f)
    internal var scope: CoroutineScope? = null
    internal var reduced = false
    private var job: Job? = null
    /** Що лишилось зробити, якщо шар зник посеред руху (поворот): показати чи прибрати екран. */
    private var owed: (() -> Unit)? = null

    /** Квиток складеться на «Назад» в екран [id]. */
    fun canFold(id: String?): Boolean = id != null && !reduced && scope != null && (flight?.id == id || id in parked)

    /** Квиток [id] зараз над усім: перехід під ним має бути миттєвим. */
    fun covers(id: String): Boolean = flight?.id == id

    /** [id] відкрили не квитком: його екран закривається звичайно, а не складається в колишній квиток. */
    fun forget(id: String) {
        if (flight?.id != id) parked.remove(id)
        pending = null
    }

    /** Розгорнути [ticket] на весь екран; коли він майже екран, [show] відкриває наступний екран під ним. */
    fun open(ticket: TicketFlight, show: () -> Unit) {
        val scope = scope
        pending = null
        // Джерела вже не видно (прогорнули, поки модель думала) — нема звідки розгортатись.
        val from = visible(ticket.key)
        if (reduced || scope == null || from == null) { parked.remove(ticket.id); show(); return }
        finish()
        ticket.from = from
        flight = ticket
        parked.remove(ticket.id)
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
            parked[ticket.id] = ticket
            if (parked.size > PARKED_MAX) parked.remove(parked.keys.first())
        }
    }

    /** Жест «Назад» на розгорнутому екрані [id]: квиток проступає над ним і трохи складається за пальцем. */
    suspend fun preview(id: String, fraction: Float) {
        val ticket = flight?.takeIf { it.id == id } ?: parked[id] ?: return
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
     * Скласти квиток екрана [id] назад: він стає непрозорим на весь екран, [hide] прибирає екран під ним, і квиток лягає
     * туди, де його джерело тепер. Джерела нема (прогорнули, зникло зі списку) — квиток згасає над попереднім екраном.
     * False — складати нема що (інший шлях, «зменшити рух»): закрий звичайно.
     */
    fun fold(id: String, hide: () -> Unit): Boolean {
        val scope = scope
        val ticket = flight?.takeIf { it.id == id } ?: parked[id]
        if (reduced || scope == null || ticket == null) return false
        parked.remove(id)
        job?.cancel()
        flight = ticket
        owed = hide
        job = scope.launch {
            if (alpha.value < 1f) alpha.animateTo(1f, tween((COVER_MS * (1f - alpha.value)).roundToInt()))
            pay()
            // Попередній екран розкладається під квитком кадр-два (головна — довше); джерело, яке ще не стало на місце,
            // чекаємо обмежено. Старих меж не беремо: після повороту вони з іншої розмітки.
            var at: Rect? = null
            var frames = 0
            while (frames < SETTLE_FRAMES || (at == null && frames < WAIT_FRAMES)) {
                withFrameNanos { }
                frames++
                at = visible(ticket.key)
            }
            if (at == null) alpha.animateTo(0f, tween(Motion.QUICK_MS))
            else {
                // Від того, де квиток зараз, а не від цілого екрана: після жесту він уже трохи складений, і стрибка нема.
                ticket.to = drawn
                ticket.from = at
                progress.snapTo(1f)
                progress.animateTo(0f, MorphSpring)
            }
            flight = null
        }
        return true
    }

    /** Межі джерела [key] у корені, якщо воно на екрані: ціле, хоч би й виглядало з-за краю списку. */
    internal fun visible(key: String): Rect? = sources[key]
        ?.takeIf { it.isAttached && !it.boundsInRoot().isEmpty }
        ?.let { Rect(it.positionInRoot(), it.size.toSize()) }

    private fun pay() {
        owed?.also { owed = null }?.invoke()
    }

    /** Шар зник посеред руху: те, що обіцяли, робимо одразу, квиток прибираємо. */
    internal fun finish() {
        job?.cancel()
        pay()
        flight = null
    }

    /** Шар зник разом з активністю (поворот): місця квитків — з тієї розмітки, жест «Назад» їх уже не знає. */
    internal fun detach() {
        scope = null
        finish()
        parked.values.forEach { it.from = Rect.Zero }
    }

    /** Наступний екран з'являється під квитком, коли той уже майже на весь екран. */
    private const val REVEAL_AT = 0.92f
    /** Наскільки квиток складається за пальцем і коли стає непрозорим. */
    private const val PREVIEW_FOLD = 0.12f
    private const val PREVIEW_OPAQUE_AT = 0.35f
    /** За скільки квиток накриває екран, коли «Назад» натиснули, а не повели жестом. */
    private const val COVER_MS = 120
    /** Кадрів, щоб відкритий екран намалювався під квитком, і скільки найдовше чекати на джерело. */
    private const val SETTLE_FRAMES = 2
    private const val WAIT_FRAMES = 12
    /** Скільки розгорнутих екранів пам'ятають свій квиток: глибше стек деталей рідко йде. */
    private const val PARKED_MAX = 8
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
        onDispose { Unfold.detach() }
    }
    val flight = Unfold.flight ?: return
    Box(
        Modifier.fillMaxSize().clearAndSetSemantics { }
            .layout { measurable, constraints ->
                val p = Unfold.progress.value.coerceIn(0f, 1f)
                val screen = Rect(0f, 0f, constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
                // Складаючись, квиток іде за джерелом: список під ним ще може доїхати (карусель мапи — до вибраної картки).
                if (flight.to != null) Unfold.visible(flight.key)?.let { flight.from = it }
                // Де квиток лежав, невідомо (активність перестворено) — жест «Назад» стискає його до центру.
                val from = flight.from.takeUnless { it.isEmpty } ?: Rect(screen.center, 0f)
                val rect = lerp(from, flight.to ?: screen, p).also { Unfold.drawn = it }
                val placeable = measurable.measure(
                    Constraints.fixed(rect.width.roundToInt().coerceAtLeast(1), rect.height.roundToInt().coerceAtLeast(1))
                )
                layout(constraints.maxWidth, constraints.maxHeight) { placeable.place(rect.left.roundToInt(), rect.top.roundToInt()) }
            }
            .graphicsLayer { alpha = Unfold.alpha.value },
        // Квиток бере рівно межі кадру, а не свій природний розмір.
        propagateMinConstraints = true
    ) {
        flight.ticket()
        // Квиток у польоті — картинка, а не кнопки: «Зберегти» й інші дії на ньому не натискаються.
        Spacer(Modifier.matchParentSize().pointerInput(Unit) { })
    }
}
