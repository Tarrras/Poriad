package app.poruch.android.ui

import android.annotation.SuppressLint
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.toRect
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Density
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.domain.Attendee
import app.poruch.domain.Event
import com.amplitude.android.sessionreplay.compose.ampBlock
import coil3.compose.AsyncImage

/**
 * Форма квитка: скруглений прямокутник із двома півкруглими вирізами на лінії відриву. [stub] — довжина корінця від
 * кінцевого краю: праворуч у горизонтального квитка, знизу у вертикального. [punched] — подія минула: кругла дірка в корінці.
 */
data class TicketShape(
    val stub: Dp,
    val vertical: Boolean = false,
    val radius: Dp = Corner.md,
    val notch: Dp = 7.dp,
    val punched: Boolean = false
) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline = with(density) {
        val cuts = Path()
        fun hole(x: Float, y: Float, r: Dp) = cuts.addOval(Rect(Offset(x, y), r.toPx()))
        val length = stub.toPx()
        if (vertical) {
            val y = size.height - length
            hole(0f, y, notch); hole(size.width, y, notch)
            if (punched) hole(size.width - 18.dp.toPx(), size.height - length / 2, 5.dp)
        } else {
            val x = size.width - length
            hole(x, 0f, notch); hole(x, size.height, notch)
            if (punched) hole(size.width - length / 2, 16.dp.toPx(), 5.dp)
        }
        val body = Path().apply { addRoundRect(RoundRect(size.toRect(), CornerRadius(radius.toPx()))) }
        Outline.Generic(Path.combine(PathOperation.Difference, body, cuts))
    }
}

/**
 * Квиток — головний предмет застосунку: основна частина на поверхні й корінець, залитий кольором жанру, за перфорацією.
 * Афішна подія — надрукований квиток із часом на корінці, зустріч від людей — квиток ще й з місцями. Обидві частини
 * тягнуться на висоту довшої, тож висоту задає вміст, а не місце виклику.
 */
@Composable
fun Ticket(
    stubColor: Color,
    stub: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    vertical: Boolean = false,
    stubLength: Dp = 84.dp,
    radius: Dp = Corner.md,
    punched: Boolean = false,
    surface: Color = Poruch.colors.surface,
    /** Тінь того, що плаває: каруселі над мапою, панелі дії. */
    elevation: Dp = 0.dp,
    /** Контур тією ж формою: пунктир порожнього квитка (1,5 dp) чи суцільна рамка вибраного на мапі (2 dp). */
    outline: Color? = null,
    dashed: Boolean = true,
    onClick: (() -> Unit)? = null,
    main: @Composable () -> Unit
) {
    val colors = Poruch.colors
    // Корінець росте з кеглем цифр, до півтора раза: інакше великий шрифт стискав би час до нечитабельного.
    val length = stubLength * LocalDensity.current.fontScale.coerceIn(1f, 1.5f)
    val shape = TicketShape(length, vertical, radius, punched = punched)
    val ticket = modifier
        .then(
            if (elevation > 0.dp) Modifier.shadow(elevation, shape, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot)
            else Modifier
        )
        .then(if (onClick != null) Modifier.pressable(shape = shape, onClick = onClick) else Modifier)
        // Уночі край тримає волосина: квиток лише трохи світліший за полотно.
        .then(if (colors.dark) Modifier.border(1.dp, colors.hairline, shape) else Modifier)
        .clip(shape)
        // Перфорація на лінії відриву: крапки кольору полотна, ніби дірочки наскрізь.
        .drawWithContent {
            drawContent()
            val inset = 11.dp.toPx()
            val at = (if (vertical) size.height else size.width) - length.toPx()
            perforation(
                colors.canvas,
                if (vertical) Offset(inset, at) else Offset(at, inset),
                if (vertical) Offset(size.width - inset, at) else Offset(at, size.height - inset)
            )
            // Контур малюється під обрізкою, тож видно внутрішню половину: ширина подвоєна.
            if (outline != null) drawOutline(
                shape.createOutline(size, layoutDirection, this), outline,
                style = Stroke(
                    (if (dashed) 1.5.dp else 2.dp).toPx() * 2,
                    pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx())) else null
                )
            )
        }
    // Вертикальний квиток тягнеться на висоту ряду: її задає місце виклику (`IntrinsicSize.Min` і `fillMaxHeight`).
    if (vertical) Column(ticket) {
        Box(Modifier.fillMaxWidth().weight(1f).background(surface)) { main() }
        Box(Modifier.fillMaxWidth().height(length).background(stubColor), contentAlignment = Alignment.Center) { stub() }
    } else Row(ticket.height(IntrinsicSize.Min)) {
        Box(Modifier.weight(1f).fillMaxHeight().background(surface)) { main() }
        Box(Modifier.width(length).fillMaxHeight().background(stubColor), contentAlignment = Alignment.Center) { stub() }
    }
}

/** Перфорація на лінії відриву: крапки кольору полотна на кроці 6, ніби дірочки наскрізь. */
internal fun DrawScope.perforation(color: Color, start: Offset, end: Offset) = drawLine(
    color, start, end, strokeWidth = 2.5.dp.toPx(), cap = StrokeCap.Round,
    pathEffect = PathEffect.dashPathEffect(floatArrayOf(0.1.dp.toPx(), 6.dp.toPx()))
)

/** Лінія відриву поза квитком: та сама перфорація ділить поле «Коли» на день і годину. Нульової ширини — стоїть між частинами. */
@Composable
fun TearLine() {
    val canvas = Poruch.colors.canvas
    Spacer(
        Modifier.fillMaxHeight().width(0.dp).drawBehind {
            val inset = 11.dp.toPx()
            perforation(canvas, Offset(0f, inset), Offset(0f, size.height - inset))
        }
    )
}

/** Чому квиток тут — тихим рядком: «Для вас», за ким стежите, «Від людей». Штамп лишається лише для стану квитка. */
@Composable
fun ReasonLine(text: String, icon: ImageVector, modifier: Modifier = Modifier) {
    val color = Poruch.colors.inkTertiary
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(12.dp), tint = color)
        Text(text, style = MaterialTheme.typography.bodySmall, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** «Збирає Тарас» — хто друкує квиток зустрічі. Нема імені (організатор без публічного профілю) — рядка нема. */
@Composable
fun hostLine(event: Event): String? =
    event.gathering?.organizerName?.takeIf { it.isNotBlank() }?.let { stringResource(R.string.hosted_by, it) }

/** Рядок «видавця» на квитку зустрічі: аватар і «Збирає Тарас». Від людей — отже, з людиною на квитку. */
@Composable
fun HostLine(event: Event, modifier: Modifier = Modifier) {
    val line = hostLine(event) ?: return
    val name = event.gathering?.organizerName.orEmpty()
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(name, null, 20.dp)
        Text(line, style = MaterialTheme.typography.bodySmall, color = Poruch.colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Що читає TalkBack на квитку: одне речення в незмінному порядку — назва, жанр, місце, коли, місця, стан.
 * Порядок накладок (штамп, «Зберегти», ціна) на нього не впливає, а жанр звучить словом: колір корінця не озвучується.
 * Те саме, що `ticketA11yLabel` на iOS.
 */
@Composable
fun ticketA11yLabel(event: Event, state: String? = null): String {
    val words = dateWords()
    val time = remember(event, words) { eventTime(event, words) }
    val category = stringResource(categoryLabel(event.category))
    val seats = event.gathering?.takeIf { !event.hasEnded(kotlin.time.Clock.System.now()) }
        ?.let { stringResource(R.string.attendees, it.attendeeCount, it.capacity) }
    return listOfNotNull(event.displayTitle, hostLine(event), category, event.placeLabel, time, seats, state)
        .filter { it.isNotBlank() }.joinToString(", ")
}

/**
 * Квиток для TalkBack — одна кнопка з [ticketA11yLabel], а «Зберегти» — власна дія, а не окрема зупинка між штампом
 * і назвою. [status] — непрочитане чи інший стан, що змінюється без зміни самого квитка.
 */
@SuppressLint("ComposableModifierFactory")
@Composable
fun Modifier.ticketSemantics(
    label: String, onClick: () -> Unit, saved: Boolean = false, onSave: (() -> Unit)? = null,
    status: String? = null, selected: Boolean = false
): Modifier {
    val saveLabel = stringResource(if (saved) R.string.unsave else R.string.save)
    return clearAndSetSemantics {
        contentDescription = label
        role = Role.Button
        if (selected) this.selected = true
        status?.let { stateDescription = it }
        onClick { onClick(); true }
        if (onSave != null) customActions = listOf(CustomAccessibilityAction(saveLabel) { onSave(); true })
    }
}

/**
 * Друк корінця: велика година табличними цифрами, під нею день, а в зустрічі від людей — місця «3/8». [row] — розкладка
 * нижнього корінця вертикального квитка: година ліворуч, день і місця праворуч. TalkBack читає дату повністю.
 */
@Composable
fun StubTime(
    event: Event, modifier: Modifier = Modifier, compact: Boolean = false, row: Boolean = false, showsSeats: Boolean = true,
    /** Жанр словами над часом: колір корінця сам по собі нічого не каже. Малий корінець рядка його не друкує — там жанр поруч текстом. */
    showsGenre: Boolean = true
) {
    val words = dateWords()
    val (big, small) = remember(event, words, compact, row) { stubParts(event, words, compact = compact && !row, medium = row) }
    val room = event.gathering?.takeIf { showsSeats && !event.hasEnded(kotlin.time.Clock.System.now()) }
    val label = listOfNotNull(
        remember(event, words) { eventTime(event, words) },
        room?.let { stringResource(R.string.attendees, it.attendeeCount, it.capacity) }
    ).joinToString(", ")
    val numeral = (if (compact) PoruchType.numeralSmall else PoruchType.numeral).copy(color = Color.White)
    // Довгий день («СБ, 25 ЖОВТ.») і «ЗАРАЗ» стискаються, а не обрізаються: ширина корінця стала.
    val bigText = @Composable {
        BasicText(big, style = numeral, maxLines = 1, autoSize = TextAutoSize.StepBased(numeral.fontSize * 0.6f, numeral.fontSize))
    }
    val day = PoruchType.overline.copy(color = Color.White, letterSpacing = 0.6.sp)
    val smallText = @Composable {
        BasicText(small, style = day, maxLines = 1, autoSize = TextAutoSize.StepBased(day.fontSize * 0.7f, day.fontSize))
    }
    val seats = @Composable {
        room?.let {
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(PoruchIcons.social, null, Modifier.size(12.dp), tint = Color.White)
                Text("${it.attendeeCount}/${it.capacity}", style = day.copy(fontFeatureSettings = "tnum"))
            }
        }
    }
    val genreName = stringResource(categoryLabel(event.category)).takeIf { showsGenre && it.isNotBlank() }?.uppercase()
    val genre = @Composable {
        genreName?.let {
            val style = (if (row) PoruchType.overline else PoruchType.stamp).copy(color = Color.White, letterSpacing = 0.6.sp)
            BasicText(it, style = style, maxLines = 1, autoSize = TextAutoSize.StepBased(style.fontSize * 0.6f, style.fontSize))
        }
    }
    val semantics = modifier.clearAndSetSemantics { contentDescription = label }
    // Під цифрами години лишається порожнє місце нижніх виносних, і центрований друк прилипав жанром до перфорації
    // (4 зверху проти 12 знизу). Відступ зверху опускає його на 4 — видимі поля рівні.
    if (row) Row(
        semantics.fillMaxWidth().padding(horizontal = Spacing.md).padding(top = Spacing.sm),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) { genre(); bigText() }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            smallText(); seats()
        }
    } else Column(
        semantics.padding(horizontal = Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        if (genreName != null) Box(Modifier.padding(bottom = Spacing.xs)) { genre() }
        bigText(); smallText()
        Box(Modifier.padding(top = Spacing.xs)) { seats() }
    }
}

/**
 * Малий корінець у рядку списку: година й дата на плитці кольору жанру з вирізами з боків. Стовпець корінців вирівнює
 * рядки, як розклад. Минулу подію пробито: дірка в куті плитки, а не через цифри.
 */
@Composable
fun StubTile(event: Event, size: Dp = 60.dp) {
    // Росте з текстом до 1,5×, як корінець квитка: на великому шрифті «18:00» стискалось до «18…».
    val side = size * LocalDensity.current.fontScale.coerceIn(1f, 1.5f)
    Box(
        Modifier
            .size(side)
            .clip(TicketShape(side / 2, vertical = true, radius = Corner.sm, notch = 4.dp))
            .background(ticketStub(event)),
        contentAlignment = Alignment.Center
    ) {
        StubTime(event, compact = true, showsSeats = false, showsGenre = false)
        if (event.hasEnded(kotlin.time.Clock.System.now())) Box(
            Modifier.align(Alignment.TopEnd).padding(6.dp).size(9.dp).background(Poruch.colors.canvas, CircleShape)
        )
    }
}

/** Штамп стану на квитку: контур тоном і легкий нахил, як гумовий штамп на касі. На фото й корінці — білий по затемненню. */
@Composable
fun TicketStamp(
    text: String,
    tone: BadgeTone = BadgeTone.Neutral,
    icon: ImageVector? = null,
    onFill: Boolean = false,
    modifier: Modifier = Modifier
) {
    val colors = Poruch.colors
    val color = if (onFill) Color.White else when (tone) {
        BadgeTone.Success -> colors.success
        BadgeTone.Accent -> colors.accentText
        BadgeTone.Danger -> colors.danger
        BadgeTone.Brand, BadgeTone.Neutral -> colors.inkSecondary
    }
    val shape = RoundedCornerShape(5.dp)
    Row(
        modifier
            .rotate(-4f)
            .then(if (onFill) Modifier.background(Color.Black.copy(alpha = 0.42f), shape) else Modifier)
            .border(1.5.dp, color, shape)
            .padding(horizontal = 7.dp, vertical = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        icon?.let { Icon(it, null, Modifier.size(12.dp), tint = color) }
        Text(text.uppercase(), style = PoruchType.stamp, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Фото людини або перша літера імені, поки фото нема чи воно ще їде. */
@Composable
fun Avatar(name: String, url: String?, size: Dp, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(colors.surfaceMuted)
            // Обличчя людей не йдуть у Session Replay: маска CONSERVATIVE ховає лише текст.
            .ampBlock(),
        contentAlignment = Alignment.Center
    ) {
        // Літера не більша за 60 % кола на будь-якому fontScale: коло фіксоване, і великий шрифт обрізав її краєм.
        val base = if (size >= 56.dp) MaterialTheme.typography.headlineMedium else MaterialTheme.typography.labelMedium
        val cap = with(LocalDensity.current) { (size * 0.6f).toSp() }
        Text(
            name.trim().take(1).uppercase(),
            style = if (base.fontSize.value > cap.value) base.copy(fontSize = cap, lineHeight = cap) else base,
            color = colors.inkSecondary
        )
        url?.let {
            AsyncImage(
                model = it,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}

/** Аватари внапуск. */
@Composable
fun AvatarStack(
    attendees: List<Attendee>,
    modifier: Modifier = Modifier,
    total: Int = attendees.size,
    size: Dp = 32.dp
) {
    val colors = Poruch.colors
    val shown = attendees.take(5)
    val hidden = (total - shown.size).coerceAtLeast(0)
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        shown.forEachIndexed { index, attendee ->
            Avatar(
                attendee.name, attendee.avatarUrl, size,
                Modifier
                    .offset(x = -(index * 10).dp)
                    .border(2.dp, colors.surface, CircleShape)
            )
        }
        if (hidden > 0) Text(
            stringResource(R.string.attendees_more, hidden),
            style = MaterialTheme.typography.labelMedium,
            color = colors.inkSecondary,
            modifier = Modifier.offset(x = -(shown.size * 10 - 4).dp)
        )
    }
}

@Composable
fun MetaLine(icon: ImageVector, text: String, modifier: Modifier = Modifier, tone: Color? = null) {
    val colors = Poruch.colors
    Row(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, Modifier.size(15.dp), tint = tone ?: colors.inkTertiary)
        Text(
            text,
            style = MaterialTheme.typography.bodySmall,
            color = tone ?: colors.inkSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
