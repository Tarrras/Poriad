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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.TextStyle
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

/** Світла тема: прохолодний сірий фон і білі картки без рамок (Apple Store). Дії майже чорні. */
val LightPoruchColors = PoruchColors(
    brand = Color(0xFF1D1D1F), brandPressed = Color(0xFF3A3A3C), brandContainer = Color(0xFFE8E8ED), onBrandContainer = Color(0xFF1D1D1F),
    accent = Color(0xFFE0582F), accentContainer = Color(0xFFFDE7DF), onAccentContainer = Color(0xFF7A2E14),
    success = Color(0xFF2E7D4F), successContainer = Color(0xFFDFF3E6), onSuccessContainer = Color(0xFF1B4C2F),
    danger = Color(0xFFC0392B), dangerContainer = Color(0xFFFBE3E0),
    ink = Color(0xFF1D1D1F), inkSecondary = Color(0xFF6E6E73), inkTertiary = Color(0xFF6E6E78),
    surface = Color(0xFFFFFFFF), surfaceRaised = Color(0xFFFFFFFF), surfaceMuted = Color(0xFFF2F2F7),
    canvas = Color(0xFFF5F5F7), canvasTint = Color(0xFFEBEBF0),
    // Шапка того ж тону, що й полотно: екран — один спокійний аркуш.
    heroTop = Color(0xFFF5F5F7), heroBottom = Color(0xFFF5F5F7),
    // Тінь є лише в того, що плаває: мʼяка, нейтральна.
    shadowAmbient = Color(0x0F000000), shadowSpot = Color(0x1A000000),
    hairline = Color(0xFFE5E5EA), onBrand = Color(0xFFFFFFFF), dark = false
)

/** Темна тема: майже чорне полотно й трохи світліші картки з тонкою лінією по краю (Moonly). */
val DarkPoruchColors = PoruchColors(
    brand = Color(0xFFF5F5F7), brandPressed = Color(0xFFD1D1D6), brandContainer = Color(0xFF2C2C33), onBrandContainer = Color(0xFFF5F5F7),
    accent = Color(0xFFFF8A5B), accentContainer = Color(0xFF3F2419), onAccentContainer = Color(0xFFFFD9C8),
    success = Color(0xFF5DC389), successContainer = Color(0xFF16311F), onSuccessContainer = Color(0xFFBFEBD0),
    danger = Color(0xFFFF6B5B), dangerContainer = Color(0xFF3C1A16),
    ink = Color(0xFFF5F5F7), inkSecondary = Color(0xFFA1A1A8), inkTertiary = Color(0xFF8E8E96),
    surface = Color(0xFF17171C), surfaceRaised = Color(0xFF202027), surfaceMuted = Color(0xFF26262E),
    canvas = Color(0xFF0B0B0F), canvasTint = Color(0xFF141419),
    heroTop = Color(0xFF0B0B0F), heroBottom = Color(0xFF0B0B0F),
    shadowAmbient = Color(0x4D000000), shadowSpot = Color(0x66000000),
    hairline = Color(0xFF2A2A33), onBrand = Color(0xFF1D1D1F), dark = true
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

/** Головна дія: рівна заливка чорнилом. Лишилось [Brush], щоб місця виклику не змінювались. */
@Composable
fun brandGradient(): Brush = SolidColor(Poruch.colors.brand)

object Spacing {
    val xs = 4.dp; val sm = 8.dp; val md = 12.dp; val lg = 16.dp
    val xl = 20.dp; val xxl = 24.dp; val section = 32.dp; val page = 16.dp
}

object Radius {
    val xs = RoundedCornerShape(12.dp)
    val sm = RoundedCornerShape(14.dp)
    val md = RoundedCornerShape(18.dp)
    val lg = RoundedCornerShape(24.dp)
    val xl = RoundedCornerShape(28.dp)
    val sheet: Shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    val pill: Shape = CircleShape
}

/** Усе в потоці лежить пласко (`card` = 0, картку робить різниця тону з полотном); плаває лише таббар, карусель, банер. */
object Elevation { val flat = 0.dp; val card = 0.dp; val raised = 8.dp; val overlay = 24.dp }

/** Один голос — системний гротеск. Ієрархію несуть кегль і вага, а не гарнітура чи регістр. */
private val PoruchTypography = Typography(
    displaySmall = TextStyle(fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold, letterSpacing = (-1.0).sp),
    headlineMedium = TextStyle(fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.8).sp),
    headlineSmall = TextStyle(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    titleLarge = TextStyle(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    titleMedium = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.2).sp),
    // Назва картки звичайним регістром.
    titleSmall = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.2).sp),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Normal),
    bodySmall = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontSize = 16.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.0.sp)
)

/** Стилі поза шкалою Material: великий заголовок секції, підпис категорії під назвою, лід деталей. */
object PoruchType {
    val sectionTitle = TextStyle(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp)
    val descriptor = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium)
    val lead = TextStyle(fontSize = 17.sp, lineHeight = 25.sp, fontWeight = FontWeight.Normal)
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
