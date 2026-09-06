package app.poruch.android.ui

import android.provider.Settings
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Design tokens for «Поруч». The single source of truth is docs/design-system.md; every screen
 * reads colour, spacing and radius from here rather than declaring literals inline.
 */
@Immutable
data class PoruchColors(
    val brand: Color, val brandPressed: Color, val brandContainer: Color, val onBrandContainer: Color,
    val accent: Color, val accentContainer: Color, val onAccentContainer: Color,
    val success: Color, val successContainer: Color, val onSuccessContainer: Color,
    val danger: Color, val dangerContainer: Color,
    val ink: Color, val inkSecondary: Color, val inkTertiary: Color,
    val surface: Color, val surfaceMuted: Color, val canvas: Color, val canvasTint: Color,
    val hairline: Color, val onBrand: Color, val dark: Boolean
)

/** Warm paper ground, white cards, near-black actions — the Corner reading of our palette. */
val LightPoruchColors = PoruchColors(
    brand = Color(0xFF14130F), brandPressed = Color(0xFF32302A), brandContainer = Color(0xFFEAE7DE), onBrandContainer = Color(0xFF14130F),
    accent = Color(0xFFD9603A), accentContainer = Color(0xFFFBE7DE), onAccentContainer = Color(0xFF7A2E14),
    success = Color(0xFF2F7D4F), successContainer = Color(0xFFDFF0E3), onSuccessContainer = Color(0xFF1B4C2F),
    danger = Color(0xFFB3402B), dangerContainer = Color(0xFFF8E1DC),
    ink = Color(0xFF14130F), inkSecondary = Color(0xFF6B675E), inkTertiary = Color(0xFF9A958A),
    surface = Color(0xFFFFFFFF), surfaceMuted = Color(0xFFEDEBE4), canvas = Color(0xFFF2F1ED), canvasTint = Color(0xFFEAE7DE),
    hairline = Color(0xFFE3E0D7), onBrand = Color(0xFFFBFAF7), dark = false
)

val DarkPoruchColors = PoruchColors(
    brand = Color(0xFFF5F3EE), brandPressed = Color(0xFFD9D6CE), brandContainer = Color(0xFF2A2823), onBrandContainer = Color(0xFFF5F3EE),
    accent = Color(0xFFEE8B63), accentContainer = Color(0xFF40251A), onAccentContainer = Color(0xFFFBDACB),
    success = Color(0xFF5CBF85), successContainer = Color(0xFF17301F), onSuccessContainer = Color(0xFFBFE8CD),
    danger = Color(0xFFE9705A), dangerContainer = Color(0xFF3A1A15),
    ink = Color(0xFFF5F3EE), inkSecondary = Color(0xFFA8A398), inkTertiary = Color(0xFF7C776C),
    surface = Color(0xFF1C1B19), surfaceMuted = Color(0xFF26241F), canvas = Color(0xFF131211), canvasTint = Color(0xFF1B1A18),
    hairline = Color(0xFF2F2D29), onBrand = Color(0xFF14130F), dark = true
)

/** Every category owns a deep hue for glyphs and text, plus a pastel wash for tiles and pins. */
private val CategoryHues = mapOf(
    "music" to Color(0xFF6D4AC9), "sport" to Color(0xFF0F7F73), "art" to Color(0xFFC43B6B),
    "food" to Color(0xFFC96A1E), "games" to Color(0xFF2F63C4), "outdoors" to Color(0xFF3E7D3A),
    "social" to Color(0xFFB8562F)
)
private val CategoryWashes = mapOf(
    "music" to Color(0xFFEBE4FB), "sport" to Color(0xFFDDF0EC), "art" to Color(0xFFFBE1EA),
    "food" to Color(0xFFFBEBD9), "games" to Color(0xFFE1EAFB), "outdoors" to Color(0xFFE4F1E2),
    "social" to Color(0xFFFAE5DA)
)

fun categoryColor(category: String): Color = CategoryHues[category] ?: Color(0xFF6B675E)

@Composable fun categoryWash(category: String): Color =
    if (Poruch.colors.dark) categoryColor(category).copy(alpha = 0.22f)
    else CategoryWashes[category] ?: Color(0xFFEDEBE4)

object Spacing {
    val xs = 4.dp; val sm = 8.dp; val md = 12.dp; val lg = 16.dp
    val xl = 20.dp; val xxl = 24.dp; val section = 32.dp; val page = 16.dp
}

object Radius {
    val xs = RoundedCornerShape(10.dp)
    val sm = RoundedCornerShape(14.dp)
    val md = RoundedCornerShape(16.dp)
    val lg = RoundedCornerShape(18.dp)
    val xl = RoundedCornerShape(26.dp)
    val sheet: Shape = RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp)
    val pill: Shape = CircleShape
}

object Elevation { val flat = 0.dp; val card = 1.dp; val raised = 4.dp; val overlay = 10.dp }

private val PoruchTypography = Typography(
    displaySmall = TextStyle(fontSize = 30.sp, lineHeight = 36.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.4).sp),
    headlineSmall = TextStyle(fontSize = 21.sp, lineHeight = 27.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp),
    titleLarge = TextStyle(fontSize = 19.sp, lineHeight = 25.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp),
    titleMedium = TextStyle(fontSize = 16.sp, lineHeight = 21.sp, fontWeight = FontWeight.SemiBold),
    // Card names read as small caps, the way Corner sets place names.
    titleSmall = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.3.sp),
    bodyLarge = TextStyle(fontSize = 15.sp, lineHeight = 22.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Normal),
    bodySmall = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
)

val LocalPoruchColors = staticCompositionLocalOf { LightPoruchColors }
val LocalReducedMotion = staticCompositionLocalOf { false }

object Poruch {
    val colors: PoruchColors
        @Composable @ReadOnlyComposable get() = LocalPoruchColors.current

    /** True when the system asks for less movement; screens then fade instead of sliding. */
    val reducedMotion: Boolean
        @Composable @ReadOnlyComposable get() = LocalReducedMotion.current
}

@Composable
fun PoruchTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val palette = if (dark) DarkPoruchColors else LightPoruchColors
    // «Remove animations» in Android accessibility settings zeroes the animator scale.
    val context = LocalContext.current
    val reducedMotion = remember(context) {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    val scheme = if (dark) darkColorScheme(
        primary = palette.brand, onPrimary = palette.onBrand, primaryContainer = palette.brandContainer, onPrimaryContainer = palette.onBrandContainer,
        secondaryContainer = palette.brandContainer, onSecondaryContainer = palette.onBrandContainer,
        background = palette.canvas, onBackground = palette.ink, surface = palette.surface, onSurface = palette.ink,
        surfaceVariant = palette.surfaceMuted, onSurfaceVariant = palette.inkSecondary, outline = palette.hairline, outlineVariant = palette.hairline,
        error = palette.danger, errorContainer = palette.dangerContainer
    ) else lightColorScheme(
        primary = palette.brand, onPrimary = palette.onBrand, primaryContainer = palette.brandContainer, onPrimaryContainer = palette.onBrandContainer,
        secondaryContainer = palette.brandContainer, onSecondaryContainer = palette.onBrandContainer,
        background = palette.canvas, onBackground = palette.ink, surface = palette.surface, onSurface = palette.ink,
        surfaceVariant = palette.surfaceMuted, onSurfaceVariant = palette.inkSecondary, outline = palette.hairline, outlineVariant = palette.hairline,
        error = palette.danger, errorContainer = palette.dangerContainer
    )
    CompositionLocalProvider(LocalPoruchColors provides palette, LocalReducedMotion provides reducedMotion) {
        MaterialTheme(
            colorScheme = scheme,
            typography = PoruchTypography,
            shapes = Shapes(extraSmall = Radius.xs, small = Radius.sm, medium = Radius.md, large = Radius.lg, extraLarge = Radius.xl),
            content = content
        )
    }
}
