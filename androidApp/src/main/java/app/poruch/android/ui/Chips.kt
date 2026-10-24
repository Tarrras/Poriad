package app.poruch.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.domain.EventCategory

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

/**
 * Плитка категорії: скруглений квадрат у пастелі категорії. На мапі ([counted]) під назвою — скільки подій вона дасть:
 * [count] null — видача ще їде, рядок лишається порожнім, а не бреше старим числом. Нуль — тиха плитка, але натискна:
 * жанр обирають і до дати («музика — а коли?»), а вибрана мусить зніматись.
 */
@Composable
fun CategoryTile(
    category: EventCategory, selected: Boolean, counted: Boolean = false, count: Int? = null, onClick: () -> Unit
) {
    val colors = Poruch.colors
    val empty = count == 0
    val name = stringResource(categoryLabel(category))
    val description = count?.let { "$name, ${pluralStringResource(R.plurals.category_events, it, it)}" }
    Column(
        Modifier
            .width(76.dp)
            .clip(Radius.md)
            .pressable(onClick = onClick)
            // Обрана плитка — стан для TalkBack, а не лише рамка; число — у назві, як на iOS.
            .semantics {
                this.selected = selected
                description?.let { contentDescription = it }
            }
            .padding(vertical = Spacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        Box(
            Modifier
                .size(60.dp)
                // Нуль — тиха поверхня, як порожній квиток, а не пастель жанру.
                .then(if (empty) Modifier.background(colors.surfaceMuted, Radius.md) else Modifier.background(categoryGradient(category), Radius.md))
                .border(2.dp, if (selected) colors.ink else Color.Transparent, Radius.md),
            contentAlignment = Alignment.Center
        ) { Icon(categoryIcon(category), null, Modifier.size(24.dp), tint = if (empty) colors.inkTertiary else categoryInk(category)) }
        val ink = when {
            selected -> colors.ink
            empty -> colors.inkTertiary
            else -> colors.inkSecondary
        }
        // Назву й число читає опис плитки: окремо вони прозвучали б двічі.
        val quiet = if (description != null) Modifier.clearAndSetSemantics {} else Modifier
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            // «Конференції» в 76 dp стискаються, а не обрізаються.
            val label = MaterialTheme.typography.labelMedium.copy(color = ink)
            BasicText(
                name, quiet, style = label, maxLines = 1,
                autoSize = TextAutoSize.StepBased(label.fontSize * 0.7f, label.fontSize)
            )
            // Порожній рядок тієї ж висоти, поки числа нема: плитки не підскакують, коли воно приходить.
            if (counted) Text(
                count?.toString() ?: " ", quiet, style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"),
                color = ink, maxLines = 1
            )
        }
    }
}

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
