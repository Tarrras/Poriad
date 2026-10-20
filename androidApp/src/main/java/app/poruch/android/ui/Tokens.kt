package app.poruch.android.ui

import app.poruch.android.R
import app.poruch.domain.Event
import app.poruch.domain.EventCategory
import android.provider.Settings
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
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
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
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
    /** Шапка того ж тону, що й полотно: екран — один аркуш. */
    val heroTop: Color,
    val heroBottom: Color,
    /** Тінь є лише в того, що плаває: мʼяка, нейтральна. */
    val shadowAmbient: Color,
    val shadowSpot: Color,
    val hairline: Color,
    /** Корінець скасованої події — погашений сірий: білий друк на ньому тримає ≥ 5:1, а подія не блідне прозорістю. */
    val voidStub: Color,
    val onBrand: Color,
    val dark: Boolean
)

/**
 * Оболонка «Корінця» — одна нейтральна шкала з холодним відтінком: денне полотно й білі квитки, нічне графітове полотно
 * й трохи світліші квитки з волосиною по краю. Колір на екрані мають лише корінці квитків і стани. Головна дія — чорнило
 * вдень, папір уночі.
 */
val LightPoruchColors = PoruchColors(
    brand = Color(0xFF141417),
    brandPressed = Color(0xFF2E2E33),
    brandContainer = Color(0xFFE6E6EA),
    onBrandContainer = Color(0xFF141417),
    accent = Color(0xFFE0582F),
    accentText = Color(0xFFC2431F),
    accentContainer = Color(0xFFFDE7DF),
    onAccentContainer = Color(0xFF7A2E14),
    success = Color(0xFF2E7D4F),
    successContainer = Color(0xFFDFF3E6),
    onSuccessContainer = Color(0xFF1B4C2F),
    danger = Color(0xFFC0392B),
    dangerContainer = Color(0xFFFBE3E0),
    ink = Color(0xFF141417),
    inkSecondary = Color(0xFF5E5E66),
    inkTertiary = Color(0xFF6A6A73),
    surface = Color(0xFFFFFFFF),
    surfaceRaised = Color(0xFFFFFFFF),
    surfaceMuted = Color(0xFFEDEDF0),
    canvas = Color(0xFFF2F2F4),
    canvasTint = Color(0xFFE8E8EC),
    heroTop = Color(0xFFF2F2F4),
    heroBottom = Color(0xFFF2F2F4),
    shadowAmbient = Color(0x0F000000),
    shadowSpot = Color(0x1A000000),
    hairline = Color(0xFFE0E0E5),
    voidStub = Color(0xFF5E5E66),
    onBrand = Color(0xFFFFFFFF),
    dark = false
)

val DarkPoruchColors = PoruchColors(
    brand = Color(0xFFF3F3F0),
    brandPressed = Color(0xFFD6D6D2),
    brandContainer = Color(0xFF2A2930),
    onBrandContainer = Color(0xFFF3F3F0),
    accent = Color(0xFFFF8A5B),
    accentText = Color(0xFFFF8A5B),
    accentContainer = Color(0xFF3F2419),
    onAccentContainer = Color(0xFFFFD9C8),
    success = Color(0xFF5DC389),
    successContainer = Color(0xFF16311F),
    onSuccessContainer = Color(0xFFBFEBD0),
    danger = Color(0xFFFF6B5B),
    dangerContainer = Color(0xFF3C1A16),
    ink = Color(0xFFF3F3F0),
    inkSecondary = Color(0xFFA6A5AD),
    inkTertiary = Color(0xFF96959E),
    surface = Color(0xFF1C1B21),
    surfaceRaised = Color(0xFF26252C),
    surfaceMuted = Color(0xFF2A2930),
    canvas = Color(0xFF0F0F13),
    canvasTint = Color(0xFF16161B),
    heroTop = Color(0xFF0F0F13),
    heroBottom = Color(0xFF0F0F13),
    shadowAmbient = Color(0x4D000000),
    shadowSpot = Color(0x66000000),
    hairline = Color(0xFF2E2D35),
    voidStub = Color(0xFF4A4950),
    onBrand = Color(0xFF141417),
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
 * Заливка корінця квитка: відтінок категорії на 12 % ближче до чорного в обох темах. Сам відтінок у їжі, стендапу
 * й дитячого дає білому дрібному тексту лише 3,7–4,2:1, а день під часом набраний 11 sp.
 */
fun categoryStub(category: EventCategory): Color =
    palette(category).hue.let { Color(it.red * 0.88f, it.green * 0.88f, it.blue * 0.88f) }

/**
 * Відтінок категорії для тексту й гліфів. У темній темі освітлюється до контрасту 4.5:1.
 * `categoryColor` лишається сирим відтінком для пінів і заливок.
 */
@Composable
fun categoryInk(category: EventCategory): Color =
    // Удень — на 16 % темніший за сирий: той давав їжі, стендапу й дитячому на білому 3,8–4,2:1, а з 16 % найслабша
    // (їжа) тримає 4,55:1 навіть на полотні.
    if (Poruch.colors.dark) lerp(categoryColor(category), Color.White, 0.45f)
    else palette(category).hue.let { Color(it.red * 0.84f, it.green * 0.84f, it.blue * 0.84f) }

/** Корінець квитка: колір жанру, а в скасованої події — погашений сірий. */
@Composable
fun ticketStub(event: Event): Color = if (event.isCalledOff) Poruch.colors.voidStub else categoryStub(event.category)

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

/** Кути квитка: скруглені, але зібрані — предмет із картону, а не мʼяка подушка. */
object Corner {
    val xs = 10.dp
    val sm = 12.dp
    val md = 14.dp
    val lg = 18.dp
    val xl = 22.dp
}

object Radius {
    val xs = RoundedCornerShape(Corner.xs)
    val sm = RoundedCornerShape(Corner.sm)
    val md = RoundedCornerShape(Corner.md)
    val lg = RoundedCornerShape(Corner.lg)
    val xl = RoundedCornerShape(Corner.xl)
    /** Верх шторки — `xl`, як шторка мапи на iOS; 28 лишилось від «Спокійного аркуша». */
    val sheet: Shape = RoundedCornerShape(topStart = Corner.xl, topEnd = Corner.xl)
    val pill: Shape = CircleShape
}

/** Усе в потоці лежить пласко (`card` = 0, картку робить різниця тону з полотном); плаває лише таббар, карусель, банер. */
object Elevation {
    val flat = 0.dp;
    val card = 0.dp;
    val raised = 8.dp;
    val overlay = 24.dp
}

/** Інтерфейс — системний гротеск: ієрархію несуть кегль і вага. Заголовки й назви подій — [PoruchType.brandDisplay] і його брати. */
private val PoruchTypography = Typography(
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
    // Label 15/20, як у DESIGN.md і на iOS: 14/18 лишалось від старого світу.
    labelMedium = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(
        fontSize = 11.sp,
        lineHeight = 14.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 1.0.sp
    )
)

/**
 * Голос квитка — Sofia Sans Condensed (SIL OFL, статичні накреслення в `res/font/`): назви подій і заголовки екранів та
 * секцій. Цифри корінця — Sofia Sans Extra Condensed, табличні. Правило за змістом: назва події
 * ([app.poruch.domain.Event.displayTitle]), заголовок, час на корінці й штамп — так; місце, чипи, кнопки, підписи й службові
 * рядки — системний шрифт. Вужчий шрифт тримає довгі українські назви в двох рядках, тому кегль на щабель більший, ніж був
 * у засічок.
 */
private val SofiaCondensed = FontFamily(
    Font(R.font.sofia_sans_condensed_bold, FontWeight.Bold),
    Font(R.font.sofia_sans_condensed_extrabold, FontWeight.ExtraBold)
)
private val SofiaExtraCondensed = FontFamily(Font(R.font.sofia_sans_extra_condensed_extrabold, FontWeight.ExtraBold))

private fun condensed(size: TextUnit, lineHeight: TextUnit, tracking: TextUnit = 0.sp, heavy: Boolean = false) = TextStyle(
    fontFamily = SofiaCondensed, fontWeight = if (heavy) FontWeight.ExtraBold else FontWeight.Bold,
    fontSize = size, lineHeight = lineHeight, letterSpacing = tracking
)

private fun numeral(size: TextUnit, lineHeight: TextUnit) = TextStyle(
    fontFamily = SofiaExtraCondensed, fontWeight = FontWeight.ExtraBold, fontSize = size, lineHeight = lineHeight,
    fontFeatureSettings = "tnum"
)

/** Стилі поза шкалою Material: голос квитка, підпис категорії під назвою, лід деталей. */
object PoruchType {
    /** «Що поруч». */
    val brandDisplay = condensed(38.sp, 42.sp, (-0.5).sp, heavy = true)
    /** Назва великого квитка. */
    val brandTitle1 = condensed(30.sp, 33.sp, (-0.2).sp)
    /** Заголовок секції й назва плану. */
    val brandTitle2 = condensed(24.sp, 28.sp, (-0.1).sp)
    /** Назва події в квитку, постері й рядку. */
    val brandTitle3 = condensed(20.sp, 23.sp)
    /** Час на корінці: «19:30». */
    val numeral = numeral(34.sp, 36.sp)
    /** Час на малому корінці рядка. */
    val numeralSmall = numeral(24.sp, 26.sp)
    /** Штамп стану: «ВИ ЙДЕТЕ», «СКАСОВАНО». */
    val stamp = condensed(13.sp, 15.sp, 0.8.sp, heavy = true)

    val descriptor = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium)
    val lead = TextStyle(fontSize = 17.sp, lineHeight = 25.sp, fontWeight = FontWeight.Normal)

    // Сансові ролі з таблиці дизайн-системи (docs/design-system.md, «Типографіка») — ті самі стилі, що й
    // шкала Material вище, під іменами з документа, як `PoruchFont` на iOS. Екрани беруть роль, а не слот.
    /** Цифри й значення: лічильники, «12 як організатор». Не заголовки. */
    val title1 get() = PoruchTypography.headlineMedium
    val title2 get() = PoruchTypography.titleLarge
    /** Службові рядки й підписи: значення «Коли / Де», опції онбордингу. */
    val title3 get() = PoruchTypography.titleMedium
    val cardName get() = PoruchTypography.titleSmall
    /** Текст у формах і листах. */
    val body get() = PoruchTypography.bodyLarge
    /** Підзаголовок шапки. */
    val subhead get() = PoruchTypography.bodyMedium
    /** Адреса, метадані, час у чаті. */
    val caption get() = PoruchTypography.bodySmall
    /** Чипи. */
    val label get() = PoruchTypography.labelMedium
    val button get() = PoruchTypography.labelLarge
    /** Дата, бейджі, підписи полів: UPPERCASE з розрядкою. */
    val overline get() = PoruchTypography.labelSmall
}

val LocalPoruchColors = staticCompositionLocalOf { LightPoruchColors }
val LocalReducedMotion = staticCompositionLocalOf { false }

/**
 * Рух: один швидкий крок і одна пружина на весь застосунок (DS: ≤220 мс, easeInOut). При «зменшити рух»
 * крок стає миттєвим; екрани беруть токен, а не власну тривалість.
 */
object Motion {
    const val QUICK_MS = 200
    fun <T> quick(reducedMotion: Boolean): FiniteAnimationSpec<T> = if (reducedMotion) snap() else tween(QUICK_MS)
    fun <T> spring(): SpringSpec<T> = spring(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow)
}

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
