package app.poruch.android.ui

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.poruch.android.R

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
