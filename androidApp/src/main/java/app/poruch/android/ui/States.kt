package app.poruch.android.ui

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
            modifier = Modifier
                .clip(Radius.pill)
                .clickable(onClick = onAction)
                .padding(horizontal = Spacing.sm, vertical = Spacing.xs)
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
    /** Lottie з генератора замість порожнього квитка (240×140): `R.raw.offline` — корінець на ниточці. */
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
        else BlankTicket(icon, Modifier.padding(bottom = Spacing.sm))
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

/** Порожній квиток над порожнім станом: ненадруковані рядки пунктиром і гліф на сірому корінці. Лише прикраса. */
@Composable
private fun BlankTicket(icon: ImageVector, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Ticket(
        colors.surfaceMuted,
        stub = { Icon(icon, null, Modifier.size(22.dp), tint = colors.inkSecondary) },
        modifier = modifier.width(184.dp).decorative(),
        stubLength = 56.dp, radius = Corner.sm, outline = colors.inkTertiary.copy(alpha = 0.6f)
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
