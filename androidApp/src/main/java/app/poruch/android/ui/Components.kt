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
 * Card surface: white, lifted off the paper by two shadows — a tight one that draws the contact
 * edge and a wide one that reads as the distance to the ground. One shadow at this radius looks
 * like a blur; two look like an object.
 *
 * Dark mode drops both (its shadow colours are transparent) and steps the surface up instead: on a
 * near-black canvas a cast shadow is invisible, and a lighter fill is what actually reads as near.
 */
@Composable
fun Modifier.cardSurface(shape: Shape = Radius.lg, elevation: Dp = Elevation.card): Modifier {
    val colors = Poruch.colors
    val lifted = if (elevation > 0.dp && !colors.dark) this
        .shadow(elevation, shape, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot)
        .shadow(elevation / 4, shape, clip = false, ambientColor = colors.shadowAmbient, spotColor = colors.shadowSpot)
    else this
    val fill = if (colors.dark && elevation >= Elevation.raised) colors.surfaceRaised else colors.surface
    // A lit card needs less line to hold it; a flat one still needs the full hairline.
    val edge = if (colors.dark || elevation == 0.dp) colors.hairline else colors.hairline.copy(alpha = 0.55f)
    return lifted.background(fill, shape).border(1.dp, edge, shape).clip(shape)
}

/**
 * Tap feedback with depth: the surface dips a fraction under the finger and springs back. Paired
 * with the card shadow this is what makes a card feel like an object rather than a rectangle —
 * so every tappable surface uses it instead of a bare `clickable`.
 *
 * Reduced motion keeps the ripple and drops the dip.
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

/** Category dot: the smallest possible carrier of category colour, straight from Corner. */
@Composable
fun CategoryDot(category: String, size: Dp = 8.dp) =
    Box(Modifier.size(size).background(categoryInk(category), CircleShape))

// ---------------------------------------------------------------- search & chips

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
            // Значок лишається дрібним, а торкатися можна всієї зони: 18 dp — це втричі менше за
            // мінімальну ціль, і в нього справді не влучаєш.
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
 * Chip: lowercase label on a white pill that hovers a millimetre off the paper; selection fills it
 * with ink, the way Corner marks state. A selected chip sits *higher* than an unselected one —
 * the state is legible from the shadow alone, before the fill is read.
 */
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

/** Category tile: a rounded square washed in the category pastel, as Corner sets its rating tiles. */
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

// ---------------------------------------------------------------- badges & buttons

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
    // The action's own shadow is tinted with the action's own colour, so a coloured button glows
    // rather than casting the same grey smudge as everything else.
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

// ---------------------------------------------------------------- structure

/**
 * A section is announced the way Corner announces one: lowercase, at reading size, in the ink of
 * the content it introduces. The 11 pt caps we used before were legible but timid — they read as a
 * caption for the card above rather than a title for the row below. Caps stay where they carry
 * data: dates, badges, field labels.
 */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    val colors = Poruch.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title.lowercase(), style = PoruchType.sectionTitle, color = colors.ink, modifier = Modifier.weight(1f))
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
    /**
     * Ручка фокуса для екрана, який відкривається заради цього поля.
     *
     * Модифікатор самого поля тут не підходить: [modifier] лягає на колонку разом із підписом
     * помилки, а фокус має отримати саме введення.
     */
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

/**
 * Field in the Corner idiom: a small uppercase label above the box rather than Material's floating
 * placeholder, so a form reads as a list of named things and every field looks the same.
 */
@Composable
fun LabelledField(
    label: String, value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
    placeholder: String = "", singleLine: Boolean = true, hint: String? = null,
    /** A multi-line field opens at this height so it reads as a place for a paragraph. */
    minLines: Int = if (singleLine) 1 else 4,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    /** Ручка фокуса для екрана, який відкривається заради цього поля. */
    focusRequester: FocusRequester? = null,
    trailing: @Composable (() -> Unit)? = null
) {
    val colors = Poruch.colors
    val field = rememberBufferedText(value, onValueChange)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
        Row(
            // A trailing control reserves a 48 dp target, so the box is tall enough to hold one
            // without growing past a plain field beside it.
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

/**
 * A field whose value is chosen rather than typed — a date, a place. It looks exactly like
 * [LabelledField] on purpose: a form should read as one list of named things, not as a form with a
 * button in the middle of it.
 */
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

// ---------------------------------------------------------------- event surfaces

/**
 * A cover with no photo is not an empty box: it is the category's own gradient with the category's
 * glyph on it, so a feed of photoless events still reads as a row of coloured objects. A photo,
 * when there is one, gets a bottom scrim — white badges and the save button sit on top of it, and
 * a bright sky underneath would swallow both.
 */
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

/**
 * Один рядок стану над карткою.
 *
 * Афіша завжди підписана джерелом, і це не стилістика: без видимої атрибуції ми не маємо права
 * її показувати (docs/event-ingestion.md §8). Місця, черга й «ви йдете» стосуються тільки кімнати —
 * тепер до них не дістатися, не спитавши спершу, чи вона взагалі є.
 */
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

/**
 * Рядок під назвою: скільки людей іде — або скільки коштує квиток. Що саме, вирішує наявність
 * кімнати, а не збіг обставин: у афіші учасників немає, і «0 з 1» під чужим концертом було
 * єдиною вадою, яку тут видно неозброєним оком.
 */
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

/** Category dot plus a lowercase descriptor — the line Corner puts under every place name. */
@Composable
fun EventDescriptor(event: Event, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        CategoryDot(event.category)
        Text(
            stringResource(categoryLabel(event.category)).lowercase(),
            style = PoruchType.descriptor, color = categoryInk(event.category), maxLines = 1
        )
        // Крапка розділяє, а не прикрашає: без тексту праворуч вона читається як самотня «•».
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

/** Feed card: photo, then the date overline, the name and one descriptor line. */
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
        // Without a photo the placeholder shrinks: an empty 16:9 band would dominate the card.
        Box(Modifier.fillMaxWidth().height(if (event.imageUrl != null) 168.dp else 96.dp)) {
            EventImage(event, Modifier.fillMaxSize().clip(Radius.sm))
            badge?.let { (text, tone) -> Box(Modifier.padding(Spacing.sm)) { StatusBadge(text, tone) } }
            if (onSave != null) SaveButton(saved, onSave, Modifier.align(Alignment.TopEnd).padding(Spacing.sm))
        }
        Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(eventOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                event.title.uppercase(), style = MaterialTheme.typography.titleSmall, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            EventDescriptor(event)
            EventMeta(event)
        }
    }
}

/** Compact row for lists: square thumbnail, name, descriptor. */
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
            Text(eventOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                event.title.uppercase(), style = MaterialTheme.typography.titleSmall, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            if (badge != null) StatusBadge(badge.first, badge.second) else EventDescriptor(event)
        }
        Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
    }
}

/** Carousel card above the map: wide enough for the name, short enough to leave the map readable. */
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
            Text(eventOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                event.title.uppercase(), style = MaterialTheme.typography.titleSmall, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            if (badge != null) StatusBadge(badge.first, badge.second) else EventMeta(event, short = true)
        }
        if (onSave != null) SaveButton(saved, onSave)
    }
}

/** Narrow tile for horizontal rails on the home screen. */
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
            Text(eventOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                event.title.uppercase(), style = MaterialTheme.typography.titleSmall, color = colors.ink,
                minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            EventDescriptor(event)
        }
    }
}

/** Overlapping avatars, the social proof Meetup puts under every event. */
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

// ---------------------------------------------------------------- navigation

data class TabItem(val key: String, val label: String, val icon: ImageVector)

/** Floating capsule bar; the active item is inked while the rest stay quiet, as Corner marks tabs. */
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
                    Icon(item.icon, null, Modifier.size(20.dp), tint = if (active) colors.ink else colors.inkTertiary)
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

/** Photos carry no information the title does not, so they are hidden from screen readers. */
@Composable
fun Modifier.decorative(): Modifier = this.clearAndSetSemantics { }

/**
 * Notices land under the status bar, not over the tab bar: the eye is already at the top after a
 * tap, and the bottom edge belongs to navigation. Tone carries the meaning — a red wash for a
 * failure, green for a success — so the two never read the same at a glance.
 */
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
 * Keeps a text field responsive when its value lives in a ViewModel.
 *
 * The store answers through a flow, so its echo arrives a frame or more after the keystroke that
 * caused it. Binding the field straight to that value drops or reorders characters during fast
 * typing. The buffer holds what the reader typed and adopts an incoming value only when it is
 * *not* the echo of the last edit sent up — a reset, a restored draft, a value the store changed
 * on its own — so the loop stays unidirectional without fighting the keyboard.
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
