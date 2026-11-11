package app.poruch.android.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import app.poruch.domain.EventCategory
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import androidx.annotation.RawRes
import com.airbnb.lottie.compose.LottieAnimation
import com.airbnb.lottie.compose.LottieCompositionSpec
import com.airbnb.lottie.compose.LottieConstants
import com.airbnb.lottie.compose.rememberLottieComposition

/**
 * Потяг стрічки вниз. Вміст має вміти прокручуватись, інакше жест нікуди не дійде.
 * [underStatusBar] — вміст заходить під смугу статусу (хедер із градієнтом, обкладинка): тоді
 * індикатор відступає від неї, інакше коло висіло б на годиннику.
 */
@Composable
fun PullToRefresh(
    refreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    underStatusBar: Boolean = false,
    content: @Composable BoxScope.() -> Unit
) {
    val colors = Poruch.colors
    val state = rememberPullToRefreshState()
    PullToRefreshBox(
        isRefreshing = refreshing, onRefresh = onRefresh, modifier = modifier, state = state,
        indicator = {
            PullToRefreshDefaults.Indicator(
                state = state, isRefreshing = refreshing,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .then(if (underStatusBar) Modifier.statusBarsPadding() else Modifier),
                containerColor = colors.surface, color = colors.ink
            )
        },
        content = content
    )
}

/** Заголовок секції: як написано в ресурсі, читабельного розміру. Капітель лишається там, де несе дані: дати, бейджі, підписи полів. */
@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            title,
            style = PoruchType.brandTitle2,
            color = colors.ink,
            // Заголовок і для TalkBack: перехід заголовками, як `.isHeader` на iOS.
            modifier = Modifier.weight(1f).semantics { heading() }
        )
        if (actionLabel != null && onAction != null) Text(
            actionLabel, style = MaterialTheme.typography.labelMedium, color = colors.ink,
            // «Усі 6», «Додати» — ключові переходи: ціль 48 dp, текст по центру, як у GhostButton.
            modifier = Modifier
                .clip(Radius.pill)
                .clickable(onClick = onAction)
                .heightIn(min = 48.dp)
                .padding(horizontal = Spacing.sm)
                .wrapContentHeight(Alignment.CenterVertically)
        )
    }
}

@Composable
fun PageHeader(
    title: String,
    modifier: Modifier = Modifier,
    back: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.page, vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        if (back != null) Box(
            Modifier
                .minimumInteractiveComponentSize()
                .size(40.dp)
                .cardSurface(CircleShape, Elevation.card)
                .pressable(onClick = back),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                PoruchIcons.arrowLeft,
                stringResource(R.string.back),
                Modifier.size(18.dp),
                tint = colors.ink
            )
        }
        Text(
            title,
            style = PoruchType.brandTitle1,
            color = colors.ink,
            modifier = Modifier.weight(1f)
        )
        trailing?.invoke()
    }
}

/** Фірмова Lottie-анімація в циклі; темний варіант лежить у raw-night. Малюнки — tools/generate_lottie.py. */
@Composable
fun BrandAnimation(@RawRes res: Int, modifier: Modifier = Modifier, still: Boolean = false) {
    val composition by rememberLottieComposition(LottieCompositionSpec.RawRes(res))
    // [still] — стоп-кадр першого кадру: «зменшити рух».
    LottieAnimation(composition, modifier, isPlaying = !still, iterations = LottieConstants.IterateForever)
}

/** Лоадер екрана чи секції: шпилька з іконки підстрибує. Кнопки й дрібні підвантаження лишаються з системним. */
@Composable
fun PoruchLoader(modifier: Modifier = Modifier) {
    if (Poruch.reducedMotion) CircularProgressIndicator(modifier, color = Poruch.colors.ink)
    else BrandAnimation(R.raw.loader, modifier.size(56.dp))
}

@Composable
fun EmptyState(
    icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier,
    actionLabel: String? = null, onAction: (() -> Unit)? = null,
    /** Lottie з генератора замість порожнього квитка (240×140). Зараз — лише `R.raw.offline`, див. [OfflineState]. */
    @RawRes animation: Int? = null
) {
    val colors = Poruch.colors
    Column(
        modifier
            .fillMaxWidth()
            .padding(Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        if (animation != null) BrandAnimation(animation, Modifier.size(240.dp, 140.dp).clearAndSetSemantics {}, still = Poruch.reducedMotion)
        else TicketFan(icon, Modifier.padding(bottom = Spacing.sm))
        // Довгі рядки переносяться: по центру, як і значок над ними.
        Text(
            title,
            style = PoruchType.brandTitle2,
            color = colors.ink,
            textAlign = TextAlign.Center
        )
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = colors.inkSecondary,
            textAlign = TextAlign.Center
        )
        if (actionLabel != null && onAction != null) PrimaryButton(
            actionLabel,
            onAction,
            Modifier.padding(top = Spacing.sm)
        )
    }
}

/**
 * «Немає звʼязку»: порожній стан без мережі — корінець порожнього квитка на ниточці (Lottie `offline`). Заголовок і
 * анімація свої, екран дає лише підказку «Покажемо …, щойно повернеться мережа.» і, де є що зробити, дію. Екран
 * відкривається сам, щойно мережа повернеться (`PoruchApp.networkChanged`). Збій сервера — банер, а не це.
 */
@Composable
fun OfflineState(message: String, modifier: Modifier = Modifier, actionLabel: String? = null, onAction: (() -> Unit)? = null) =
    EmptyState(PoruchIcons.wifiOff, stringResource(R.string.offline_title), message, modifier, actionLabel, onAction, animation = R.raw.offline)

/** «Без мережі · показуємо збережене»: над тим, що показано з телефону. Гліф «нема мережі» — штампова фарба (DESIGN.md). */
@Composable
fun OfflineNote(modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Row(modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Icon(PoruchIcons.wifiOff, null, Modifier.size(15.dp), tint = colors.accent)
        Text(stringResource(R.string.offline_cached), style = PoruchType.caption, color = colors.inkSecondary)
    }
}

/** Без [subtitle] банер тонкий: гліф, один рядок і стрілка. */
@Composable
fun BannerCard(
    title: String,
    subtitle: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector = PoruchIcons.sparkle
) {
    val colors = Poruch.colors
    val slim = subtitle == null
    Row(
        modifier
            .fillMaxWidth()
            .pressable(onClick = onClick)
            .cardSurface()
            .padding(horizontal = Spacing.lg, vertical = if (slim) Spacing.md else Spacing.lg),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier
                .size(if (slim) 36.dp else 44.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, Modifier.size(20.dp), tint = colors.ink) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = colors.ink)
            subtitle?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary
                )
            }
        }
        Box(
            Modifier
                .size(if (slim) 28.dp else 32.dp)
                .background(colors.brand, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                PoruchIcons.arrowRight,
                null,
                Modifier.size(16.dp),
                tint = colors.onBrand
            )
        }
    }
}

/**
 * Порожній стан — віяло з трьох квитків із корінцями різних жанрів замість сірого пунктирного контуру (10.11, «Папір»):
 * тут будуть ваші квитки. Передній несе гліф екрана на корінці, задні — лише колір. Віяло розкривається раз пружиною;
 * з вимкненими анімаціями стоїть розкрите. Квитки лежать один на одному, тож мають тінь. Лише прикраса.
 */
@Composable
fun TicketFan(
    icon: ImageVector, modifier: Modifier = Modifier,
    /** Задній, середній і передній квиток. Шапка профілю гостя бере жанри зустрічей від людей. */
    genres: Triple<EventCategory, EventCategory, EventCategory> = Triple(EventCategory.FOOD, EventCategory.SPORT, EventCategory.MUSIC)
) {
    val colors = Poruch.colors
    val reducedMotion = Poruch.reducedMotion
    var open by remember { mutableStateOf(reducedMotion) }
    LaunchedEffect(Unit) { open = true }
    val spread by animateFloatAsState(
        if (open) 1f else 0f,
        if (reducedMotion) snap() else spring(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow),
        label = "fan"
    )
    @Composable
    fun ticket(category: EventCategory, turn: Float, x: Dp, y: Dp, glyph: ImageVector? = null) {
        Ticket(
            categoryStub(category),
            stub = { if (glyph != null) Icon(glyph, null, Modifier.size(22.dp), tint = Color.White) },
            modifier = Modifier
                .graphicsLayer {
                    rotationZ = turn * spread
                    translationX = x.toPx() * spread
                    translationY = y.toPx() * spread
                }
                .width(184.dp),
            stubLength = 56.dp, radius = Corner.sm, elevation = Elevation.raised
        ) {
            Column(
                Modifier.heightIn(min = 72.dp).padding(horizontal = Spacing.md),
                verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically)
            ) {
                Box(Modifier.size(72.dp, 6.dp).background(colors.hairline, Radius.pill))
                Box(Modifier.size(44.dp, 6.dp).background(colors.hairline, Radius.pill))
            }
        }
    }
    Box(modifier.padding(top = 32.dp, bottom = 12.dp).decorative(), contentAlignment = Alignment.Center) {
        ticket(genres.first, -11f, 8.dp, (-26).dp)
        ticket(genres.second, 7f, 34.dp, (-4).dp)
        ticket(genres.third, -2f, (-14).dp, 14.dp, icon)
    }
}

/** Банер під статус-баром, а не над таббаром. Тон несе зміст: червоний для помилки, зелений для успіху. */
@Composable
fun NoticeBanner(
    text: String,
    error: Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = Poruch.colors
    val wash = if (error) colors.dangerContainer else colors.successContainer
    val mark = if (error) colors.danger else colors.success
    Row(
        modifier
            .fillMaxWidth()
            .pressable(onClick = onDismiss)
            .cardSurface(Radius.md, Elevation.overlay)
            .padding(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier
                .size(36.dp)
                .background(wash, Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (error) PoruchIcons.alert else PoruchIcons.checkCircle, null,
                Modifier.size(20.dp), tint = mark
            )
        }
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = colors.ink,
            modifier = Modifier.weight(1f)
        )
        Icon(
            PoruchIcons.close,
            stringResource(R.string.close),
            Modifier.size(18.dp),
            tint = colors.inkTertiary
        )
    }
}
