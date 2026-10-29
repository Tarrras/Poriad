package app.poruch.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.R

/** Кнопки — зібрані прямокутники з кутом квитка, а не пігулки: пігулками лишились чипи й бейджі. */
val ButtonShape = Radius.md

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

/**
 * Текстова дія — завжди ця кнопка, а не `Text().pressable()`: ціль 48 dp на Android. [onClickLabel] — що саме зробить
 * дотик, коли напис сам не каже («Скасувати» → «Скасувати пошук компанії»). [trailingIcon] — шеврон «Детальніше ›».
 */
@Composable
fun GhostButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tone: Color? = null,
    enabled: Boolean = true,
    onClickLabel: String? = null,
    trailingIcon: ImageVector? = null
) {
    val colors = Poruch.colors
    val color = if (enabled) tone ?: colors.ink else colors.inkTertiary
    Row(
        // Ціль 48 dp при тексті на рядок: вирівнюємо по центру, а не добираємо полями.
        modifier
            .clip(Radius.pill)
            .clickable(enabled = enabled, onClickLabel = onClickLabel, role = Role.Button, onClick = onClick)
            .heightIn(min = 48.dp)
            .padding(horizontal = Spacing.lg, vertical = Spacing.xs),
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = color)
        trailingIcon?.let { Icon(it, null, Modifier.size(14.dp), tint = color) }
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

/** Кругла дія з підписом під нею: ряд таких — панель дій на деталях. */
@Composable
fun RoundAction(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    /** Дія чекає мережі: замість гліфа — індикатор, повторний тап нічого не робить. */
    loading: Boolean = false
) {
    val colors = Poruch.colors
    val ink = if (enabled) colors.ink else colors.inkTertiary
    Column(
        modifier
            .clip(Radius.md)
            .pressable(enabled = enabled && !loading, onClick = onClick)
            .padding(Spacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        Box(
            Modifier
                .size(56.dp)
                .cardSurface(CircleShape), contentAlignment = Alignment.Center
        ) {
            if (loading) CircularProgressIndicator(Modifier.size(20.dp), color = ink, strokeWidth = 2.dp)
            else Icon(icon, null, Modifier.size(22.dp), tint = ink)
        }
        // На великому шрифті — трикрапка, а не підпис, обрізаний посеред слова.
        Text(title, style = MaterialTheme.typography.labelMedium, color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
