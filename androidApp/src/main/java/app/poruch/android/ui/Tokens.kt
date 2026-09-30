package app.poruch.android.ui

import app.poruch.android.R
import app.poruch.domain.EventCategory
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
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Токени дизайну. Джерело правди — docs/design-system.md; екрани беруть кольори, відступи й радіуси звідси. */
@Immutable
data class PoruchColors(
    val brand: Color,
    val brandPressed: Color,
    val brandContainer: Color,
    val onBrandContainer: Color,
    val accent: Color,
    /** `accent` як колір дрібного тексту на білому: сам `accent` там дає 3,75:1, цей — 5,1:1. Заливкам і крапкам лишається `accent`. */
    val accentText: Color,
    val accentContainer: Color,
    val onAccentContainer: Color,
    val success: Color,
    val successContainer: Color,
    val onSuccessContainer: Color,
    val danger: Color,
    val dangerContainer: Color,
    val ink: Color,
    val inkSecondary: Color,
    val inkTertiary: Color,
    val surface: Color,
    val surfaceRaised: Color,
    val surfaceMuted: Color,
    val canvas: Color,
    val canvasTint: Color,
    /** Сяйво за шапкою головної: холодний відтінок, що на висоті екрана тане в полотно. */
    val glow: Color,
    /** Тепла заливка вгорі шапки, згасає в `canvas`. */
    val heroTop: Color,
    val heroBottom: Color,
    /** Тіні коричнево-чорні, не нейтральні: сіра тінь на теплому папері виглядає як бруд. */
    val shadowAmbient: Color,
    val shadowSpot: Color,
    val hairline: Color,
    val onBrand: Color,
    val dark: Boolean
)

/** Світла тема: прохолодний сірий фон і білі картки без рамок (Apple Store). Дії майже чорні. */
val LightPoruchColors = PoruchColors(
    brand = Color(0xFF1D1D1F),
    brandPressed = Color(0xFF3A3A3C),
    brandContainer = Color(0xFFE8E8ED),
    onBrandContainer = Color(0xFF1D1D1F),
    accent = Color(0xFFE0582F),
    accentText = Color(0xFFC2431F),
    accentContainer = Color(0xFFFDE7DF),
    onAccentContainer = Color(0xFF7A2E14),
    success = Color(0xFF2E7D4F),
    successContainer = Color(0xFFDFF3E6),
    onSuccessContainer = Color(0xFF1B4C2F),
    danger = Color(0xFFC0392B),
    dangerContainer = Color(0xFFFBE3E0),
    ink = Color(0xFF1D1D1F),
    inkSecondary = Color(0xFF6E6E73),
    inkTertiary = Color(0xFF6E6E78),
    surface = Color(0xFFFFFFFF),
    surfaceRaised = Color(0xFFFFFFFF),
    surfaceMuted = Color(0xFFF2F2F7),
    canvas = Color(0xFFF5F5F7),
    canvasTint = Color(0xFFEBEBF0),
    glow = Color(0xFFE4E1F6),
    // Шапка того ж тону, що й полотно: екран — один спокійний аркуш.
    heroTop = Color(0xFFF5F5F7),
    heroBottom = Color(0xFFF5F5F7),
    // Тінь є лише в того, що плаває: мʼяка, нейтральна.
    shadowAmbient = Color(0x0F000000),
    shadowSpot = Color(0x1A000000),
    hairline = Color(0xFFE5E5EA),
    onBrand = Color(0xFFFFFFFF),
    dark = false
)

/** Темна тема: майже чорне полотно й трохи світліші картки з тонкою лінією по краю (Moonly). */
val DarkPoruchColors = PoruchColors(
    brand = Color(0xFFF5F5F7),
    brandPressed = Color(0xFFD1D1D6),
    brandContainer = Color(0xFF2C2C33),
    onBrandContainer = Color(0xFFF5F5F7),
    accent = Color(0xFFFF8A5B),
    accentText = Color(0xFFFF8A5B),
    accentContainer = Color(0xFF3F2419),
    onAccentContainer = Color(0xFFFFD9C8),
    success = Color(0xFF5DC389),
    successContainer = Color(0xFF16311F),
    onSuccessContainer = Color(0xFFBFEBD0),
    danger = Color(0xFFFF6B5B),
    dangerContainer = Color(0xFF3C1A16),
    ink = Color(0xFFF5F5F7),
    inkSecondary = Color(0xFFA1A1A8),
    inkTertiary = Color(0xFF8E8E96),
    surface = Color(0xFF17171C),
    surfaceRaised = Color(0xFF202027),
    surfaceMuted = Color(0xFF26262E),
    canvas = Color(0xFF0B0B0F),
    canvasTint = Color(0xFF141419),
    glow = Color(0xFF1B1A36),
    heroTop = Color(0xFF0B0B0F),
    heroBottom = Color(0xFF0B0B0F),
    shadowAmbient = Color(0x4D000000),
    shadowSpot = Color(0x66000000),
    hairline = Color(0xFF2A2A33),
    onBrand = Color(0xFF1D1D1F),
    dark = true
)

/**
 * Палітра категорії: [hue] — глибокий відтінок для гліфів і тексту, [wash] — пастель плиток і пінів,
 * [partner] — другий відтінок пари для градієнта обкладинки.
 */
private class CategoryPalette(val hue: Color, val wash: Color, val partner: Color)

private fun palette(category: EventCategory) = when (category) {
    EventCategory.MUSIC -> CategoryPalette(Color(0xFF6D4AC9), Color(0xFFEBE4FB), Color(0xFFC43B6B))
    EventCategory.SPORT -> CategoryPalette(Color(0xFF0F7F73), Color(0xFFDDF0EC), Color(0xFF2F63C4))
    EventCategory.ART -> CategoryPalette(Color(0xFFC43B6B), Color(0xFFFBE1EA), Color(0xFF6D4AC9))
    EventCategory.FOOD -> CategoryPalette(Color(0xFFC96A1E), Color(0xFFFBEBD9), Color(0xFFC43B6B))
    EventCategory.GAMES -> CategoryPalette(Color(0xFF2F63C4), Color(0xFFE1EAFB), Color(0xFF0F7F73))
    EventCategory.OUTDOORS -> CategoryPalette(Color(0xFF3E7D3A), Color(0xFFE4F1E2), Color(0xFF0F7F73))
    EventCategory.SOCIAL -> CategoryPalette(Color(0xFFB8562F), Color(0xFFFAE5DA), Color(0xFFC96A1E))
    // Палітру будували на сім категорій. Золото й бірюза підібрані вручну за контрастом,
    // варті погляду дизайнера.
    EventCategory.COMEDY -> CategoryPalette(Color(0xFFA07813), Color(0xFFF7ECD2), Color(0xFFC43B6B))
    EventCategory.KIDS -> CategoryPalette(Color(0xFF1F8A8A), Color(0xFFD9EFEF), Color(0xFF2F63C4))
    // Олива й пурпур — середини найбільших вільних проміжків на колі відтінків, контраст у нормі.
    EventCategory.TOURS -> CategoryPalette(Color(0xFF5F7F1F), Color(0xFFECF0E4), Color(0xFF3E7D3A))
    EventCategory.CONFERENCE -> CategoryPalette(Color(0xFF933FA8), Color(0xFFF2E8F5), Color(0xFF6D4AC9))
    EventCategory.UNKNOWN -> CategoryPalette(Color(0xFF6B675E), Color(0xFFEDEBE4), Color(0xFF6B675E))
}

fun categoryColor(category: EventCategory): Color = palette(category).hue

/**
 * Відтінок категорії для тексту й гліфів. У темній темі освітлюється до контрасту 4.5:1.
 * `categoryColor` лишається сирим відтінком для пінів і заливок.
 */
@Composable
fun categoryInk(category: EventCategory): Color =
    if (Poruch.colors.dark) lerp(categoryColor(category), Color.White, 0.45f) else categoryColor(category)

@Composable
fun categoryWash(category: EventCategory): Color =
    if (Poruch.colors.dark) categoryColor(category).copy(alpha = 0.22f) else palette(category).wash

/** Заливка обкладинки: пастель у світлій темі, тонка вуаль у темній. Два відтінки, щоб стіна обкладинок не зливалась. */
@Composable
fun categoryGradient(category: EventCategory): Brush {
    val p = palette(category)
    return if (Poruch.colors.dark) Brush.linearGradient(
        listOf(p.hue.copy(alpha = 0.30f), p.partner.copy(alpha = 0.14f))
    ) else Brush.linearGradient(
        listOf(lerp(p.wash, Color.White, 0.55f), p.wash, lerp(p.wash, p.partner, 0.22f))
    )
}

/** Заливка великої картки без фото: глибокий відтінок категорії веде до сусіднього, текст поверх білий. */
fun categoryHeroGradient(category: EventCategory): Brush {
    val p = palette(category)
    return Brush.linearGradient(listOf(p.hue, p.partner))
}

/** Заливка шапки: тепле світло вгорі, папір унизу. */
@Composable
fun heroGradient(): Brush =
    Poruch.colors.let { Brush.verticalGradient(listOf(it.heroTop, it.heroBottom)) }

/** Головна дія: рівна заливка чорнилом. Лишилось [Brush], щоб місця виклику не змінювались. */
@Composable
fun brandGradient(): Brush = SolidColor(Poruch.colors.brand)

object Spacing {
    val xs = 4.dp;
    val sm = 8.dp;
    val md = 12.dp;
    val lg = 16.dp
    val xl = 20.dp;
    val xxl = 24.dp;
    val section = 32.dp;
    val page = 16.dp
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
object Elevation {
    val flat = 0.dp;
    val card = 0.dp;
    val raised = 8.dp;
    val overlay = 24.dp
}

/** Один голос — системний гротеск. Ієрархію несуть кегль і вага, а не гарнітура чи регістр. */
private val PoruchTypography = Typography(
    displaySmall = TextStyle(
        fontSize = 34.sp,
        lineHeight = 40.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = (-1.0).sp
    ),
    headlineMedium = TextStyle(
        fontSize = 28.sp,
        lineHeight = 34.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = (-0.8).sp
    ),
    headlineSmall = TextStyle(
        fontSize = 22.sp,
        lineHeight = 28.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = (-0.5).sp
    ),
    titleLarge = TextStyle(
        fontSize = 22.sp,
        lineHeight = 28.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = (-0.5).sp
    ),
    titleMedium = TextStyle(
        fontSize = 17.sp,
        lineHeight = 22.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = (-0.2).sp
    ),
    // Назва картки звичайним регістром.
    titleSmall = TextStyle(
        fontSize = 17.sp,
        lineHeight = 22.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = (-0.2).sp
    ),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Normal),
    bodySmall = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontSize = 16.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(
        fontSize = 11.sp,
        lineHeight = 14.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 1.0.sp
    )
)

/**
 * Заголовки з засічками: Source Serif 4 (змінний шрифт, SIL OFL, `res/font/source_serif4.ttf`), вага 600. Лише від 22 sp:
 * дрібніше лишається системний шрифт. Оптичний розмір шрифту — кегль стилю (`opticalSizing`): 34 sp — «Display», 22 sp — «Subhead».
 * Поки що лише головна, решта екранів — після огляду.
 */
@OptIn(ExperimentalTextApi::class)
private fun serifStyle(size: TextUnit, lineHeight: TextUnit, tracking: TextUnit) = TextStyle(
    fontFamily = FontFamily(
        Font(
            R.font.source_serif4, FontWeight.SemiBold,
            variationSettings = FontVariation.Settings(FontVariation.weight(600), FontVariation.opticalSizing(size))
        )
    ),
    fontWeight = FontWeight.SemiBold, fontSize = size, lineHeight = lineHeight, letterSpacing = tracking
)

/** Стилі поза шкалою Material: великий заголовок секції, підпис категорії під назвою, лід деталей, заголовки з засічками. */
object PoruchType {
    /** «Що поруч». */
    val serifDisplay = serifStyle(34.sp, 40.sp, (-0.5).sp)
    /** Назва великої картки. */
    val serifTitle1 = serifStyle(28.sp, 34.sp, (-0.4).sp)
    /** Заголовок секції й назва плану. */
    val serifTitle2 = serifStyle(22.sp, 28.sp, (-0.2).sp)

    val sectionTitle = TextStyle(
        fontSize = 22.sp,
        lineHeight = 28.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = (-0.5).sp
    )
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
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f
        ) == 0f
    }
    val scheme = if (dark) darkColorScheme(
        primary = palette.brand,
        onPrimary = palette.onBrand,
        primaryContainer = palette.brandContainer,
        onPrimaryContainer = palette.onBrandContainer,
        secondaryContainer = palette.brandContainer,
        onSecondaryContainer = palette.onBrandContainer,
        background = palette.canvas,
        onBackground = palette.ink,
        surface = palette.surface,
        onSurface = palette.ink,
        surfaceVariant = palette.surfaceMuted,
        onSurfaceVariant = palette.inkSecondary,
        outline = palette.hairline,
        outlineVariant = palette.hairline,
        error = palette.danger,
        errorContainer = palette.dangerContainer
    ) else lightColorScheme(
        primary = palette.brand,
        onPrimary = palette.onBrand,
        primaryContainer = palette.brandContainer,
        onPrimaryContainer = palette.onBrandContainer,
        secondaryContainer = palette.brandContainer,
        onSecondaryContainer = palette.onBrandContainer,
        background = palette.canvas,
        onBackground = palette.ink,
        surface = palette.surface,
        onSurface = palette.ink,
        surfaceVariant = palette.surfaceMuted,
        onSurfaceVariant = palette.inkSecondary,
        outline = palette.hairline,
        outlineVariant = palette.hairline,
        error = palette.danger,
        errorContainer = palette.dangerContainer
    )
    CompositionLocalProvider(
        LocalPoruchColors provides palette,
        LocalReducedMotion provides reducedMotion
    ) {
        MaterialTheme(
            colorScheme = scheme,
            typography = PoruchTypography,
            shapes = Shapes(
                extraSmall = Radius.xs,
                small = Radius.sm,
                medium = Radius.md,
                large = Radius.lg,
                extraLarge = Radius.xl
            ),
            content = content
        )
    }
}
