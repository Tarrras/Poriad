package app.poruch.android.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.*
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
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
import app.poruch.domain.Attendee
import app.poruch.domain.Event
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
 * Відгук на тап: поверхня трохи просідає під пальцем і повертається. Разом із тінню це робить
 * картку об'єктом, тому всі натискні поверхні беруть його замість голого `clickable`.
 * Reduced motion лишає ripple і прибирає просідання.
 */
@Composable
fun Modifier.pressable(
    enabled: Boolean = true,
    pressedScale: Float = 0.98f,
    role: Role? = Role.Button,
    onClick: () -> Unit
): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed && !Poruch.reducedMotion) pressedScale else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMediumLow
        ),
        label = "press"
    )
    return this
        .graphicsLayer { scaleX = scale; scaleY = scale }
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
fun Modifier.tabBarClearance(): Modifier =
    navigationBarsPadding().padding(bottom = 56.dp + Spacing.md + Spacing.lg)

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
fun CategoryDot(category: String, size: Dp = 8.dp) =
    Box(
        Modifier
            .size(size)
            .background(categoryInk(category), CircleShape)
    )

// ---- Пошук і чипи

@Composable
fun PoruchSearchField(
    value: String, onValueChange: (String) -> Unit, placeholder: String,
    modifier: Modifier = Modifier, activeFilters: Int = 0, onFilters: (() -> Unit)? = null
) {
    val colors = Poruch.colors
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
                modifier = Modifier.weight(1f),
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
                    Icons.Outlined.Cancel, stringResource(R.string.clear_search),
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
                    .background(colors.accent, CircleShape)
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
    dot: String? = null,
    /** Гліф після підпису: шеврон каже, що чип відкриває вибір, а не перемикає фільтр. */
    trailingIcon: ImageVector? = null,
    /** Скільки непрочитаних чатів у цьому розрізі. */
    badge: Int = 0
) {
    val colors = Poruch.colors
    Row(
        Modifier
            .minimumInteractiveComponentSize()
            .height(38.dp)
            .background(if (selected) brandGradient() else SolidColor(colors.surface), Radius.pill)
            .border(
                1.dp,
                if (selected || !colors.dark) Color.Transparent else colors.hairline,
                Radius.pill
            )
            .clip(Radius.pill)
            .semantics { this.selected = selected }
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg),
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
            maxLines = 1
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
                    .height(40.dp)
                    .clip(Radius.pill)
                    .background(if (active) colors.surface else Color.Transparent, Radius.pill)
                    .selectable(active, role = Role.Tab) { if (!active) onSelect(index) },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    title,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (active) colors.ink else colors.inkSecondary,
                    maxLines = 1
                )
            }
        }
    }
}

/** Плитка категорії: скруглений квадрат у пастелі категорії. */
@Composable
fun CategoryTile(category: String, selected: Boolean, onClick: () -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier
            .width(76.dp)
            .clip(Radius.md)
            .pressable(onClick = onClick)
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
        Text(
            stringResource(categoryLabel(category)),
            style = MaterialTheme.typography.labelMedium,
            color = if (selected) colors.ink else colors.inkSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/** Картка категорії для сіток вибору (онбординг, редактор): пастель на всю картку, гліф угорі, назва внизу, позначка в кутку. */
@Composable
fun CategoryCard(
    category: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    role: Role = Role.Checkbox,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    Column(
        modifier
            .heightIn(min = 96.dp)
            .clip(Radius.md)
            .background(categoryGradient(category), Radius.md)
            .border(2.dp, if (selected) colors.ink else Color.Transparent, Radius.md)
            .selectable(selected, role = role, onClick = onClick)
            .padding(Spacing.md),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Icon(categoryIcon(category), null, Modifier.size(24.dp), tint = categoryInk(category))
            Spacer(Modifier.weight(1f))
            Box(
                Modifier
                    .size(20.dp)
                    .background(
                        if (selected) colors.brand else colors.surface.copy(alpha = 0.7f),
                        CircleShape
                    ),
                contentAlignment = Alignment.Center
            ) {
                if (selected) Icon(
                    Icons.Outlined.Check,
                    null,
                    Modifier.size(12.dp),
                    tint = colors.onBrand
                )
            }
        }
        Text(
            stringResource(categoryLabel(category)),
            style = MaterialTheme.typography.labelMedium,
            color = colors.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = Spacing.md)
        )
    }
}

// ---- Бейджі й кнопки

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
        tone != null -> Brush.verticalGradient(listOf(tone.copy(alpha = 0.92f), tone))
        else -> brandGradient()
    }
    val foreground = if (enabled) colors.onBrand else colors.inkTertiary
    Row(
        modifier
            .height(52.dp)
            .background(background, Radius.pill)
            .clip(Radius.pill)
            .pressable(enabled = enabled && !loading, onClick = onClick)
            .padding(horizontal = Spacing.xxl),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm, Alignment.CenterHorizontally)
    ) {
        if (loading) CircularProgressIndicator(
            Modifier.size(18.dp),
            color = foreground,
            strokeWidth = 2.dp
        )
        else icon?.let { Icon(it, null, Modifier.size(18.dp), tint = foreground) }
        Text(text, style = MaterialTheme.typography.labelLarge, color = foreground, maxLines = 1)
    }
}

@Composable
fun SecondaryButton(
    text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, icon: ImageVector? = null, tone: Color? = null
) {
    val colors = Poruch.colors
    val foreground = if (enabled) tone ?: colors.ink else colors.inkTertiary
    Row(
        modifier
            .height(52.dp)
            .background(colors.brandContainer, Radius.pill)
            .clip(Radius.pill)
            .pressable(enabled = enabled, onClick = onClick)
            .padding(horizontal = Spacing.xxl),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm, Alignment.CenterHorizontally)
    ) {
        icon?.let { Icon(it, null, Modifier.size(18.dp), tint = foreground) }
        Text(text, style = MaterialTheme.typography.labelLarge, color = foreground, maxLines = 1)
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
        modifier = modifier
            .clip(Radius.pill)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md)
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
            style = PoruchType.sectionTitle,
            color = colors.ink,
            modifier = Modifier.weight(1f)
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
                Icons.AutoMirrored.Outlined.ArrowBack,
                stringResource(R.string.back),
                Modifier.size(18.dp),
                tint = colors.ink
            )
        }
        Text(
            title,
            style = MaterialTheme.typography.headlineMedium,
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
        // Кола й крапка «шукаємо поруч» довкола гліфа; їм можна вийти за рамку, під ними лише відступи.
        Box(
            Modifier.size(if (Poruch.reducedMotion) 64.dp else 120.dp),
            contentAlignment = Alignment.Center
        ) {
            if (!Poruch.reducedMotion) BrandAnimation(R.raw.empty, Modifier.requiredSize(160.dp))
            Box(
                Modifier
                    .size(64.dp)
                    .cardSurface(Radius.md),
                contentAlignment = Alignment.Center
            ) { Icon(icon, null, Modifier.size(26.dp), tint = colors.inkSecondary) }
        }
        // Довгі рядки переносяться: по центру, як і значок над ними.
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
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

@Composable
fun BannerCard(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector = PoruchIcons.sparkle
) {
    val colors = Poruch.colors
    Row(
        modifier
            .fillMaxWidth()
            .pressable(onClick = onClick)
            .cardSurface()
            .padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier
                .size(44.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, Modifier.size(20.dp), tint = colors.ink) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = colors.ink)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        Box(
            Modifier
                .size(32.dp)
                .background(colors.brand, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.AutoMirrored.Outlined.ArrowForward,
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
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = colors.inkTertiary
        )
        Row(
            // Висота вміщує 48 dp ціль кінцевого контролу, не переростаючи сусіднє поле.
            Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 56.dp)
                // Біле поле на сірому полотні: `surfaceMuted` відрізнявся від полотна на два тони і поле зникало.
                .background(colors.surface, Radius.sm)
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
                .background(colors.surface, Radius.sm)
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
private fun EventImage(event: Event, modifier: Modifier, glyphSize: Dp = 26.dp) {
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

/** Рядок стану над карткою. Афіша завжди підписана джерелом (docs/event-ingestion.md §8); місця й черга лише в кімнати. */
@Composable
private fun eventStatus(event: Event, waitlisted: Boolean = false): Pair<String, BadgeTone>? {
    if (event.isCancelled) return stringResource(R.string.cancelled) to BadgeTone.Danger
    event.listing?.let { listing ->
        return if (listing.isWithdrawn) stringResource(R.string.listing_withdrawn) to BadgeTone.Neutral
        else stringResource(R.string.listing_badge, listing.sourceName) to BadgeTone.Neutral
    }
    val room = event.gathering ?: return null
    // Місця й «ви йдете» після кінця нічого не кажуть: рядок покаже категорію.
    if (event.hasEnded(kotlin.time.Clock.System.now())) return null
    return when {
        room.joined -> stringResource(R.string.going) to BadgeTone.Success
        waitlisted -> stringResource(R.string.in_queue) to BadgeTone.Accent
        room.isFull -> stringResource(R.string.full) to BadgeTone.Neutral
        room.isScarce -> stringResource(R.string.seats_left, room.seatsLeft) to BadgeTone.Accent
        else -> null
    }
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

        listing != null -> MetaLine(Icons.Outlined.ConfirmationNumber, listingPrice(listing))
    }
}

/** Крапка категорії плюс її назва кольором категорії. */
@Composable
fun EventDescriptor(event: Event, modifier: Modifier = Modifier, withCity: Boolean = false) {
    val colors = Poruch.colors
    Row(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CategoryDot(event.category)
        Text(
            stringResource(categoryLabel(event.category)),
            style = PoruchType.descriptor, color = categoryInk(event.category), maxLines = 1
        )
        // Роздільник лише коли є текст праворуч.
        // Місто першим: у видачі з різних міст воно важливіше за адресу й не зникає під трьома крапками.
        val place = if (withCity) listOf(event.city, event.address).filter { it.isNotBlank() }
            .joinToString(", ")
        else event.address.ifBlank { event.city }
        place.takeIf { it.isNotBlank() }?.let { place ->
            Text(
                "· $place",
                style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun SaveButton(saved: Boolean, onSave: () -> Unit, modifier: Modifier = Modifier) {
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

/** Картка стрічки: фото, надрядок дати, назва, рядок опису. */
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
    val cancelled = event.isCancelled
    val badge = eventStatus(event, waitlisted)
    // Фото врівень із краєм картки: [cardSurface] обрізає вміст за радіусом картки.
    Column(
        modifier
            .fillMaxWidth()
            .pressable(onClick = onClick)
            .cardSurface()
            .alpha(if (cancelled) 0.6f else 1f)
    ) {
        // Без фото плейсхолдер нижчий: порожній 16:9 домінував би на картці.
        Box(
            Modifier
                .fillMaxWidth()
                .height(if (event.imageUrl != null) 200.dp else 120.dp)
        ) {
            EventImage(event, Modifier.fillMaxSize())
            badge?.let { (text, tone) ->
                Box(Modifier.padding(Spacing.md)) {
                    StatusBadge(
                        text,
                        tone
                    )
                }
            }
            if (onSave != null) SaveButton(
                saved,
                onSave,
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(Spacing.md)
            )
        }
        Column(
            Modifier.padding(Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            Text(
                cardOverline(event, dateWords()),
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkTertiary
            )
            Text(
                event.title, style = MaterialTheme.typography.titleSmall, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            EventDescriptor(event, withCity = withCity)
            EventMeta(event)
        }
    }
}

/** Компактний рядок списку: квадратне превʼю, назва, опис. */
@Composable
fun EventRow(event: Event, modifier: Modifier = Modifier, unread: Int = 0, onClick: () -> Unit) {
    val colors = Poruch.colors
    val badge = eventStatus(event)
    val unreadLabel =
        if (unread > 0) stringResource(R.string.unread_messages_a11y, unread) else null
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { unreadLabel?.let { stateDescription = it } }
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md)
            .alpha(if (event.isCancelled) 0.6f else 1f),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        EventImage(
            event, Modifier
                .size(60.dp)
                .clip(Radius.xs)
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(
                cardOverline(event, dateWords()),
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkTertiary
            )
            Text(
                event.title, style = MaterialTheme.typography.titleSmall, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            if (badge != null) StatusBadge(badge.first, badge.second) else EventDescriptor(event)
        }
        // Непрочитане в чаті — той самий бейдж, що на вкладці: видно, куди він веде.
        if (unread > 0) CountBadge(unread)
        Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
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
            .background(colors.accent, Radius.pill)
            .padding(horizontal = 6.dp, vertical = 1.dp)
    )
}

/** Картка каруселі над мапою: досить широка для назви, досить низька, щоб мапу було видно. */
@Composable
fun EventMapCard(
    event: Event, modifier: Modifier = Modifier, focused: Boolean = false,
    saved: Boolean = false, onSave: (() -> Unit)? = null, onClick: () -> Unit
) {
    val colors = Poruch.colors
    val badge = eventStatus(event)
    Row(
        modifier
            .height(112.dp)
            .pressable(onClick = onClick)
            .cardSurface(Radius.lg, Elevation.overlay)
            .border(2.dp, if (focused) colors.ink else Color.Transparent, Radius.lg)
            .padding(Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        EventImage(
            event, Modifier
                .size(84.dp)
                .clip(Radius.xs)
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(
                cardOverline(event, dateWords()),
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkTertiary
            )
            Text(
                event.title, style = MaterialTheme.typography.titleSmall, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            if (badge != null) StatusBadge(badge.first, badge.second) else EventMeta(
                event,
                short = true
            )
        }
        if (onSave != null) SaveButton(saved, onSave)
    }
}

/** Вузька плитка для горизонтальних стрічок головної. */
@Composable
fun EventTile(event: Event, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = Poruch.colors
    Column(
        modifier
            .pressable(onClick = onClick)
            .cardSurface()
            .alpha(if (event.isCancelled) 0.6f else 1f)
    ) {
        EventImage(
            event, Modifier
                .fillMaxWidth()
                .height(120.dp)
        )
        Column(
            Modifier.padding(Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            Text(
                cardOverline(event, dateWords()),
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkTertiary
            )
            Text(
                event.title, style = MaterialTheme.typography.titleSmall, color = colors.ink,
                minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            EventDescriptor(event)
        }
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
            .background(colors.surfaceMuted),
        contentAlignment = Alignment.Center
    ) {
        Text(
            name.trim().take(1).uppercase(),
            style = if (size >= 56.dp) MaterialTheme.typography.headlineMedium else MaterialTheme.typography.labelMedium,
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

/** Велика картка-афіша: обкладинка на всю висоту, текст на затемненні внизу. Одна на екран, для головного. */
@Composable
fun EventHeroCard(
    event: Event, eyebrow: String, modifier: Modifier = Modifier,
    saved: Boolean = false, onSave: (() -> Unit)? = null, onClick: () -> Unit
) {
    val colors = Poruch.colors
    val badge = eventStatus(event)
    Box(
        modifier
            .fillMaxWidth()
            .height(360.dp)
            .pressable(onClick = onClick)
            .clip(Radius.xl)
            .alpha(if (event.isCancelled) 0.6f else 1f)
    ) {
        EventImage(event, Modifier.fillMaxSize(), glyphSize = 56.dp)
        Box(
            Modifier
                .matchParentSize()
                .background(
                    Brush.verticalGradient(
                        0.3f to Color.Transparent,
                        0.7f to Color.Black.copy(alpha = 0.55f),
                        1f to Color.Black.copy(alpha = 0.85f)
                    )
                )
        )
        badge?.let { (text, tone) -> Box(Modifier.padding(Spacing.lg)) { StatusBadge(text, tone) } }
        if (onSave != null) SaveButton(
            saved,
            onSave,
            Modifier
                .align(Alignment.TopEnd)
                .padding(Spacing.md)
        )
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .padding(Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            Text(
                eyebrow.uppercase(),
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.75f)
            )
            Text(
                event.title,
                style = MaterialTheme.typography.headlineMedium,
                color = Color.White,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                cardOverline(
                    event,
                    dateWords()
                ) + " · " + stringResource(categoryLabel(event.category)),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.85f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** Широка картка горизонтальної стрічки: фото врівень із краєм, текст під ним. Сусідня визирає з-за краю. */
@Composable
fun EventRailCard(
    event: Event,
    modifier: Modifier = Modifier,
    saved: Boolean = false,
    onSave: (() -> Unit)? = null,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val badge = eventStatus(event)
    Column(
        modifier
            .width(300.dp)
            .pressable(onClick = onClick)
            .cardSurface()
            .alpha(if (event.isCancelled) 0.6f else 1f)
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(170.dp)
        ) {
            EventImage(event, Modifier.fillMaxSize(), glyphSize = 32.dp)
            badge?.let { (text, tone) ->
                Box(Modifier.padding(Spacing.md)) {
                    StatusBadge(
                        text,
                        tone
                    )
                }
            }
            if (onSave != null) SaveButton(
                saved,
                onSave,
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(Spacing.sm)
            )
        }
        Column(
            Modifier.padding(Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            Text(
                cardOverline(event, dateWords()),
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkTertiary
            )
            Text(
                event.title,
                style = MaterialTheme.typography.titleSmall,
                color = colors.ink,
                minLines = 2,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            EventDescriptor(event)
            EventMeta(event, short = true)
        }
    }
}

/** Швидка дія на пів ширини: гліф у колі, надрядок, назва. */
@Composable
fun QuickActionCard(
    eyebrow: String, title: String, icon: ImageVector, onClick: () -> Unit,
    modifier: Modifier = Modifier, filled: Boolean = false
) {
    val colors = Poruch.colors
    val ink = if (filled) colors.onBrand else colors.ink
    Column(
        // Незалита картка — звичайна поверхня, з лінією по краю в темній темі, як усі картки поруч.
        modifier
            .then(
                if (filled) Modifier
                    .clip(Radius.lg)
                    .background(colors.brand) else Modifier.cardSurface()
            )
            .pressable(onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = "$eyebrow: $title" }
            .padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(
                    if (filled) colors.onBrand.copy(alpha = 0.14f) else colors.surfaceMuted,
                    CircleShape
                ),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, Modifier.size(20.dp), tint = ink) }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                eyebrow.uppercase(),
                style = MaterialTheme.typography.labelSmall,
                color = ink.copy(alpha = 0.7f)
            )
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                color = ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** Рядок групового списку: гліф, назва, підпис, справа значення й шеврон. Кілька рядків збирає [GroupedRows]. */
@Composable
fun LinkRow(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
    value: String? = null
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
        }
        if (value != null) Text(
            value,
            style = MaterialTheme.typography.titleLarge,
            color = colors.ink
        )
        Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
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
    val badge: Int = 0
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
        Row(
            Modifier
                .weight(1f)
                .cardSurface(Radius.pill, Elevation.overlay)
                .padding(horizontal = Spacing.xs, vertical = Spacing.xs)
                .selectableGroup(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            items.forEach { item ->
                val active = item.key == selected
                // Скрінрідер чує вкладку, її стан і бейдж одним рядком.
                val description = if (item.badge > 0) stringResource(
                    R.string.tab_badge_a11y,
                    item.label,
                    item.badge
                ) else item.label
                // Бейдж живе поза капсулою пункту: її обрізає clip для ріплу, і кут числа зникав.
                Box(Modifier.weight(1f)) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .height(48.dp)
                            .clip(Radius.pill)
                            .background(
                                if (active) colors.brandContainer else Color.Transparent,
                                Radius.pill
                            )
                            .selectable(active, role = Role.Tab) { onSelect(item.key) }
                            .semantics { contentDescription = description },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            item.icon,
                            null,
                            Modifier.size(20.dp),
                            tint = if (active) colors.ink else colors.inkTertiary
                        )
                        Text(
                            item.label,
                            style = MaterialTheme.typography.labelSmall,
                            color = if (active) colors.ink else colors.inkTertiary,
                            maxLines = 1,
                            overflow = TextOverflow.Clip,
                            modifier = Modifier.padding(top = 3.dp)
                        )
                    }
                    // Поверх кута гліфа: число справ, не повідомлень.
                    if (item.badge > 0) CountBadge(
                        item.badge,
                        Modifier
                            .align(Alignment.TopCenter)
                            .offset(x = 14.dp, y = (-4).dp)
                    )
                }
            }
        }
        trailing?.invoke()
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
            Icons.Outlined.Close,
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
    onCheckedChange: (Boolean) -> Unit,
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
