package app.poruch.android.ui

import android.annotation.SuppressLint
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.ui.draw.clipToBounds
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
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Density
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import androidx.annotation.RawRes
import com.airbnb.lottie.compose.LottieAnimation
import com.airbnb.lottie.compose.LottieCompositionSpec
import com.airbnb.lottie.compose.LottieConstants
import com.airbnb.lottie.compose.rememberLottieComposition
import app.poruch.domain.EventCategory
import app.poruch.domain.Attendee
import app.poruch.domain.Event
import app.poruch.domain.ArtistHit
import app.poruch.domain.ArtistKind
import app.poruch.domain.ArtistRole
import app.poruch.domain.DiscoveryRules
import com.amplitude.android.sessionreplay.compose.ampBlock
import app.poruch.domain.Place
import coil3.compose.AsyncImage

/**
 * Картка: біла на сірому без рамки й тіні; у темряві — трохи світліша за полотно, з тонкою лінією
 * по краю. Тінь лише в того, що плаває ([Elevation.raised] і вище): мʼяка, одна.
 */
@Composable
fun Modifier.cardSurface(shape: Shape = Radius.lg, elevation: Dp = Elevation.card): Modifier {
    val colors = Poruch.colors
    val lifted = if (elevation > 0.dp) this
        .shadow(
            elevation,
            shape,
            clip = false,
            ambientColor = colors.shadowAmbient,
            spotColor = colors.shadowSpot
        )
    else this
    val fill =
        if (colors.dark && elevation >= Elevation.raised) colors.surfaceRaised else colors.surface
    val edged = if (colors.dark) lifted
        .background(fill, shape)
        .border(1.dp, colors.hairline, shape) else lifted.background(fill, shape)
    return edged.clip(shape)
}

/**
 * Затемнення низу обкладинки під текстом — одне на велику картку головної й обкладинку деталей, щоб
 * одна й та сама афіша не мінялась тоном між екранами. Кольори на фото від теми не залежать.
 */
val PhotoScrim: Brush = Brush.verticalGradient(
    0.3f to Color.Transparent,
    0.7f to Color.Black.copy(alpha = 0.55f),
    1f to Color.Black.copy(alpha = 0.85f)
)

/** Чорнило й поверхня кнопки на скримі: завжди світла пігулка з темним гліфом, той самий hex, що й `ink` світлої теми. */
private val ScrimInk = Color(0xFF1D1D1F)
private val ScrimSurface = Color.White.copy(alpha = 0.92f)

/** Кругла кнопка 40 dp на обкладинці («назад», «поділитися»): фото довільне, тож на власному світлому скримі. */
@Composable
fun ScrimButton(icon: ImageVector, description: String, onClick: () -> Unit) {
    Box(
        Modifier
            .minimumInteractiveComponentSize()
            .size(40.dp)
            .background(ScrimSurface, CircleShape)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), CircleShape)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(icon, description, Modifier.size(18.dp), tint = ScrimInk) }
}

/**
 * Відгук на тап: поверхня трохи просідає під пальцем і повертається. Разом із тінню це робить
 * картку об'єктом, тому всі натискні поверхні беруть його замість голого `clickable`.
 * Reduced motion лишає ripple і прибирає просідання.
 */
@Composable
fun Modifier.pressable(
    enabled: Boolean = true,
    pressedScale: Float = 0.98f,
    role: Role? = Role.Button,
    /** Форма, якою обрізано відгук: у квитка ripple не залазить у вирізи й кути. */
    shape: Shape? = null,
    onClick: () -> Unit
): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val reducedMotion = Poruch.reducedMotion
    // Натиск не читається в композиції: хост (картка з її форматуванням) не перескладається на кожен
    // тап і відпускання. Масштаб іде з потоку взаємодій просто в шар малювання.
    val scale = remember { Animatable(1f) }
    LaunchedEffect(interaction, reducedMotion, pressedScale) {
        var presses = 0
        interaction.interactions.collect { event ->
            when (event) {
                is PressInteraction.Press -> presses++
                is PressInteraction.Release, is PressInteraction.Cancel -> presses--
                else -> return@collect
            }
            val target = if (presses > 0 && !reducedMotion) pressedScale else 1f
            launch {
                scale.animateTo(
                    target,
                    spring(
                        dampingRatio = Spring.DampingRatioMediumBouncy,
                        stiffness = Spring.StiffnessMediumLow
                    )
                )
            }
        }
    }
    return this
        .graphicsLayer {
            scaleX = scale.value; scaleY = scale.value
            if (shape != null) { this.shape = shape; clip = true }
        }
        .clickable(
            interactionSource = interaction,
            indication = LocalIndication.current,
            enabled = enabled,
            role = role,
            onClick = onClick
        )
}

/**
 * Низ прокручуваного вмісту вкладки: під плаваючим таббаром (кнопка 56 dp і його відступ) і системною
 * смугою навігації, якої заввишки вона б не була.
 */
fun Modifier.tabBarClearance(): Modifier = navigationBarsPadding().padding(bottom = TabBarClearance)

/** Те саме число для `contentPadding` лінивих списків: смугу навігації вони додають самі. */
val TabBarClearance = 56.dp + Spacing.md + Spacing.lg

/** Те саме, що [tabBarClearance], для `contentPadding` лінивого списку: вміст доїжджає під таббар, а не обрізається над ним. */
@Composable
fun tabBarClearancePadding(top: Dp = 0.dp): PaddingValues =
    PaddingValues(
        top = top,
        bottom = WindowInsets.navigationBars.asPaddingValues()
            .calculateBottomPadding() + 56.dp + Spacing.md + Spacing.lg
    )

/** Смуга полотна на 94 % під статус-баром: прокручений вміст кореня вкладки не лягає під годинник. Ставити останньою в `Box`. */
@Composable
fun StatusBarBand() =
    Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(Poruch.colors.canvas.copy(alpha = 0.94f)))

@Composable
fun HairLine(modifier: Modifier = Modifier) =
    Box(
        modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(Poruch.colors.hairline)
    )

/** Крапка категорії: найменший носій її кольору. */
@Composable
fun CategoryDot(category: EventCategory, size: Dp = 8.dp) =
    Box(
        Modifier
            .size(size)
            .background(categoryInk(category), CircleShape)
    )

// ---- Пошук і чипи

@Composable
fun PoruchSearchField(
    value: String, onValueChange: (String) -> Unit, placeholder: String,
    modifier: Modifier = Modifier, activeFilters: Int = 0, onFilters: (() -> Unit)? = null,
    /** Поле з'явилося на вимогу людини (іконка пошуку): курсор одразу в ньому. */
    autoFocus: Boolean = false
) {
    val colors = Poruch.colors
    val focus = remember { FocusRequester() }
    if (autoFocus) LaunchedEffect(Unit) { focus.requestFocus() }
    Row(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier
                .weight(1f)
                .height(50.dp)
                .cardSurface(Radius.pill, Elevation.card)
                .padding(horizontal = Spacing.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Icon(PoruchIcons.search, null, Modifier.size(18.dp), tint = colors.inkSecondary)
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                modifier = Modifier
                    .weight(1f)
                    .focusRequester(focus),
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.ink),
                cursorBrush = SolidColor(colors.ink),
                decorationBox = { inner ->
                    if (value.isEmpty()) Text(
                        placeholder,
                        style = MaterialTheme.typography.bodyLarge,
                        color = colors.inkTertiary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    inner()
                }
            )
            // Значок дрібний, зона дотику повна: у 18 dp не влучиш.
            if (value.isNotEmpty()) Box(
                Modifier
                    .minimumInteractiveComponentSize()
                    .clip(CircleShape)
                    .clickable { onValueChange("") },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    PoruchIcons.closeCircle, stringResource(R.string.clear_search),
                    Modifier.size(18.dp), tint = colors.inkTertiary
                )
            }
        }
        if (onFilters != null) Box {
            IconPill(PoruchIcons.filters, stringResource(R.string.filters), onClick = onFilters)
            if (activeFilters > 0) Text(
                activeFilters.toString(),
                style = MaterialTheme.typography.labelSmall,
                color = colors.onBrand,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .size(18.dp)
                    .background(colors.accentText, CircleShape)
                    .wrapContentSize(Alignment.Center)
            )
        }
    }
}

@Composable
fun IconPill(
    icon: ImageVector,
    contentDescription: String,
    selected: Boolean = false,
    size: Dp = 48.dp,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    Box(
        Modifier
            .minimumInteractiveComponentSize()
            .size(size)
            .background(if (selected) brandGradient() else SolidColor(colors.surface), CircleShape)
            .border(
                1.dp,
                if (selected || !colors.dark) Color.Transparent else colors.hairline,
                CircleShape
            )
            .clip(CircleShape)
            .pressable(onClick = onClick)
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            icon,
            null,
            Modifier.size(20.dp),
            tint = if (selected) colors.onBrand else colors.ink
        )
    }
}

/**
 * Потяг стрічки вниз. Вміст має вміти прокручуватись, інакше жест нікуди не дійде.
 * [underStatusBar] — вміст заходить під смугу статусу (хедер із градієнтом, обкладинка): тоді
 * індикатор відступає від неї, інакше коло висіло б на годиннику.
 */
@Composable
fun PullToRefresh(
    refreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    underStatusBar: Boolean = false,
    content: @Composable BoxScope.() -> Unit
) {
    val colors = Poruch.colors
    val state = rememberPullToRefreshState()
    PullToRefreshBox(
        isRefreshing = refreshing, onRefresh = onRefresh, modifier = modifier, state = state,
        indicator = {
            PullToRefreshDefaults.Indicator(
                state = state, isRefreshing = refreshing,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .then(if (underStatusBar) Modifier.statusBarsPadding() else Modifier),
                containerColor = colors.surface, color = colors.ink
            )
        },
        content = content
    )
}

/** Чип: біла пігулка на сірому; обраний заливається чорнилом. */
@Composable
fun PoruchChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    icon: ImageVector? = null,
    dot: EventCategory? = null,
    /** Гліф після підпису: шеврон каже, що чип відкриває вибір, а не перемикає фільтр. */
    trailingIcon: ImageVector? = null,
    /** Скільки непрочитаних чатів у цьому розрізі. */
    badge: Int = 0,
    /** Фільтр — один рядок; довге імʼя у складі переноситься, а не обрізається. */
    maxLines: Int = 1
) {
    val colors = Poruch.colors
    Row(
        Modifier
            .minimumInteractiveComponentSize()
            // Найменша висота, а не стала: з великим шрифтом чип росте, а не випускає підпис за пігулку.
            .heightIn(min = 38.dp)
            .background(
                if (selected) brandGradient() else SolidColor(
                    LocalFieldSurface.current ?: colors.surface
                ), Radius.pill
            )
            .border(
                1.dp,
                if (selected || !colors.dark) Color.Transparent else colors.hairline,
                Radius.pill
            )
            .clip(Radius.pill)
            .semantics { this.selected = selected }
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        when {
            dot != null -> Box(
                Modifier
                    .size(8.dp)
                    .background(if (selected) colors.onBrand else categoryInk(dot), CircleShape)
            )

            icon != null -> Icon(
                icon,
                null,
                Modifier.size(15.dp),
                tint = if (selected) colors.onBrand else colors.inkSecondary
            )
        }
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = if (selected) colors.onBrand else colors.ink,
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis
        )
        if (trailingIcon != null) Icon(
            trailingIcon,
            null,
            Modifier.size(16.dp),
            tint = if (selected) colors.onBrand else colors.inkSecondary
        )
        if (badge > 0) CountBadge(badge)
    }
}

/**
 * «Стежити» / «Ви стежите»: чип-перемикач біля закладу чи організатора. Гліф — дзвінок, бо пуш про нове
 * і є суттю підписки. Стан приходить зі спільного шару, тап лише просить його змінити.
 */
@Composable
fun FollowPill(
    following: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    onCard: Boolean = false
) {
    // На білій картці біла пігулка злилась би з нею: тоді підкладка приглушена, як у полях шторки.
    CompositionLocalProvider(LocalFieldSurface provides if (onCard) Poruch.colors.surfaceMuted else LocalFieldSurface.current) {
        Box(modifier) {
            PoruchChip(
                stringResource(if (following) R.string.following else R.string.follow),
                following,
                onToggle,
                if (following) PoruchIcons.bellActive else PoruchIcons.bell
            )
        }
    }
}

/** Сегментований перемикач-пігулка: тиха доріжка, біла пластина під обраним. Два-три рівноправні режими одного екрана. */
@Composable
fun SegmentedPill(
    items: List<String>,
    selected: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = Poruch.colors
    Row(
        modifier
            .fillMaxWidth()
            .background(colors.brandContainer, Radius.pill)
            .padding(4.dp)
    ) {
        items.forEachIndexed { index, title ->
            val active = index == selected
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = 40.dp)
                    .clip(Radius.pill)
                    .background(if (active) colors.surface else Color.Transparent, Radius.pill)
                    .selectable(active, role = Role.Tab) { if (!active) onSelect(index) }
                    .padding(horizontal = Spacing.sm, vertical = Spacing.xs),
                contentAlignment = Alignment.Center
            ) {
                // Великий шрифт стискає напис до 70 %, а не обрізає «Реєстрац…».
                val style = MaterialTheme.typography.labelLarge.copy(color = if (active) colors.ink else colors.inkSecondary)
                BasicText(title, style = style, maxLines = 1, autoSize = TextAutoSize.StepBased(style.fontSize * 0.7f, style.fontSize))
            }
        }
    }
}

/** Плитка категорії: скруглений квадрат у пастелі категорії. */
@Composable
fun CategoryTile(category: EventCategory, selected: Boolean, onClick: () -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier
            .width(76.dp)
            .clip(Radius.md)
            .pressable(onClick = onClick)
            // Обрана плитка — стан для TalkBack, а не лише рамка.
            .semantics { this.selected = selected }
            .padding(vertical = Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        Box(
            Modifier
                .size(60.dp)
                .background(categoryGradient(category), Radius.md)
                .border(2.dp, if (selected) colors.ink else Color.Transparent, Radius.md),
            contentAlignment = Alignment.Center
        ) { Icon(categoryIcon(category), null, Modifier.size(24.dp), tint = categoryInk(category)) }
        // «Конференції» в 76 dp стискаються, а не обрізаються.
        val label = MaterialTheme.typography.labelMedium.copy(color = if (selected) colors.ink else colors.inkSecondary)
        BasicText(
            stringResource(categoryLabel(category)), style = label, maxLines = 1,
            autoSize = TextAutoSize.StepBased(label.fontSize * 0.7f, label.fontSize)
        )
    }
}

// ---- Бейджі й кнопки

/** Кнопки — зібрані прямокутники з кутом квитка, а не пігулки: пігулками лишились чипи й бейджі. */
val ButtonShape = Radius.md

enum class BadgeTone { Brand, Success, Accent, Danger, Neutral }

@Composable
fun StatusBadge(text: String, tone: BadgeTone = BadgeTone.Neutral, icon: ImageVector? = null) {
    val colors = Poruch.colors
    val (background, foreground) = when (tone) {
        BadgeTone.Brand -> colors.brandContainer to colors.onBrandContainer
        BadgeTone.Success -> colors.successContainer to colors.onSuccessContainer
        BadgeTone.Accent -> colors.accentContainer to colors.onAccentContainer
        BadgeTone.Danger -> colors.dangerContainer to colors.danger
        BadgeTone.Neutral -> colors.surfaceMuted to colors.inkSecondary
    }
    Row(
        Modifier
            .background(background, Radius.pill)
            .padding(horizontal = Spacing.md, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        icon?.let { Icon(it, null, Modifier.size(13.dp), tint = foreground) }
        Text(text, style = MaterialTheme.typography.labelSmall, color = foreground)
    }
}

@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
    icon: ImageVector? = null,
    tone: Color? = null
) {
    val colors = Poruch.colors
    val background: Brush = when {
        // Блідіша за другорядну кнопку поруч: інакше «Назад» і неактивна «Далі» виглядали однаково.
        !enabled -> SolidColor(colors.brandContainer.copy(alpha = 0.55f))
        tone != null -> SolidColor(tone)
        else -> brandGradient()
    }
    val foreground = if (enabled) colors.onBrand else colors.inkTertiary
    Row(
        modifier
            // Великий шрифт переносить напис, а не обрізає: кнопка росте від 52 dp.
            .heightIn(min = 52.dp)
            .background(background, ButtonShape)
            .clip(ButtonShape)
            .pressable(enabled = enabled && !loading, onClick = onClick)
            .padding(horizontal = Spacing.xxl, vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm, Alignment.CenterHorizontally)
    ) {
        if (loading) CircularProgressIndicator(
            Modifier.size(18.dp),
            color = foreground,
            strokeWidth = 2.dp
        )
        else icon?.let { Icon(it, null, Modifier.size(18.dp), tint = foreground) }
        Text(text, style = MaterialTheme.typography.labelLarge, color = foreground, maxLines = 2, textAlign = TextAlign.Center)
    }
}

@Composable
fun SecondaryButton(
    text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, icon: ImageVector? = null, tone: Color? = null,
    /** Вужчі поля: поруч із підписом у панелі дії, де ширину ділить корінець. */
    compact: Boolean = false
) {
    val colors = Poruch.colors
    val foreground = if (enabled) tone ?: colors.ink else colors.inkTertiary
    Row(
        modifier
            .heightIn(min = 52.dp)
            .background(colors.brandContainer, ButtonShape)
            .clip(ButtonShape)
            .pressable(enabled = enabled, onClick = onClick)
            .padding(horizontal = if (compact) Spacing.lg else Spacing.xxl, vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm, Alignment.CenterHorizontally)
    ) {
        icon?.let { Icon(it, null, Modifier.size(18.dp), tint = foreground) }
        Text(text, style = MaterialTheme.typography.labelLarge, color = foreground, maxLines = 2, textAlign = TextAlign.Center)
    }
}

@Composable
fun GhostButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tone: Color? = null,
    enabled: Boolean = true
) {
    val colors = Poruch.colors
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = if (enabled) tone ?: colors.ink else colors.inkTertiary,
        // Ціль 48 dp при тексті на рядок: вирівнюємо по центру, а не добираємо полями.
        modifier = modifier
            .clip(Radius.pill)
            .clickable(enabled = enabled, onClick = onClick)
            .heightIn(min = 48.dp)
            .padding(horizontal = Spacing.lg, vertical = Spacing.xs)
            .wrapContentHeight(Alignment.CenterVertically)
    )
}

// ---- Структура

/** Заголовок секції: як написано в ресурсі, читабельного розміру. Капітель лишається там, де несе дані: дати, бейджі, підписи полів. */
@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            title,
            style = PoruchType.brandTitle2,
            color = colors.ink,
            // Заголовок і для TalkBack: перехід заголовками, як `.isHeader` на iOS.
            modifier = Modifier.weight(1f).semantics { heading() }
        )
        if (actionLabel != null && onAction != null) Text(
            actionLabel, style = MaterialTheme.typography.labelMedium, color = colors.ink,
            modifier = Modifier
                .clip(Radius.pill)
                .clickable(onClick = onAction)
                .padding(horizontal = Spacing.sm, vertical = Spacing.xs)
        )
    }
}

@Composable
fun PageHeader(
    title: String,
    modifier: Modifier = Modifier,
    back: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.page, vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        if (back != null) Box(
            Modifier
                .minimumInteractiveComponentSize()
                .size(40.dp)
                .cardSurface(CircleShape, Elevation.card)
                .pressable(onClick = back),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                PoruchIcons.arrowLeft,
                stringResource(R.string.back),
                Modifier.size(18.dp),
                tint = colors.ink
            )
        }
        Text(
            title,
            style = PoruchType.brandTitle1,
            color = colors.ink,
            modifier = Modifier.weight(1f)
        )
        trailing?.invoke()
    }
}

/** Фірмова Lottie-анімація в циклі; темний варіант лежить у raw-night. Малюнки — tools/generate_lottie.py. */
@Composable
fun BrandAnimation(@RawRes res: Int, modifier: Modifier = Modifier) {
    val composition by rememberLottieComposition(LottieCompositionSpec.RawRes(res))
    LottieAnimation(composition, modifier, iterations = LottieConstants.IterateForever)
}

/** Лоадер екрана чи секції: шпилька з іконки підстрибує. Кнопки й дрібні підвантаження лишаються з системним. */
@Composable
fun PoruchLoader(modifier: Modifier = Modifier) {
    if (Poruch.reducedMotion) CircularProgressIndicator(modifier, color = Poruch.colors.ink)
    else BrandAnimation(R.raw.loader, modifier.size(56.dp))
}

@Composable
fun EmptyState(
    icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier,
    actionLabel: String? = null, onAction: (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Column(
        modifier
            .fillMaxWidth()
            .padding(Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        BlankTicket(icon, Modifier.padding(bottom = Spacing.sm))
        // Довгі рядки переносяться: по центру, як і значок над ними.
        Text(
            title,
            style = PoruchType.brandTitle2,
            color = colors.ink,
            textAlign = TextAlign.Center
        )
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = colors.inkSecondary,
            textAlign = TextAlign.Center
        )
        if (actionLabel != null && onAction != null) PrimaryButton(
            actionLabel,
            onAction,
            Modifier.padding(top = Spacing.sm)
        )
    }
}

/** Без [subtitle] банер тонкий: гліф, один рядок і стрілка. */
@Composable
fun BannerCard(
    title: String,
    subtitle: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector = PoruchIcons.sparkle
) {
    val colors = Poruch.colors
    val slim = subtitle == null
    Row(
        modifier
            .fillMaxWidth()
            .pressable(onClick = onClick)
            .cardSurface()
            .padding(horizontal = Spacing.lg, vertical = if (slim) Spacing.md else Spacing.lg),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier
                .size(if (slim) 36.dp else 44.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, Modifier.size(20.dp), tint = colors.ink) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = colors.ink)
            subtitle?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary
                )
            }
        }
        Box(
            Modifier
                .size(if (slim) 28.dp else 32.dp)
                .background(colors.brand, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                PoruchIcons.arrowRight,
                null,
                Modifier.size(16.dp),
                tint = colors.onBrand
            )
        }
    }
}

@Composable
fun PoruchField(
    value: String, onValueChange: (String) -> Unit, label: String, modifier: Modifier = Modifier,
    singleLine: Boolean = true, error: String? = null, supporting: String? = null,
    /** Фокус для екрана, що відкривається заради цього поля. [modifier] лягає на колонку, а фокус потрібен введенню. */
    focusRequester: FocusRequester? = null
) {
    val colors = Poruch.colors
    val field = rememberBufferedText(value, onValueChange)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        OutlinedTextField(
            value = field.text,
            onValueChange = field.onChange,
            label = { Text(label) },
            singleLine = singleLine,
            minLines = if (singleLine) 1 else 4,
            isError = error != null,
            shape = Radius.sm,
            modifier = Modifier.fillMaxWidth()
                .let { if (focusRequester != null) it.focusRequester(focusRequester) else it },
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = colors.surface,
                unfocusedContainerColor = colors.surface,
                focusedBorderColor = colors.ink,
                unfocusedBorderColor = colors.hairline,
                focusedTextColor = colors.ink,
                unfocusedTextColor = colors.ink,
                focusedLabelColor = colors.ink,
                unfocusedLabelColor = colors.inkTertiary,
                cursorColor = colors.ink
            )
        )
        (error ?: supporting)?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = if (error != null) colors.danger else colors.inkTertiary,
                modifier = Modifier.padding(start = Spacing.lg)
            )
        }
    }
}

/** Поле з малим підписом над рамкою замість плаваючого плейсхолдера Material: форма читається як список названих речей. */
@Composable
fun LabelledField(
    label: String, value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
    placeholder: String = "", singleLine: Boolean = true, hint: String? = null,
    /** Багаторядкове поле відкривається цієї висоти, щоб читалось як місце для абзацу. */
    minLines: Int = if (singleLine) 1 else 4,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    /** Фокус для екрана, що відкривається заради цього поля. */
    focusRequester: FocusRequester? = null,
    /** Що не так із полем: під ним, кольором помилки. */
    error: String? = null,
    trailing: @Composable (() -> Unit)? = null
) {
    val colors = Poruch.colors
    val field = rememberBufferedText(value, onValueChange)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        // Підпис — назва самого поля для TalkBack, а не окрема зупинка перед ним: інакше заповнене поле
        // озвучувало лише значення, без того, що це за поле.
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = colors.inkTertiary,
            modifier = Modifier.clearAndSetSemantics { }
        )
        Row(
            // Висота вміщує 48 dp ціль кінцевого контролу, не переростаючи сусіднє поле.
            Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 56.dp)
                // Біле поле на сірому полотні: `surfaceMuted` відрізнявся від полотна на два тони і поле зникало.
                // У шторці навпаки — див. [LocalFieldSurface].
                .background(LocalFieldSurface.current ?: colors.surface, Radius.sm)
                .padding(horizontal = Spacing.lg, vertical = if (singleLine) 0.dp else Spacing.md),
            verticalAlignment = if (singleLine) Alignment.CenterVertically else Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            BasicTextField(
                value = field.text,
                onValueChange = field.onChange,
                singleLine = singleLine,
                minLines = minLines,
                modifier = Modifier.weight(1f)
                    // Помилка — стан поля: TalkBack каже її разом із назвою, а не як окремий текст нижче.
                    .semantics { contentDescription = label; if (error != null) error(error) }
                    .let { if (focusRequester != null) it.focusRequester(focusRequester) else it },
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.ink),
                cursorBrush = SolidColor(colors.ink),
                keyboardOptions = keyboardOptions,
                visualTransformation = visualTransformation,
                decorationBox = { inner ->
                    if (field.text.isEmpty() && placeholder.isNotEmpty()) {
                        Text(
                            placeholder,
                            style = MaterialTheme.typography.bodyLarge,
                            color = colors.inkTertiary
                        )
                    }
                    inner()
                }
            )
            trailing?.invoke()
        }
        hint?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkTertiary
            )
        }
        error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.danger) }
    }
}

/**
 * Перемикач видимості пароля для [LabelledField]. Іконка — стан, як у системному полі Android:
 * відкрите око, коли пароль видно, перекреслене — коли приховано. Підпис для TalkBack — дія.
 */
@Composable
fun PasswordRevealIcon(revealed: Boolean, onToggle: () -> Unit) {
    Icon(
        if (revealed) PoruchIcons.eye else PoruchIcons.eyeOff,
        stringResource(if (revealed) R.string.hide_password else R.string.show_password),
        Modifier
            .minimumInteractiveComponentSize()
            .size(20.dp)
            .clip(CircleShape)
            .clickable(onClick = onToggle),
        tint = Poruch.colors.inkSecondary
    )
}

/** Поле з вибором замість введення: дата, місце. Виглядає як [LabelledField], щоб форма лишалась одним списком. */
@Composable
fun PickerField(
    label: String, value: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    placeholder: String = "", hint: String? = null, icon: ImageVector? = null
) {
    val colors = Poruch.colors
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = colors.inkTertiary
        )
        Row(
            Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 56.dp)
                // Біле поле на сірому полотні: `surfaceMuted` відрізнявся від полотна на два тони і поле зникало.
                // У шторці навпаки — див. [LocalFieldSurface].
                .background(LocalFieldSurface.current ?: colors.surface, Radius.sm)
                .clip(Radius.sm)
                .pressable(onClick = onClick)
                .padding(horizontal = Spacing.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            Text(
                value.ifEmpty { placeholder },
                style = MaterialTheme.typography.bodyLarge,
                color = if (value.isEmpty()) colors.inkTertiary else colors.ink,
                modifier = Modifier.weight(1f)
            )
            icon?.let { Icon(it, null, Modifier.size(18.dp), tint = colors.inkTertiary) }
        }
        hint?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkTertiary
            )
        }
    }
}

// ---- Поверхні подій

/** Обкладинка без фото — градієнт категорії з її гліфом. Фото отримує затемнення знизу під білі бейджі. */
@Composable
fun EventImage(event: Event, modifier: Modifier, glyphSize: Dp = 26.dp) {
    Box(
        modifier.background(categoryGradient(event.category)),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            categoryIcon(event.category),
            null,
            Modifier.size(glyphSize),
            tint = categoryInk(event.category)
        )
        event.imageUrl?.let {
            AsyncImage(
                model = it,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
            Box(
                Modifier
                    .matchParentSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(
                                Color.Black.copy(alpha = 0.28f),
                                Color.Transparent,
                                Color.Black.copy(alpha = 0.12f)
                            )
                        )
                    )
            )
        }
    }
}

/** Стан події словами: скасовано, знято, а для кімнати — «ви йдете», запит, черга, місця. Без підпису джерела афіші. */
@Composable
fun eventState(event: Event, waitlisted: Boolean = false): Pair<String, BadgeTone>? {
    if (event.isCancelled) return stringResource(R.string.cancelled) to BadgeTone.Danger
    event.listing?.let { listing ->
        return if (listing.isWithdrawn) stringResource(R.string.listing_withdrawn) to BadgeTone.Neutral else null
    }
    val room = event.gathering ?: return null
    // Місця й «ви йдете» після кінця нічого не кажуть: рядок покаже категорію.
    if (event.hasEnded(kotlin.time.Clock.System.now())) return null
    return when {
        room.joined -> stringResource(R.string.going) to BadgeTone.Success
        room.awaitingApproval -> stringResource(R.string.request_pending) to BadgeTone.Accent
        waitlisted -> stringResource(R.string.in_queue) to BadgeTone.Accent
        room.isFull -> stringResource(R.string.full) to BadgeTone.Neutral
        // Коротко, як на iOS: штамп на вузькому квитку не мусить налазити на «Зберегти».
        room.isScarce -> stringResource(R.string.seats_left_short, room.seatsLeft) to BadgeTone.Accent
        else -> null
    }
}

/** Рядок стану над карткою. Афіша завжди підписана джерелом (docs/event-ingestion.md §8); місця й черга лише в кімнати. */
@Composable
private fun eventStatus(event: Event, waitlisted: Boolean = false): Pair<String, BadgeTone>? =
    eventState(event, waitlisted)
        ?: event.listing?.let {
            stringResource(
                R.string.listing_badge,
                it.sourceName
            ) to BadgeTone.Neutral
        }

/** Рядок під назвою: учасники для кімнати, ціна для афіші. */
@Composable
private fun EventMeta(event: Event, short: Boolean = false) {
    val room = event.gathering
    val listing = event.listing
    when {
        room != null -> MetaLine(
            PoruchIcons.social,
            stringResource(
                if (short) R.string.attendees_short else R.string.attendees,
                room.attendeeCount,
                room.capacity
            )
        )

        listing != null -> MetaLine(PoruchIcons.ticket, listingPrice(listing))
    }
}

/**
 * Крапка категорії плюс її назва кольором категорії. [placeFirst] — місце першим, а категорія лише крапкою:
 * на постері назва закладу важливіша за жанр, який і так каже афіша; жанр лишається для TalkBack.
 */
@Composable
fun EventDescriptor(
    event: Event,
    modifier: Modifier = Modifier,
    withCity: Boolean = false,
    placeFirst: Boolean = false
) {
    val colors = Poruch.colors
    // Роздільник лише коли є текст праворуч. Назва закладу, коли є, замість адреси.
    // Місто першим: у видачі з різних міст воно важливіше за адресу й не зникає під трьома крапками.
    val place = if (withCity) placeWithCity(event) else event.placeLabel
    val category = stringResource(categoryLabel(event.category))
    Row(
        if (placeFirst) modifier.semantics(mergeDescendants = true) {
            contentDescription =
                listOf(category, place).filter { it.isNotBlank() }.joinToString(", ")
        }
        else modifier,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CategoryDot(event.category)
        if (placeFirst) Text(
            place.ifBlank { category },
            style = MaterialTheme.typography.bodySmall,
            color = colors.inkSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        ) else {
            Text(
                category,
                style = PoruchType.descriptor,
                color = categoryInk(event.category),
                maxLines = 1
            )
            place.takeIf { it.isNotBlank() }?.let { place ->
                Text(
                    "· $place",
                    style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary,
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
fun SaveButton(saved: Boolean, onSave: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Box(
        modifier
            .minimumInteractiveComponentSize()
            .size(34.dp)
            .shadow(
                Elevation.raised,
                CircleShape,
                clip = false,
                ambientColor = Color(0x1F000000),
                spotColor = Color(0x33000000)
            )
            .background(colors.surface, CircleShape)
            .border(1.dp, colors.hairline, CircleShape)
            .clip(CircleShape)
            .pressable(onClick = onSave),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            if (saved) PoruchIcons.bookmarkFilled else PoruchIcons.bookmark,
            stringResource(if (saved) R.string.unsave else R.string.save), Modifier.size(17.dp),
            tint = if (saved) colors.ink else colors.inkSecondary
        )
    }
}

/** Квиток стрічки: фото врівень із краєм, назва й опис; на корінці — збереження й час. Минулий квиток пробито. */
@Composable
fun EventCard(
    event: Event,
    modifier: Modifier = Modifier,
    saved: Boolean = false,
    waitlisted: Boolean = false,
    /** Назвати місто в підписі: видача з різних міст. */
    withCity: Boolean = false,
    onSave: (() -> Unit)? = null,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val badge = eventStatus(event, waitlisted)
    Ticket(
        ticketStub(event),
        stub = {
            Column(Modifier.fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                if (onSave != null) SaveButton(saved, onSave, Modifier.padding(top = Spacing.sm))
                Spacer(Modifier.weight(1f).heightIn(min = Spacing.md))
                StubTime(event)
                Spacer(Modifier.weight(1f).heightIn(min = Spacing.md))
            }
        },
        modifier = modifier.fillMaxWidth()
            .ticketSemantics(ticketA11yLabel(event, badge?.first), onClick, saved, onSave),
        punched = event.hasEnded(kotlin.time.Clock.System.now()),
        onClick = onClick
    ) {
        Column {
            // Фото врівень із краєм квитка; без фото обкладинки нема — квиток і так кольоровий.
            if (event.imageUrl != null) Box(Modifier.fillMaxWidth().height(180.dp)) {
                EventImage(event, Modifier.fillMaxSize())
                badge?.let { (text, tone) -> TicketStamp(text, tone, onFill = true, modifier = Modifier.padding(Spacing.md)) }
            }
            Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                if (event.imageUrl == null) badge?.let { (text, tone) -> TicketStamp(text, tone) }
                Text(
                    event.displayTitle, style = PoruchType.brandTitle3, color = colors.ink,
                    maxLines = 2, overflow = TextOverflow.Ellipsis
                )
                EventDescriptor(event, withCity = withCity)
                artistsLine(event)?.let { MetaLine(PoruchIcons.person, it) }
                // Місця зустрічі — на корінці.
                if (event.gathering == null) EventMeta(event)
            }
        }
    }
}

/** Компактний рядок списку: малий корінець з часом, назва, опис. */
@Composable
fun EventRow(
    event: Event,
    modifier: Modifier = Modifier,
    unread: Int = 0,
    waitlisted: Boolean = false,
    /** Рядок замість статусу й категорії: «Ваша оцінка ★ 5». */
    note: String? = null,
    /** Праворуч власна дія рядка замість шеврона. */
    trailing: (@Composable () -> Unit)? = null,
    /** Статус замість звичного: «2 запити на участь» у своїй події. */
    status: Pair<String, BadgeTone>? = null,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val badge = status ?: eventState(event, waitlisted)
    val source = event.listing?.takeIf { !it.isWithdrawn }?.let { stringResource(R.string.listing_badge, it.sourceName) }
    val unreadLabel =
        if (unread > 0) stringResource(R.string.unread_messages_a11y, unread) else null
    Row(
        modifier
            .fillMaxWidth()
            .ticketSemantics(ticketA11yLabel(event, note ?: listOfNotNull(badge?.first, source).joinToString(", ")), onClick, status = unreadLabel)
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StubTile(event)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(
                event.displayTitle, style = PoruchType.brandTitle3, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            when {
                note != null -> Text(
                    note,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary,
                    maxLines = 1
                )

                // Жанр і місце — завжди; штамп — лише коли з квитком щось сталось. Джерело афіші — тихим підписом,
                // а не штампом: штамп «Афіша · Concert.ua» витісняв жанр і місце з усіх рядків афіші.
                else -> {
                    badge?.let { TicketStamp(it.first, it.second, modifier = Modifier.padding(top = 2.dp)) }
                    EventDescriptor(event)
                    source?.let {
                        Text(it, style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
        // Непрочитане в чаті — той самий бейдж, що на вкладці: видно, куди він веде.
        if (unread > 0) CountBadge(unread)
        if (trailing != null) trailing()
        else Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
    }
}

/** Місто перед закладом чи адресою, якщо адреса вже з нього не починається. */
private fun placeWithCity(event: Event): String {
    val place = event.placeLabel
    return if (event.city.isBlank() || place == event.city || place.startsWith(event.city + ",")) place
    else listOf(event.city, place).filter { it.isNotBlank() }.joinToString(", ")
}

/** Відступ лінії між рядками видачі пошуку: від тексту, а не від краю. */
val ResultRowInset = Spacing.lg + 56.dp + Spacing.md

/**
 * Рядок видачі пошуку: малий корінець з часом, назва й «категорія · місце · ціна»; справа — штамп
 * стану кімнати. Кілька рядків збирає [GroupedRows]. Афіша підписана джерелом окремим рядком:
 * атрибуція на картці обов'язкова (docs/event-ingestion.md §8).
 */
@Composable
fun EventResultRow(
    event: Event,
    modifier: Modifier = Modifier,
    waitlisted: Boolean = false,
    /** Назвати місто в підписі: видача з різних міст. */
    withCity: Boolean = false,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val badge = resultBadge(event, waitlisted)
    val price = event.listing?.takeIf { it.isFree == true || it.priceMin != null }
        ?.let { listingPrice(it).replaceFirstChar { c -> c.lowercase() } }
    val subtitle = listOfNotNull(
        stringResource(categoryLabel(event.category)),
        (if (withCity) placeWithCity(event) else event.placeLabel).takeIf { it.isNotBlank() },
        price
    ).joinToString(" · ")
    Row(
        modifier
            .fillMaxWidth()
            .ticketSemantics(ticketA11yLabel(event, badge?.first), onClick)
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StubTile(event, 56.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                event.displayTitle, style = PoruchType.brandTitle3, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            Text(
                subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            artistsLine(event)?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            event.listing?.let { listing ->
                Text(
                    stringResource(R.string.listing_badge, listing.sourceName),
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.inkTertiary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        badge?.let { (text, tone) -> TicketStamp(text, tone) }
    }
}

/** Бейдж рядка видачі: лише те, що міняє рішення, — скасування, зняття, стан кімнати. Джерело афіші — окремим рядком. */
@Composable
private fun resultBadge(event: Event, waitlisted: Boolean): Pair<String, BadgeTone>? {
    if (event.isCancelled) return stringResource(R.string.cancelled) to BadgeTone.Danger
    if (event.listing?.isWithdrawn == true) return stringResource(R.string.listing_withdrawn) to BadgeTone.Neutral
    val room = event.gathering ?: return null
    if (event.hasEnded(kotlin.time.Clock.System.now())) return null
    return when {
        room.joined -> stringResource(R.string.going) to BadgeTone.Success
        waitlisted -> stringResource(R.string.in_queue) to BadgeTone.Accent
        room.isFull -> stringResource(R.string.full) to BadgeTone.Neutral
        room.isScarce -> pluralStringResource(
            R.plurals.seats_short,
            room.seatsLeft,
            room.seatsLeft
        ) to BadgeTone.Accent

        else -> null
    }
}

/**
 * Склад для картки одним рядком: до трьох імен, ведучий окремо («· ведучий Дмитро»), решта «та ще N». Null — артистів нема.
 * Імена в картці не тапаються: вся картка вже кнопка, тапабельні чипи лише в деталях ([Lineup]).
 */
@Composable
fun artistsLine(event: Event): String? {
    val shown = event.cardArtists
    if (shown.isEmpty()) return null
    val performers = shown.filter { it.role != ArtistRole.HOST }.joinToString(", ") { it.name }
    val hosts = shown.filter { it.role == ArtistRole.HOST }.joinToString(", ") { it.name }
    val host = if (hosts.isEmpty()) null else stringResource(R.string.artist_line_host, hosts)
    val line = listOfNotNull(performers.takeIf { it.isNotEmpty() }, host).joinToString(" · ")
    return if (event.moreArtists > 0) stringResource(
        R.string.artist_line_more,
        line,
        event.moreArtists
    ) else line
}

/** Вид словом, лише коли він відомий і не людина: `person` без підпису. */
@Composable
fun artistKindLabel(kind: ArtistKind?): String? = when (kind) {
    ArtistKind.GROUP -> stringResource(R.string.artist_kind_group)
    ArtistKind.SHOW -> stringResource(R.string.artist_kind_show)
    ArtistKind.COMPANY -> stringResource(R.string.artist_kind_company)
    ArtistKind.PERSON, null -> null
}

/** Рядок артиста в пошуку: піктограма людини, ім'я й скільки подій попереду. */
@Composable
fun ArtistRow(artist: ArtistHit, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = Poruch.colors
    val subtitle = listOfNotNull(
        artistKindLabel(artist.kind),
        pluralStringResource(R.plurals.place_upcoming, artist.upcoming, artist.upcoming)
    )
        .joinToString(" · ")
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {}
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(PoruchIcons.person, null, Modifier.size(20.dp), tint = colors.ink)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                artist.name,
                style = PoruchType.brandTitle3,
                color = colors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** Рядок закладу в пошуку: піктограма місця, назва, адреса й скільки подій попереду. */
@Composable
fun PlaceRow(
    place: Place,
    modifier: Modifier = Modifier,
    withCity: Boolean = false,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val address = if (withCity && place.city.isNotBlank() && !place.address.contains(place.city)) {
        listOf(place.city, place.address).filter { it.isNotBlank() }.joinToString(", ")
    } else place.address
    val subtitle = listOf(
        address,
        pluralStringResource(R.plurals.place_upcoming, place.upcoming, place.upcoming)
    )
        .filter { it.isNotBlank() }.joinToString(" · ")
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {}
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(PoruchIcons.pin, null, Modifier.size(20.dp), tint = colors.ink)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                place.name, style = PoruchType.brandTitle3, color = colors.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(
                subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** Число на акцентній пігулці: бейдж вкладки, рядка й чипа однаковий. */
@Composable
fun CountBadge(count: Int, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Text(
        count.coerceAtMost(99).toString(),
        style = MaterialTheme.typography.labelSmall,
        color = colors.onBrand,
        modifier = modifier
            .clearAndSetSemantics { }
            // Тло — `accentText`: білий дрібний текст на самому `accent` давав лише 3,75:1.
            .background(colors.accentText, Radius.pill)
            .padding(horizontal = 6.dp, vertical = 1.dp)
    )
}

/** Квиток каруселі над мапою: досить широкий для назви, досить низький, щоб мапу було видно. */
@Composable
fun EventMapCard(
    event: Event, modifier: Modifier = Modifier, focused: Boolean = false,
    saved: Boolean = false, onSave: (() -> Unit)? = null, onClick: () -> Unit
) {
    val colors = Poruch.colors
    val state = eventState(event)
    Ticket(
        ticketStub(event),
        stub = {
            // «Зберегти» на корінці, як на великому квитку: в основній частині назва важливіша.
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                if (onSave != null) SaveButton(saved, onSave)
                // Жанр словами — в основній частині: на корінці над «Зберегти» й часом йому не лишалось місця.
                StubTime(event, compact = onSave != null, showsGenre = false)
            }
        },
        modifier = modifier
            .ticketSemantics(ticketA11yLabel(event, state?.first), onClick, saved, onSave, selected = focused),
        stubLength = 80.dp, radius = Corner.lg, surface = colors.surfaceRaised, elevation = Elevation.raised,
        outline = if (focused) colors.ink else null, dashed = false, onClick = onClick
    ) {
        Row(
            Modifier.height(mapCardHeight()).padding(start = Spacing.md, end = Spacing.sm),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
            verticalAlignment = Alignment.CenterVertically
        ) {
            EventImage(event, Modifier.size(76.dp).clip(Radius.sm))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                // Назва поступається штампу: слот картки фіксований, і довга назва інакше виштовхує його за край.
                Text(
                    event.displayTitle,
                    style = PoruchType.brandTitle3,
                    color = colors.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                // Склад замість місця: на слоті картки місця для обох нема, а хто виступає каже більше.
                val artists = artistsLine(event)
                if (state != null) TicketStamp(state.first, state.second)
                else if (artists != null) MetaLine(PoruchIcons.person, artists)
                else EventDescriptor(event)
            }
        }
    }
}

/** Порожній квиток над порожнім станом: ненадруковані рядки пунктиром і гліф на сірому корінці. Лише прикраса. */
@Composable
private fun BlankTicket(icon: ImageVector, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Ticket(
        colors.surfaceMuted,
        stub = { Icon(icon, null, Modifier.size(22.dp), tint = colors.inkSecondary) },
        modifier = modifier.width(184.dp).decorative(),
        stubLength = 56.dp, radius = Corner.sm, outline = colors.inkTertiary.copy(alpha = 0.6f)
    ) {
        Column(
            Modifier.heightIn(min = 72.dp).padding(horizontal = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically)
        ) {
            Box(Modifier.size(72.dp, 6.dp).background(colors.hairline, Radius.pill))
            Box(Modifier.size(44.dp, 6.dp).background(colors.hairline, Radius.pill))
        }
    }
}

// ---- Квиток («Корінець»)

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
            drawLine(
                colors.canvas,
                if (vertical) Offset(inset, at) else Offset(at, inset),
                if (vertical) Offset(size.width - inset, at) else Offset(at, size.height - inset),
                strokeWidth = 2.5.dp.toPx(), cap = StrokeCap.Round,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(0.1.dp.toPx(), 6.dp.toPx()))
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

// ---- Композиційні картки головної

/**
 * Порожній квиток «Організувати подію»: свою зустріч друкуєш сам. Корінець чорнильний — це головна дія екрана; контур
 * пунктиром. Головна одиниця застосунку — зустріч від людини, тож дорога до неї видна одразу. Гостя тап веде до входу.
 */
@Composable
fun CreateEventCard(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    /** Олівець — «друкуєш сам»; інший гліф — та сама порожня форма для іншої першої дії («Знайти подію поруч»). */
    icon: ImageVector = PoruchIcons.edit
) {
    val colors = Poruch.colors
    Ticket(
        colors.brand,
        // Олівець, а не «+»: плюс уже є на кнопці створення біля таббара, а тут квиток заповнюють.
        stub = { Icon(icon, null, Modifier.size(22.dp), tint = colors.onBrand) },
        modifier = modifier.fillMaxWidth(),
        stubLength = 64.dp, outline = colors.inkTertiary.copy(alpha = 0.7f), onClick = onClick
    ) {
        Column(
            Modifier.heightIn(min = 72.dp).padding(horizontal = Spacing.lg, vertical = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)
        ) {
            Text(title, style = PoruchType.brandTitle3, color = colors.ink)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
    }
}

/**
 * Великий квиток-афіша: обкладинка зверху, назва й опис на поверхні, час на корінці; без фото — друкована сторона з назвою
 * великим кеглем. На головній їх кілька, гортаються.
 */
@Composable
fun EventHeroCard(
    event: Event, modifier: Modifier = Modifier, eyebrow: String? = null, height: Dp = 360.dp,
    saved: Boolean = false, onSave: (() -> Unit)? = null, onClick: () -> Unit
) {
    val colors = Poruch.colors
    // Штамп — лише стан квитка. Чому квиток тут («Для вас», «Від людей») — тихим рядком під описом.
    val stamp: Triple<String, BadgeTone, ImageVector?>? = eventState(event)?.let { Triple(it.first, it.second, null) }
    val reason: Pair<String, ImageVector>? = eyebrow?.let { it to PoruchIcons.sparkle }
        ?: if (event.gathering != null) stringResource(R.string.from_people) to PoruchIcons.social else null
    Ticket(
        ticketStub(event),
        stub = {
            Column(Modifier.fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                if (onSave != null) SaveButton(saved, onSave, Modifier.padding(top = Spacing.md))
                Spacer(Modifier.weight(1f))
                StubTime(event, Modifier.padding(bottom = Spacing.xl))
            }
        },
        modifier = modifier.fillMaxWidth()
            .ticketSemantics(ticketA11yLabel(event, listOfNotNull(stamp?.first, reason?.first).joinToString(", ")), onClick, saved, onSave),
        radius = Corner.lg, onClick = onClick
    ) {
        val printed = event.imageUrl == null
        // Висота — найменша, а не стала: з великим шрифтом назва, місце й підпис джерела не обрізаються.
        Column(Modifier.heightIn(min = height)) {
            // Без фото обкладинки нема: квиток друкований — штамп і назва великим кеглем на самій поверхні.
            if (!printed) Box(Modifier.fillMaxWidth().height(height * 0.54f).clipToBounds()) {
                EventArt(event, Modifier.fillMaxSize(), glyph = 160.dp)
                stamp?.let { (text, tone, icon) -> TicketStamp(text, tone, icon, onFill = true, modifier = Modifier.padding(Spacing.md)) }
            } else stamp?.let { (text, tone, icon) ->
                TicketStamp(text, tone, icon, modifier = Modifier.padding(start = Spacing.lg, end = Spacing.lg, top = Spacing.lg))
            }
            Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(
                    event.displayTitle, style = if (printed) PoruchType.brandDisplay else PoruchType.brandTitle1, color = colors.ink,
                    maxLines = if (printed) 5 else 2, overflow = TextOverflow.Ellipsis
                )
                HostLine(event)
                EventDescriptor(event)
                reason?.let { (text, icon) -> ReasonLine(text, icon) }
                artistsLine(event)?.let { MetaLine(PoruchIcons.person, it) }
                event.listing?.let {
                    Text(
                        stringResource(R.string.listing_badge, it.sourceName), style = MaterialTheme.typography.labelSmall,
                        color = colors.inkTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

/**
 * Афіша на всю обкладинку; без фото — насичений градієнт категорії з її великим прозорим гліфом.
 * Одна на hero й постер, щоб подія без фото не блідла серед подій із ним. [glyph] — розмір прозорого гліфа,
 * [glyphDrop] — наскільки його опустити (на деталях верх зайнятий смугою статусу й кнопками).
 */
@Composable
fun EventArt(
    event: Event,
    modifier: Modifier = Modifier,
    glyph: Dp = 220.dp,
    glyphDrop: Dp = 0.dp
) {
    if (event.imageUrl == null) Box(modifier.background(categoryHeroGradient(event.category))) {
        Icon(
            categoryIcon(event.category), null,
            Modifier
                .align(Alignment.TopEnd)
                .offset(x = glyph * 0.25f, y = glyphDrop - glyph * 0.04f)
                .size(glyph),
            tint = Color.White.copy(alpha = 0.18f)
        )
    } else EventImage(event, modifier, glyphSize = 72.dp)
}

/** Рядок групового списку: гліф, назва, підпис, справа значення й шеврон. Кілька рядків збирає [GroupedRows]. */
@Composable
fun LinkRow(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
    value: String? = null,
    /** Що нового за рядком («3 нові»): помітніше за [value]. */
    badge: String? = null
) {
    val colors = Poruch.colors
    Row(
        Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { role = Role.Button }
            .clickable(onClick = onClick)
            .padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, null, Modifier.size(20.dp), tint = colors.ink)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = colors.ink)
            if (subtitle != null) Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkSecondary
            )
            // Під підписом, як у списку підписок: праворуч поруч із числом він стискав підпис у три рядки.
            if (badge != null) Box(Modifier.padding(top = Spacing.xs)) { StatusBadge(badge, BadgeTone.Accent) }
        }
        if (value != null) Text(
            value,
            style = MaterialTheme.typography.titleLarge,
            color = colors.ink
        )
        Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
    }
}

/** Підпис над [GroupedRows] капітеллю: «Події · 7», «Місця». Праворуч — необов'язкова дія. */
@Composable
fun GroupLabel(
    text: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            text.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = colors.inkTertiary,
            modifier = Modifier
                .weight(1f)
                .semantics { heading() }
        )
        if (actionLabel != null && onAction != null) Text(
            actionLabel, style = MaterialTheme.typography.labelMedium, color = colors.ink,
            modifier = Modifier
                .clip(Radius.pill)
                .clickable(onClick = onAction)
                .padding(horizontal = Spacing.sm, vertical = Spacing.xs)
        )
    }
}

/** Секція «Місця» у видачі пошуку: заклади з тим самим словом. Тап — мапа на закладі. */
@Composable
fun PlacesGroup(
    places: List<Place>,
    withCity: Boolean,
    modifier: Modifier = Modifier,
    onOpen: (Place) -> Unit
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        GroupLabel(stringResource(R.string.search_places_group))
        GroupedRows {
            places.forEachIndexed { position, place ->
                if (position > 0) HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                PlaceRow(place, withCity = withCity) { onOpen(place) }
            }
        }
    }
}

/** Секція «Артисти» у видачі пошуку під «Місцями». Тап — екран артиста. */
@Composable
fun ArtistsGroup(
    artists: List<ArtistHit>,
    modifier: Modifier = Modifier,
    onOpen: (ArtistHit) -> Unit
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        GroupLabel(stringResource(R.string.search_artists_group))
        GroupedRows {
            artists.take(DiscoveryRules.ARTISTS_LIMIT).forEachIndexed { position, artist ->
                if (position > 0) HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                ArtistRow(artist) { onOpen(artist) }
            }
        }
    }
}

/** Біла картка з рядками; лінія між ними йде від тексту, а не від краю. */
@Composable
fun GroupedRows(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) =
    Column(
        modifier
            .fillMaxWidth()
            .cardSurface(), content = content
    )

/** Кругла дія з підписом під нею: ряд таких — панель дій на деталях. */
@Composable
fun RoundAction(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    val colors = Poruch.colors
    val ink = if (enabled) colors.ink else colors.inkTertiary
    Column(
        modifier
            .clip(Radius.md)
            .pressable(enabled = enabled, onClick = onClick)
            .padding(Spacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        Box(
            Modifier
                .size(56.dp)
                .cardSurface(CircleShape), contentAlignment = Alignment.Center
        ) {
            Icon(icon, null, Modifier.size(22.dp), tint = ink)
        }
        Text(title, style = MaterialTheme.typography.labelMedium, color = ink, maxLines = 1)
    }
}

// ---- Навігація

data class TabItem(
    val key: String, val label: String, val icon: ImageVector,
    /** Скільки справ чекає: 0 — без бейджа. */
    val badge: Int = 0,
    /** Є нове, але не справа, яку треба рахувати: крапка замість числа. */
    val dot: Boolean = false,
    /** Підказка першого знайомства, що вказує на цей пункт. */
    val tip: CoachTip? = null
)

/** Плаваючий таббар-капсула; під активним пунктом тонова пігулка. */
@Composable
fun PoruchTabBar(
    items: List<TabItem>,
    selected: String,
    modifier: Modifier = Modifier,
    onSelect: (String) -> Unit,
    trailing: @Composable (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Row(
        modifier.padding(horizontal = Spacing.lg),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Великий системний шрифт: підписи ростуть разом із ним, поки найдовший влазить у пункт, далі стоять одним
        // кеглем. Коли не влазить навіть звичайний кегль — лише гліфи, назву скрінрідер бере з contentDescription.
        BoxWithConstraints(Modifier.weight(1f)) {
            val base = MaterialTheme.typography.labelSmall
            val measurer = rememberTextMeasurer()
            val density = LocalDensity.current
            val room = with(density) { ((maxWidth - Spacing.xs * 2) / items.size - Spacing.xs * 2).toPx() }
            val labels = items.map { it.label }
            // Ширина тексту не пропорційна кеглю (хінтинг), тож міряємо: крок 2 % униз, поки найдовший не влізе.
            // Стискаємо в пікселях — sp з Android 14 масштабується нелінійно. Нижче 85 % звичайного кегля — без підписів.
            val labelStyle = remember(labels, room, base, density) {
                with(density) {
                    generateSequence(1f) { it - 0.02f }
                        .takeWhile { base.fontSize.toPx() * it >= base.fontSize.value.dp.toPx() * 0.85f }
                        .map {
                            base.copy(
                                fontSize = (base.fontSize.toPx() * it).toSp(),
                                lineHeight = (base.lineHeight.toPx() * it).toSp(),
                                letterSpacing = (base.letterSpacing.toPx() * it).toSp()
                            )
                        }
                        .firstOrNull { style ->
                            labels.all { measurer.measure(it, style, maxLines = 1, softWrap = false).size.width <= room }
                        }
                }
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .cardSurface(Radius.pill, Elevation.overlay)
                    .padding(horizontal = Spacing.xs, vertical = Spacing.xs)
                    .selectableGroup(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                items.forEach { item ->
                    TabBarItem(item, item.key == selected, labelStyle, onSelect, Modifier.weight(1f))
                }
            }
        }
        trailing?.invoke()
    }
}

/**
 * Пункт вкладки — однаковий у нижньому таббарі й у рейці широкого вікна. [labelStyle] null — лише гліф (назву скрінрідер
 * бере з опису). [wrapLabel] — у вузькій рейці підпис переноситься на другий рядок, а не обрізається.
 */
@Composable
private fun TabBarItem(
    item: TabItem, active: Boolean, labelStyle: TextStyle?, onSelect: (String) -> Unit, modifier: Modifier,
    wrapLabel: Boolean = false
) {
    val colors = Poruch.colors
    // Скрінрідер чує вкладку, її стан і бейдж одним рядком.
    val description = when {
        item.badge > 0 -> stringResource(
            R.string.tab_badge_a11y,
            item.label,
            item.badge
        )

        item.dot -> stringResource(R.string.a11y_tab_new_follows, item.label)
        else -> item.label
    }
    // Бейдж живе поза капсулою пункту: її обрізає clip для ріплу, і кут числа зникав.
    Box(modifier.coachTarget(item.tip)) {
        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clip(Radius.pill)
                .background(
                    if (active) colors.brandContainer else Color.Transparent,
                    Radius.pill
                )
                .selectable(active, role = Role.Tab) { onSelect(item.key) }
                .semantics { contentDescription = description }
                .padding(Spacing.xs),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            val tint = if (active) colors.ink else colors.inkTertiary
            Icon(item.icon, null, Modifier.size(20.dp), tint = tint)
            if (labelStyle != null) Text(
                item.label,
                style = labelStyle,
                color = tint,
                maxLines = if (wrapLabel) 2 else 1,
                softWrap = wrapLabel,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 3.dp)
            )
        }
        // Поверх кута гліфа: число справ, не повідомлень.
        if (item.badge > 0) CountBadge(
            item.badge,
            Modifier
                .align(Alignment.TopCenter)
                .offset(x = 14.dp, y = (-4).dp)
        ) else if (item.dot) Box(
            Modifier
                .align(Alignment.TopCenter)
                .offset(x = 10.dp, y = 6.dp)
                .size(8.dp)
                .background(colors.accent, CircleShape)
        )
    }
}

/** Висота квитка в каруселі мапи: 112 dp, з великим шрифтом — до 1.6 раза, щоб назва й місце не обрізались. */
@Composable
fun mapCardHeight(): Dp = 112.dp * LocalDensity.current.fontScale.coerceIn(1f, 1.6f)

/** Широке вікно (від 600 dp: планшет, телефон у ландшафті): вкладки — рейкою зліва, вміст — колонкою по центру. */
val LocalWideLayout = staticCompositionLocalOf { false }

/** Найширша колонка вмісту на широкому вікні: квитки й рядки тексту лишаються читабельними, а не розтягнутими. */
val ContentMaxWidth = 720.dp

/** Скільки місця забирає рейка вкладок зліва разом із полями. */
val NavRailClearance = 72.dp + Spacing.md * 2

/**
 * Екран-колонка: на широкому вікні вміст стоїть по центру шириною до [ContentMaxWidth], на телефоні — як був.
 * Мапа сюди не йде: вона на весь екран.
 */
@Composable
fun ContentColumn(content: @Composable () -> Unit) {
    if (!LocalWideLayout.current) return content()
    Box(Modifier.fillMaxSize().background(Poruch.colors.canvas), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.widthIn(max = ContentMaxWidth).fillMaxHeight()) { content() }
    }
}

/**
 * Рейка вкладок широкого вікна (Material: навігаційна рейка замість нижньої панелі): та сама картка, що й таббар,
 * стовпцем зліва; кнопка створення — над нею.
 */
@Composable
fun PoruchNavRail(
    items: List<TabItem>,
    selected: String,
    modifier: Modifier = Modifier,
    onSelect: (String) -> Unit,
    header: @Composable (() -> Unit)? = null
) {
    Column(
        modifier.padding(horizontal = Spacing.md),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        header?.invoke()
        Column(
            Modifier
                .width(72.dp)
                .cardSurface(Radius.xl, Elevation.overlay)
                .padding(Spacing.xs)
                .selectableGroup(),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            items.forEach { item ->
                TabBarItem(item, item.key == selected, MaterialTheme.typography.labelSmall, onSelect, Modifier.fillMaxWidth(), wrapLabel = true)
            }
        }
    }
}

@Composable
fun CreateButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Box(
        modifier
            .size(56.dp)
            .shadow(
                Elevation.overlay,
                CircleShape,
                clip = false,
                ambientColor = colors.shadowAmbient,
                spotColor = colors.shadowSpot
            )
            .background(brandGradient(), CircleShape)
            .clip(CircleShape)
            .pressable(pressedScale = 0.94f, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            PoruchIcons.plus,
            stringResource(R.string.create),
            Modifier.size(24.dp),
            tint = colors.onBrand
        )
    }
}

/** Фото не додає нічого до назви, тому сховане від скрінрідера. */
@Composable
fun Modifier.decorative(): Modifier = this.clearAndSetSemantics { }

/** Банер під статус-баром, а не над таббаром. Тон несе зміст: червоний для помилки, зелений для успіху. */
@Composable
fun NoticeBanner(
    text: String,
    error: Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = Poruch.colors
    val wash = if (error) colors.dangerContainer else colors.successContainer
    val mark = if (error) colors.danger else colors.success
    Row(
        modifier
            .fillMaxWidth()
            .pressable(onClick = onDismiss)
            .cardSurface(Radius.md, Elevation.overlay)
            .padding(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier
                .size(36.dp)
                .background(wash, Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (error) PoruchIcons.alert else PoruchIcons.checkCircle, null,
                Modifier.size(20.dp), tint = mark
            )
        }
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = colors.ink,
            modifier = Modifier.weight(1f)
        )
        Icon(
            PoruchIcons.close,
            stringResource(R.string.close),
            Modifier.size(18.dp),
            tint = colors.inkTertiary
        )
    }
}

/**
 * Буфер для поля, чиє значення живе у ViewModel: відлуння зі стору приходить на кадр пізніше і
 * при швидкому наборі губило б символи. Буфер приймає вхідне значення лише коли це не відлуння
 * останньої правки (скидання, відновлена чернетка).
 */
@Composable
fun rememberBufferedText(value: String, onValueChange: (String) -> Unit): BufferedText {
    var text by remember { mutableStateOf(value) }
    var sent by remember { mutableStateOf(value) }
    if (value != sent) {
        text = value; sent = value
    }
    return BufferedText(text) { edited ->
        text = edited
        sent = edited
        onValueChange(edited)
    }
}

class BufferedText(val text: String, val onChange: (String) -> Unit)

/**
 * Перемикач у кольорах токенів. Стандартний вимкнений стан бере `surfaceContainerHighest`, якого
 * в нашій схемі нема, і на теплому папері виглядав як сіра пляма без бігунка.
 */
@Composable
fun PoruchSwitch(
    checked: Boolean,
    /** Null — перемикає весь рядок (`toggleable`), і TalkBack читає підпис рядка разом зі станом. */
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier
) {
    val colors = Poruch.colors
    Switch(
        checked, onCheckedChange, modifier,
        colors = SwitchDefaults.colors(
            checkedTrackColor = colors.brand,
            checkedThumbColor = colors.onBrand,
            checkedBorderColor = colors.brand,
            uncheckedTrackColor = colors.surfaceMuted,
            uncheckedThumbColor = colors.inkTertiary,
            uncheckedBorderColor = colors.hairline
        )
    )
}
