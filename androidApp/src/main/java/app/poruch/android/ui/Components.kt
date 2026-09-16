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
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.domain.Attendee
import app.poruch.domain.Event
import coil3.compose.AsyncImage

/**
 * Поверхня картки з двома тінями: вузька малює край дотику, широка — відстань до землі. Одна тінь
 * виглядає як розмиття, дві — як об'єкт. У темній темі тіней нема (кольори прозорі), натомість
 * поверхня світлішає.
 */
@Composable
fun Modifier.cardSurface(shape: Shape = Radius.lg, elevation: Dp = Elevation.card): Modifier {
    val colors = Poruch.colors
    val lifted = if (elevation > 0.dp && !colors.dark) this
        .shadow(elevation, shape, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot)
        .shadow(elevation / 4, shape, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot)
    else this
    val fill = if (colors.dark && elevation >= Elevation.raised) colors.surfaceRaised else colors.surface
    // Піднятій картці досить тоншої лінії; плоскій потрібна повна.
    val edge = if (colors.dark || elevation == 0.dp) colors.hairline else colors.hairline.copy(alpha = 0.55f)
    return lifted.background(fill, shape).border(1.dp, edge, shape).clip(shape)
}

/**
 * Відгук на тап: поверхня трохи просідає під пальцем і повертається. Разом із тінню це робить
 * картку об'єктом, тому всі натискні поверхні беруть його замість голого `clickable`.
 * Reduced motion лишає ripple і прибирає просідання.
 */
@Composable
fun Modifier.pressable(enabled: Boolean = true, pressedScale: Float = 0.98f, onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed && !Poruch.reducedMotion) pressedScale else 1f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow),
        label = "press"
    )
    return this
        .graphicsLayer { scaleX = scale; scaleY = scale }
        .clickable(interactionSource = interaction, indication = LocalIndication.current, enabled = enabled, onClick = onClick)
}

@Composable
fun HairLine(modifier: Modifier = Modifier) = Box(modifier.fillMaxWidth().height(1.dp).background(Poruch.colors.hairline))

/** Крапка категорії: найменший носій її кольору. */
@Composable
fun CategoryDot(category: String, size: Dp = 8.dp) =
    Box(Modifier.size(size).background(categoryInk(category), CircleShape))

// ---- Пошук і чипи

@Composable
fun PoruchSearchField(
    value: String, onValueChange: (String) -> Unit, placeholder: String,
    modifier: Modifier = Modifier, activeFilters: Int = 0, onFilters: (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.weight(1f).height(48.dp).cardSurface(Radius.pill, Elevation.card).padding(horizontal = Spacing.lg),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Icon(PoruchIcons.search, null, Modifier.size(18.dp), tint = colors.inkSecondary)
            BasicTextField(
                value = value, onValueChange = onValueChange, singleLine = true, modifier = Modifier.weight(1f),
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.ink),
                cursorBrush = SolidColor(colors.ink),
                decorationBox = { inner ->
                    if (value.isEmpty()) Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = colors.inkTertiary)
                    inner()
                }
            )
            // Значок дрібний, зона дотику повна: у 18 dp не влучиш.
            if (value.isNotEmpty()) Box(
                Modifier.minimumInteractiveComponentSize().clip(CircleShape)
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
                activeFilters.toString(), style = MaterialTheme.typography.labelSmall, color = colors.onBrand,
                modifier = Modifier.align(Alignment.TopEnd).size(18.dp).background(colors.accent, CircleShape)
                    .wrapContentSize(Alignment.Center)
            )
        }
    }
}

@Composable
fun IconPill(icon: ImageVector, contentDescription: String, selected: Boolean = false, size: Dp = 48.dp, onClick: () -> Unit) {
    val colors = Poruch.colors
    Box(
        Modifier.minimumInteractiveComponentSize().size(size)
            .shadow(if (colors.dark) 0.dp else Elevation.card, CircleShape, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot)
            .background(if (selected) brandGradient() else SolidColor(colors.surface), CircleShape)
            .border(1.dp, if (selected) Color.Transparent else colors.hairline, CircleShape)
            .clip(CircleShape).pressable(onClick = onClick).semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center
    ) { Icon(icon, null, Modifier.size(20.dp), tint = if (selected) colors.onBrand else colors.ink) }
}

/**
 * Потяг стрічки вниз. Вміст має вміти прокручуватись, інакше жест нікуди не дійде.
 * [underStatusBar] — вміст заходить під смугу статусу (хедер із градієнтом, обкладинка): тоді
 * індикатор відступає від неї, інакше коло висіло б на годиннику.
 */
@Composable
fun PullToRefresh(
    refreshing: Boolean, onRefresh: () -> Unit, modifier: Modifier = Modifier, underStatusBar: Boolean = false,
    content: @Composable BoxScope.() -> Unit
) {
    val colors = Poruch.colors
    val state = rememberPullToRefreshState()
    PullToRefreshBox(
        isRefreshing = refreshing, onRefresh = onRefresh, modifier = modifier, state = state,
        indicator = {
            PullToRefreshDefaults.Indicator(
                state = state, isRefreshing = refreshing,
                modifier = Modifier.align(Alignment.TopCenter).then(if (underStatusBar) Modifier.statusBarsPadding() else Modifier),
                containerColor = colors.surface, color = colors.ink
            )
        },
        content = content
    )
}

/** Чип: біла пігулка над папером; обраний заливається чорнилом і сидить вище, тож стан видно з тіні. */
@Composable
fun PoruchChip(label: String, selected: Boolean, onClick: () -> Unit, icon: ImageVector? = null, dot: String? = null) {
    val colors = Poruch.colors
    Row(
        Modifier.minimumInteractiveComponentSize().height(38.dp)
            .shadow(
                if (colors.dark) 0.dp else if (selected) Elevation.raised else Elevation.card,
                Radius.pill, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot
            )
            .background(if (selected) brandGradient() else SolidColor(colors.surface), Radius.pill)
            .border(1.dp, if (selected) Color.Transparent else colors.hairline, Radius.pill)
            .clip(Radius.pill).pressable(onClick = onClick).padding(horizontal = Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        when {
            dot != null -> Box(Modifier.size(8.dp).background(if (selected) colors.onBrand else categoryInk(dot), CircleShape))
            icon != null -> Icon(icon, null, Modifier.size(15.dp), tint = if (selected) colors.onBrand else colors.inkSecondary)
        }
        Text(label, style = MaterialTheme.typography.labelMedium, color = if (selected) colors.onBrand else colors.ink, maxLines = 1)
    }
}

/** Плитка категорії: скруглений квадрат у пастелі категорії. */
@Composable
fun CategoryTile(category: String, selected: Boolean, onClick: () -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.width(76.dp).clip(Radius.md).pressable(onClick = onClick).padding(vertical = Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        Box(
            Modifier.size(60.dp)
                .shadow(
                    if (colors.dark) 0.dp else Elevation.card, Radius.sm, clip = false,
                    ambientColor = categoryColor(category).copy(alpha = 0.20f), spotColor = categoryColor(category).copy(alpha = 0.30f)
                )
                .background(categoryGradient(category), Radius.sm)
                .border(
                    if (selected) 2.dp else 1.dp,
                    if (selected) colors.ink else categoryColor(category).copy(alpha = 0.18f), Radius.sm
                ),
            contentAlignment = Alignment.Center
        ) { Icon(categoryIcon(category), null, Modifier.size(24.dp), tint = categoryInk(category)) }
        Text(
            stringResource(categoryLabel(category)), style = MaterialTheme.typography.labelMedium,
            color = if (selected) colors.ink else colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis
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
        Modifier.background(background, Radius.pill).padding(horizontal = Spacing.md, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        icon?.let { Icon(it, null, Modifier.size(13.dp), tint = foreground) }
        Text(text, style = MaterialTheme.typography.labelSmall, color = foreground)
    }
}

@Composable
fun PrimaryButton(
    text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, loading: Boolean = false, icon: ImageVector? = null, tone: Color? = null
) {
    val colors = Poruch.colors
    val background: Brush = when {
        !enabled -> SolidColor(colors.surfaceMuted)
        tone != null -> Brush.verticalGradient(listOf(tone.copy(alpha = 0.92f), tone))
        else -> brandGradient()
    }
    val foreground = if (enabled) colors.onBrand else colors.inkTertiary
    // Тінь кнопки тонована її кольором: кольорова кнопка світиться, а не кидає сіру пляму.
    val glow = (tone ?: colors.shadowSpot).copy(alpha = if (tone != null) 0.38f else 0.30f)
    Row(
        modifier.height(52.dp)
            .shadow(
                if (enabled && !colors.dark) Elevation.raised else 0.dp, Radius.pill, clip = false,
                ambientColor = glow.copy(alpha = glow.alpha * 0.6f), spotColor = glow
            )
            .background(background, Radius.pill).clip(Radius.pill)
            .pressable(enabled = enabled && !loading, onClick = onClick).padding(horizontal = Spacing.xxl),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm, Alignment.CenterHorizontally)
    ) {
        if (loading) CircularProgressIndicator(Modifier.size(18.dp), color = foreground, strokeWidth = 2.dp)
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
        modifier.height(52.dp).background(colors.surfaceMuted, Radius.pill)
            .clip(Radius.pill).pressable(enabled = enabled, onClick = onClick).padding(horizontal = Spacing.xxl),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm, Alignment.CenterHorizontally)
    ) {
        icon?.let { Icon(it, null, Modifier.size(18.dp), tint = foreground) }
        Text(text, style = MaterialTheme.typography.labelLarge, color = foreground, maxLines = 1)
    }
}

@Composable
fun GhostButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, tone: Color? = null, enabled: Boolean = true) {
    val colors = Poruch.colors
    Text(
        text, style = MaterialTheme.typography.labelLarge, color = if (enabled) tone ?: colors.ink else colors.inkTertiary,
        modifier = modifier.clip(Radius.pill).clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md)
    )
}

// ---- Структура

/** Заголовок секції: як написано в ресурсі, читабельного розміру. Капітель лишається там, де несе дані: дати, бейджі, підписи полів. */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    val colors = Poruch.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = PoruchType.sectionTitle, color = colors.ink, modifier = Modifier.weight(1f))
        if (actionLabel != null && onAction != null) Text(
            actionLabel, style = MaterialTheme.typography.labelMedium, color = colors.ink,
            modifier = Modifier.clip(Radius.pill).clickable(onClick = onAction).padding(horizontal = Spacing.sm, vertical = Spacing.xs)
        )
    }
}

@Composable
fun PageHeader(title: String, modifier: Modifier = Modifier, back: (() -> Unit)? = null, trailing: @Composable (() -> Unit)? = null) {
    val colors = Poruch.colors
    Row(
        modifier.fillMaxWidth().padding(horizontal = Spacing.page, vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        if (back != null) Box(
            Modifier.size(40.dp).cardSurface(CircleShape, Elevation.card).pressable(onClick = back),
            contentAlignment = Alignment.Center
        ) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back), Modifier.size(18.dp), tint = colors.ink) }
        Text(title, style = MaterialTheme.typography.headlineMedium, color = colors.ink, modifier = Modifier.weight(1f))
        trailing?.invoke()
    }
}

@Composable
fun EmptyState(
    icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier,
    actionLabel: String? = null, onAction: (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Column(
        modifier.fillMaxWidth().padding(Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier.size(64.dp)
                .shadow(if (colors.dark) 0.dp else Elevation.card, Radius.md, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot)
                .background(Brush.verticalGradient(listOf(colors.surface, colors.surfaceMuted)), Radius.md)
                .border(1.dp, colors.hairline, Radius.md),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, Modifier.size(26.dp), tint = colors.inkSecondary) }
        Text(title, style = MaterialTheme.typography.titleLarge, color = colors.ink)
        Text(message, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
        if (actionLabel != null && onAction != null) PrimaryButton(actionLabel, onAction, Modifier.padding(top = Spacing.sm))
    }
}

@Composable
fun BannerCard(title: String, subtitle: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector = PoruchIcons.sparkle) {
    val colors = Poruch.colors
    Row(
        modifier.fillMaxWidth().pressable(onClick = onClick)
            .shadow(if (colors.dark) 0.dp else Elevation.card, Radius.lg, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot)
            .background(Brush.linearGradient(listOf(colors.heroTop, colors.surface)), Radius.lg)
            .border(1.dp, colors.hairline, Radius.lg).clip(Radius.lg).padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier.size(44.dp).background(Brush.verticalGradient(listOf(colors.surface, colors.brandContainer)), Radius.xs)
                .border(1.dp, colors.hairline, Radius.xs),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, Modifier.size(20.dp), tint = colors.ink) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = colors.ink)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        Box(Modifier.size(32.dp).background(colors.brand, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Outlined.ArrowForward, null, Modifier.size(16.dp), tint = colors.onBrand)
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
            value = field.text, onValueChange = field.onChange, label = { Text(label) }, singleLine = singleLine,
            minLines = if (singleLine) 1 else 4, isError = error != null, shape = Radius.sm,
            modifier = Modifier.fillMaxWidth().let { if (focusRequester != null) it.focusRequester(focusRequester) else it },
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface,
                focusedBorderColor = colors.ink, unfocusedBorderColor = colors.hairline,
                focusedTextColor = colors.ink, unfocusedTextColor = colors.ink,
                focusedLabelColor = colors.ink, unfocusedLabelColor = colors.inkTertiary, cursorColor = colors.ink
            )
        )
        (error ?: supporting)?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = if (error != null) colors.danger else colors.inkTertiary,
                modifier = Modifier.padding(start = Spacing.lg))
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
    trailing: @Composable (() -> Unit)? = null
) {
    val colors = Poruch.colors
    val field = rememberBufferedText(value, onValueChange)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
        Row(
            // Висота вміщує 48 dp ціль кінцевого контролу, не переростаючи сусіднє поле.
            Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp)
                .background(colors.surface, Radius.sm).border(1.dp, colors.hairline, Radius.sm)
                .padding(horizontal = Spacing.lg, vertical = if (singleLine) 0.dp else Spacing.md),
            verticalAlignment = if (singleLine) Alignment.CenterVertically else Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            BasicTextField(
                value = field.text, onValueChange = field.onChange, singleLine = singleLine, minLines = minLines,
                modifier = Modifier.weight(1f).let { if (focusRequester != null) it.focusRequester(focusRequester) else it },
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.ink),
                cursorBrush = SolidColor(colors.ink),
                keyboardOptions = keyboardOptions,
                visualTransformation = visualTransformation,
                decorationBox = { inner ->
                    if (field.text.isEmpty() && placeholder.isNotEmpty()) {
                        Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = colors.inkTertiary)
                    }
                    inner()
                }
            )
            trailing?.invoke()
        }
        hint?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary) }
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
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp)
                .background(colors.surface, Radius.sm).border(1.dp, colors.hairline, Radius.sm)
                .clip(Radius.sm).pressable(onClick = onClick).padding(horizontal = Spacing.lg),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            Text(
                value.ifEmpty { placeholder }, style = MaterialTheme.typography.bodyLarge,
                color = if (value.isEmpty()) colors.inkTertiary else colors.ink, modifier = Modifier.weight(1f)
            )
            icon?.let { Icon(it, null, Modifier.size(18.dp), tint = colors.inkTertiary) }
        }
        hint?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary) }
    }
}

// ---- Поверхні подій

/** Обкладинка без фото — градієнт категорії з її гліфом. Фото отримує затемнення знизу під білі бейджі. */
@Composable
private fun EventImage(event: Event, modifier: Modifier) {
    Box(modifier.background(categoryGradient(event.category)), contentAlignment = Alignment.Center) {
        Icon(categoryIcon(event.category), null, Modifier.size(26.dp), tint = categoryInk(event.category))
        event.imageUrl?.let {
            AsyncImage(model = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            Box(
                Modifier.matchParentSize().background(
                    Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.28f), Color.Transparent, Color.Black.copy(alpha = 0.12f)))
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
            stringResource(if (short) R.string.attendees_short else R.string.attendees, room.attendeeCount, room.capacity)
        )
        listing != null -> MetaLine(Icons.Outlined.ConfirmationNumber, listingPrice(listing))
    }
}

/** Крапка категорії плюс опис курсивною антиквою. */
@Composable
fun EventDescriptor(event: Event, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        CategoryDot(event.category)
        Text(
            stringResource(categoryLabel(event.category)),
            style = PoruchType.descriptor, color = categoryInk(event.category), maxLines = 1
        )
        // Роздільник лише коли є текст праворуч.
        event.address.ifBlank { event.city }.takeIf { it.isNotBlank() }?.let { place ->
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
        modifier.minimumInteractiveComponentSize().size(34.dp)
            .shadow(Elevation.raised, CircleShape, clip = false, ambientColor = Color(0x1F000000), spotColor = Color(0x33000000))
            .background(colors.surface, CircleShape).border(1.dp, colors.hairline, CircleShape)
            .clip(CircleShape).pressable(onClick = onSave),
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
    event: Event, modifier: Modifier = Modifier, saved: Boolean = false, waitlisted: Boolean = false,
    onSave: (() -> Unit)? = null, onClick: () -> Unit
) {
    val colors = Poruch.colors
    val cancelled = event.isCancelled
    val badge = eventStatus(event, waitlisted)
    Column(
        modifier.fillMaxWidth().pressable(onClick = onClick).cardSurface().padding(Spacing.sm)
            .alpha(if (cancelled) 0.6f else 1f)
    ) {
        // Без фото плейсхолдер нижчий: порожній 16:9 домінував би на картці.
        Box(Modifier.fillMaxWidth().height(if (event.imageUrl != null) 168.dp else 96.dp)) {
            EventImage(event, Modifier.fillMaxSize().clip(Radius.sm))
            badge?.let { (text, tone) -> Box(Modifier.padding(Spacing.sm)) { StatusBadge(text, tone) } }
            if (onSave != null) SaveButton(saved, onSave, Modifier.align(Alignment.TopEnd).padding(Spacing.sm))
        }
        Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(cardOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                event.title.uppercase(), style = MaterialTheme.typography.titleSmall, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            EventDescriptor(event)
            EventMeta(event)
        }
    }
}

/** Компактний рядок списку: квадратне превʼю, назва, опис. */
@Composable
fun EventRow(event: Event, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = Poruch.colors
    val badge = eventStatus(event)
    Row(
        modifier.fillMaxWidth().clip(Radius.md).pressable(onClick = onClick).padding(vertical = Spacing.md)
            .alpha(if (event.isCancelled) 0.6f else 1f),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
    ) {
        EventImage(event, Modifier.size(60.dp).clip(Radius.xs))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(cardOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                event.title.uppercase(), style = MaterialTheme.typography.titleSmall, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            if (badge != null) StatusBadge(badge.first, badge.second) else EventDescriptor(event)
        }
        Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
    }
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
        modifier.height(112.dp).pressable(onClick = onClick).cardSurface(Radius.lg, Elevation.overlay)
            .border(if (focused) 2.dp else 1.dp, if (focused) colors.ink else colors.hairline, Radius.lg)
            .padding(Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
    ) {
        EventImage(event, Modifier.size(84.dp).clip(Radius.xs))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(cardOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                event.title.uppercase(), style = MaterialTheme.typography.titleSmall, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            if (badge != null) StatusBadge(badge.first, badge.second) else EventMeta(event, short = true)
        }
        if (onSave != null) SaveButton(saved, onSave)
    }
}

/** Вузька плитка для горизонтальних стрічок головної. */
@Composable
fun EventTile(event: Event, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = Poruch.colors
    Column(
        modifier.pressable(onClick = onClick).cardSurface().padding(Spacing.sm)
            .alpha(if (event.isCancelled) 0.6f else 1f),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        EventImage(event, Modifier.fillMaxWidth().height(104.dp).clip(Radius.xs))
        Column(
            Modifier.padding(horizontal = Spacing.sm).padding(bottom = Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            Text(cardOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                event.title.uppercase(), style = MaterialTheme.typography.titleSmall, color = colors.ink,
                minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            EventDescriptor(event)
        }
    }
}

/** Аватари внапуск. */
@Composable
fun AvatarStack(attendees: List<Attendee>, modifier: Modifier = Modifier, total: Int = attendees.size, size: Dp = 32.dp) {
    val colors = Poruch.colors
    val shown = attendees.take(5)
    val hidden = (total - shown.size).coerceAtLeast(0)
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        shown.forEachIndexed { index, attendee ->
            Box(
                Modifier.offset(x = -(index * 10).dp).size(size).background(colors.surfaceMuted, CircleShape)
                    .border(2.dp, colors.surface, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    attendee.name.trim().take(1).uppercase(), style = MaterialTheme.typography.labelMedium,
                    color = colors.inkSecondary
                )
                attendee.avatarUrl?.let {
                    AsyncImage(model = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().clip(CircleShape))
                }
            }
        }
        if (hidden > 0) Text(
            stringResource(R.string.attendees_more, hidden), style = MaterialTheme.typography.labelMedium,
            color = colors.inkSecondary, modifier = Modifier.offset(x = -(shown.size * 10 - 4).dp)
        )
    }
}

@Composable
fun MetaLine(icon: ImageVector, text: String, modifier: Modifier = Modifier, tone: Color? = null) {
    val colors = Poruch.colors
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(15.dp), tint = tone ?: colors.inkTertiary)
        Text(text, style = MaterialTheme.typography.bodySmall, color = tone ?: colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// ---- Навігація

data class TabItem(val key: String, val label: String, val icon: ImageVector, /** Скільки справ чекає: 0 — без бейджа. */ val badge: Int = 0)

/** Плаваючий таббар-капсула; активний пункт залитий чорнилом. */
@Composable
fun PoruchTabBar(items: List<TabItem>, selected: String, modifier: Modifier = Modifier, onSelect: (String) -> Unit, trailing: @Composable (() -> Unit)? = null) {
    val colors = Poruch.colors
    Row(modifier.padding(horizontal = Spacing.lg), horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.weight(1f).cardSurface(Radius.pill, Elevation.overlay).padding(horizontal = Spacing.xs, vertical = Spacing.sm),
            horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically
        ) {
            items.forEach { item ->
                val active = item.key == selected
                Column(
                    Modifier.weight(1f).height(42.dp).clip(Radius.pill)
                        .background(if (active) colors.brandContainer else Color.Transparent, Radius.pill)
                        .clickable { onSelect(item.key) }
                        .semantics { contentDescription = item.label },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center
                ) {
                    Box {
                        Icon(item.icon, null, Modifier.size(20.dp), tint = if (active) colors.ink else colors.inkTertiary)
                        // Бейдж поверх кута гліфа: число справ, не повідомлень.
                        if (item.badge > 0) Text(
                            item.badge.coerceAtMost(99).toString(), style = MaterialTheme.typography.labelSmall, color = colors.onBrand,
                            modifier = Modifier.align(Alignment.TopEnd).offset(x = 10.dp, y = (-6).dp)
                                .background(colors.accent, Radius.pill).padding(horizontal = 5.dp, vertical = 1.dp)
                        )
                    }
                    Text(
                        item.label, style = MaterialTheme.typography.labelSmall,
                        color = if (active) colors.ink else colors.inkTertiary,
                        maxLines = 1, overflow = TextOverflow.Clip, modifier = Modifier.padding(top = 3.dp)
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
        modifier.size(56.dp)
            .shadow(
                Elevation.overlay, CircleShape, clip = false,
                ambientColor = colors.accent.copy(alpha = 0.35f), spotColor = colors.accent.copy(alpha = 0.45f)
            )
            .background(brandGradient(), CircleShape).clip(CircleShape).pressable(pressedScale = 0.94f, onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(PoruchIcons.plus, stringResource(R.string.create), Modifier.size(24.dp), tint = colors.onBrand) }
}

/** Фото не додає нічого до назви, тому сховане від скрінрідера. */
@Composable
fun Modifier.decorative(): Modifier = this.clearAndSetSemantics { }

/** Банер під статус-баром, а не над таббаром. Тон несе зміст: червоний для помилки, зелений для успіху. */
@Composable
fun NoticeBanner(text: String, error: Boolean, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    val wash = if (error) colors.dangerContainer else colors.successContainer
    val mark = if (error) colors.danger else colors.success
    Row(
        modifier.fillMaxWidth().pressable(onClick = onDismiss).cardSurface(Radius.md, Elevation.overlay)
            .padding(Spacing.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier.size(36.dp).background(Brush.verticalGradient(listOf(wash, lerp(wash, mark, 0.16f))), Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (error) PoruchIcons.alert else PoruchIcons.checkCircle, null,
                Modifier.size(20.dp), tint = mark
            )
        }
        Text(text, style = MaterialTheme.typography.bodyMedium, color = colors.ink, modifier = Modifier.weight(1f))
        Icon(Icons.Outlined.Close, stringResource(R.string.close), Modifier.size(18.dp), tint = colors.inkTertiary)
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
    if (value != sent) { text = value; sent = value }
    return BufferedText(text) { edited ->
        text = edited
        sent = edited
        onValueChange(edited)
    }
}

class BufferedText(val text: String, val onChange: (String) -> Unit)
