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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Токени дизайну. Джерело правди — docs/design-system.md; екрани беруть кольори, відступи й радіуси звідси. */
@Immutable
data class PoruchColors(
    val brand: Color, val brandPressed: Color, val brandContainer: Color, val onBrandContainer: Color,
    val accent: Color, val accentContainer: Color, val onAccentContainer: Color,
    val success: Color, val successContainer: Color, val onSuccessContainer: Color,
    val danger: Color, val dangerContainer: Color,
    val ink: Color, val inkSecondary: Color, val inkTertiary: Color,
    val surface: Color, val surfaceRaised: Color, val surfaceMuted: Color,
    val canvas: Color, val canvasTint: Color,
    /** Тепла заливка вгорі шапки, згасає в `canvas`. */
    val heroTop: Color, val heroBottom: Color,
    /** Тіні коричнево-чорні, не нейтральні: сіра тінь на теплому папері виглядає як бруд. */
    val shadowAmbient: Color, val shadowSpot: Color,
    val hairline: Color, val onBrand: Color, val dark: Boolean
)

/** Теплий папір, білі картки над ним, майже чорні дії. */
val LightPoruchColors = PoruchColors(
    brand = Color(0xFF14130F), brandPressed = Color(0xFF32302A), brandContainer = Color(0xFFEAE7DE), onBrandContainer = Color(0xFF14130F),
    accent = Color(0xFFD9603A), accentContainer = Color(0xFFFBE7DE), onAccentContainer = Color(0xFF7A2E14),
    success = Color(0xFF2F7D4F), successContainer = Color(0xFFDFF0E3), onSuccessContainer = Color(0xFF1B4C2F),
    danger = Color(0xFFB3402B), dangerContainer = Color(0xFFF8E1DC),
    ink = Color(0xFF14130F), inkSecondary = Color(0xFF6B675E), inkTertiary = Color(0xFF9A958A),
    surface = Color(0xFFFFFFFF), surfaceRaised = Color(0xFFFFFFFF), surfaceMuted = Color(0xFFEDEBE4),
    canvas = Color(0xFFF2F0EA), canvasTint = Color(0xFFEAE6DA),
    heroTop = Color(0xFFF4E7D8), heroBottom = Color(0xFFF2F0EA),
    shadowAmbient = Color(0x1A2A2016), shadowSpot = Color(0x332A2016),
    hairline = Color(0xFFE5E1D6), onBrand = Color(0xFFFBFAF7), dark = false
)

val DarkPoruchColors = PoruchColors(
    brand = Color(0xFFF5F3EE), brandPressed = Color(0xFFD9D6CE), brandContainer = Color(0xFF2A2823), onBrandContainer = Color(0xFFF5F3EE),
    accent = Color(0xFFEE8B63), accentContainer = Color(0xFF40251A), onAccentContainer = Color(0xFFFBDACB),
    success = Color(0xFF5CBF85), successContainer = Color(0xFF17301F), onSuccessContainer = Color(0xFFBFE8CD),
    danger = Color(0xFFE9705A), dangerContainer = Color(0xFF3A1A15),
    ink = Color(0xFFF5F3EE), inkSecondary = Color(0xFFA8A398), inkTertiary = Color(0xFF7C776C),
    surface = Color(0xFF1F1E1B), surfaceRaised = Color(0xFF272521), surfaceMuted = Color(0xFF2C2A25),
    canvas = Color(0xFF121110), canvasTint = Color(0xFF1B1A17),
    heroTop = Color(0xFF272119), heroBottom = Color(0xFF121110),
    shadowAmbient = Color(0x00000000), shadowSpot = Color(0x00000000),
    hairline = Color(0xFF33302B), onBrand = Color(0xFF14130F), dark = true
)

/** Глибокий відтінок категорії для гліфів і тексту; пастель для плиток і пінів робить [categoryGradient]. */
private val CategoryHues = mapOf(
    "music" to Color(0xFF6D4AC9), "sport" to Color(0xFF0F7F73), "art" to Color(0xFFC43B6B),
    "food" to Color(0xFFC96A1E), "games" to Color(0xFF2F63C4), "outdoors" to Color(0xFF3E7D3A),
    "social" to Color(0xFFB8562F),
    // Палітру будували на сім категорій. Золото й бірюза підібрані вручну за контрастом,
    // варті погляду дизайнера.
    "comedy" to Color(0xFFA07813),
    "kids" to Color(0xFF1F8A8A),
    // Олива й пурпур — середини найбільших вільних проміжків на колі відтінків, контраст у нормі.
    "tours" to Color(0xFF5F7F1F),
    "conference" to Color(0xFF933FA8)
)
private val CategoryWashes = mapOf(
    "music" to Color(0xFFEBE4FB), "sport" to Color(0xFFDDF0EC), "art" to Color(0xFFFBE1EA),
    "food" to Color(0xFFFBEBD9), "games" to Color(0xFFE1EAFB), "outdoors" to Color(0xFFE4F1E2),
    "social" to Color(0xFFFAE5DA), "comedy" to Color(0xFFF7ECD2), "kids" to Color(0xFFD9EFEF),
    "tours" to Color(0xFFECF0E4), "conference" to Color(0xFFF2E8F5)
)

/** Другий відтінок пари для градієнта обкладинки. */
private val CategoryPartners = mapOf(
    "music" to Color(0xFFC43B6B), "sport" to Color(0xFF2F63C4), "art" to Color(0xFF6D4AC9),
    "food" to Color(0xFFC43B6B), "games" to Color(0xFF0F7F73), "outdoors" to Color(0xFF0F7F73),
    "social" to Color(0xFFC96A1E), "comedy" to Color(0xFFC43B6B), "kids" to Color(0xFF2F63C4),
    "tours" to Color(0xFF3E7D3A), "conference" to Color(0xFF6D4AC9)
)

fun categoryColor(category: String): Color = CategoryHues[category] ?: Color(0xFF6B675E)

/**
 * Відтінок категорії для тексту й гліфів. У темній темі освітлюється до контрасту 4.5:1.
 * `categoryColor` лишається сирим відтінком для пінів і заливок.
 */
@Composable fun categoryInk(category: String): Color =
    if (Poruch.colors.dark) lerp(categoryColor(category), Color.White, 0.45f) else categoryColor(category)

@Composable fun categoryWash(category: String): Color =
    if (Poruch.colors.dark) categoryColor(category).copy(alpha = 0.22f)
    else CategoryWashes[category] ?: Color(0xFFEDEBE4)

/** Заливка обкладинки: пастель у світлій темі, тонка вуаль у темній. Два відтінки, щоб стіна обкладинок не зливалась. */
@Composable
fun categoryGradient(category: String): Brush {
    val hue = categoryColor(category)
    val partner = CategoryPartners[category] ?: hue
    return if (Poruch.colors.dark) Brush.linearGradient(
        listOf(hue.copy(alpha = 0.30f), partner.copy(alpha = 0.14f))
    ) else {
        val wash = CategoryWashes[category] ?: Color(0xFFEDEBE4)
        Brush.linearGradient(
            listOf(lerp(wash, Color.White, 0.55f), wash, lerp(wash, partner, 0.22f))
        )
    }
}

/** Заливка шапки: тепле світло вгорі, папір унизу. */
@Composable
fun heroGradient(): Brush = Poruch.colors.let { Brush.verticalGradient(listOf(it.heroTop, it.heroBottom)) }

/** Головна дія: заливка чорнилом зі світлою ниткою по верхньому краю. */
@Composable
fun brandGradient(): Brush = Poruch.colors.let {
    Brush.verticalGradient(listOf(lerp(it.brand, if (it.dark) Color.White else Color(0xFF4A463D), 0.22f), it.brand))
}

object Spacing {
    val xs = 4.dp; val sm = 8.dp; val md = 12.dp; val lg = 16.dp
    val xl = 20.dp; val xxl = 24.dp; val section = 32.dp; val page = 16.dp
}

object Radius {
    val xs = RoundedCornerShape(10.dp)
    val sm = RoundedCornerShape(14.dp)
    val md = RoundedCornerShape(16.dp)
    val lg = RoundedCornerShape(20.dp)
    val xl = RoundedCornerShape(26.dp)
    val sheet: Shape = RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp)
    val pill: Shape = CircleShape
}

/** Чотири рівні відстані від паперу: картка лежить, чип висить, таббар і карусель плавають. У темній темі тіні прозорі, глибину несе поверхня. */
object Elevation { val flat = 0.dp; val card = 4.dp; val raised = 10.dp; val overlay = 20.dp }

private val PoruchTypography = Typography(
    displaySmall = TextStyle(fontSize = 32.sp, lineHeight = 37.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.8).sp),
    headlineMedium = TextStyle(fontSize = 26.sp, lineHeight = 31.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.7).sp),
    headlineSmall = TextStyle(fontSize = 21.sp, lineHeight = 27.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.4).sp),
    titleLarge = TextStyle(fontSize = 19.sp, lineHeight = 25.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp),
    titleMedium = TextStyle(fontSize = 16.sp, lineHeight = 21.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.1).sp),
    // Назви карток читаються як капітель.
    titleSmall = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.4.sp),
    bodyLarge = TextStyle(fontSize = 15.sp, lineHeight = 22.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Normal),
    bodySmall = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
)

/**
 * Два стилі, яких нема в шкалі Material: `sectionTitle` — заголовок секції малими літерами,
 * `descriptor` — курсивна антиква під назвою, що відділяє «що це» від «як зветься».
 */
object PoruchType {
    val sectionTitle = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp)
    val descriptor = TextStyle(
        fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic,
        fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal
    )
    /** Та сама антиква прямо: лід на екрані деталей. */
    val lead = TextStyle(fontFamily = FontFamily.Serif, fontSize = 16.sp, lineHeight = 24.sp, fontWeight = FontWeight.Normal)
}

val LocalPoruchColors = staticCompositionLocalOf { LightPoruchColors }
val LocalReducedMotion = staticCompositionLocalOf { false }

object Poruch {
    val colors: PoruchColors
        @Composable @ReadOnlyComposable get() = LocalPoruchColors.current

    /** Система просить менше руху: екрани згасають замість ковзати. */
    val reducedMotion: Boolean
        @Composable @ReadOnlyComposable get() = LocalReducedMotion.current
}

@Composable
fun PoruchTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val palette = if (dark) DarkPoruchColors else LightPoruchColors
    // «Вимкнути анімації» в налаштуваннях доступності обнуляє масштаб аніматора.
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
