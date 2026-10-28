package app.poruch.android.ui

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.poruch.domain.EventCategory

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
        // Широке вікно: таббар — рейка зліва, знизу під нього місця не треба.
        bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() +
            if (LocalWideLayout.current) Spacing.lg else 56.dp + Spacing.md + Spacing.lg
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

/** Фото не додає нічого до назви, тому сховане від скрінрідера. */
@Composable
fun Modifier.decorative(): Modifier = this.clearAndSetSemantics { }
