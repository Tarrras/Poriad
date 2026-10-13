package app.poruch.android.feature.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.android.feature.mine.countdownOverline
import app.poruch.domain.ArtistRole
import app.poruch.domain.ContactRules
import app.poruch.domain.Event
import app.poruch.domain.EventIndexEntry
import app.poruch.domain.TitleRules
import app.poruch.domain.FollowRules
import app.poruch.domain.CompanionRules
import app.poruch.domain.Membership
import app.poruch.domain.EventSession
import app.poruch.domain.asIndexEntry
import app.poruch.domain.Gathering
import app.poruch.domain.EventRating
import app.poruch.domain.RatingRules
import app.poruch.domain.RatingTag
import app.poruch.domain.ReportReason
import app.poruch.domain.ShelterKind

// Обкладинка деталей і її геометрія. Розрізано з DetailScreen.kt.

/**
 * Обкладинка на весь верх екрана — та сама афіша, що й велика картка головної ([EventArt]): без фото
 * насичений градієнт категорії, а не бліда пастель. Назва й стан лежать на затемненні внизу: одна сцена,
 * а не фото з підписом. Низ на [HERO_OVERLAP] ховається під аркушем секцій.
 */
@Composable
internal fun Hero(event: Event, state: DetailState, scroll: ScrollState, onIntent: (DetailIntent) -> Unit) {
    val room = state.room
    // Відлік лише для сьогоднішнього, як на картці плану головної.
    val words = dateWords()
    val today = remember(event) {
        event.startInstant?.let {
            java.time.Instant.ofEpochMilli(it.toEpochMilliseconds()).atZone(java.time.ZoneId.systemDefault()).toLocalDate() == java.time.LocalDate.now()
        } == true
    }
    val overline = if (today) countdownOverline(event) else remember(event) { cardOverline(event, words) }
    Box(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(HERO_HEIGHT)) {
            EventArt(event, Modifier.fillMaxSize(), glyph = 260.dp, glyphDrop = 120.dp)
            // Обкладинка довільна, тож тонка тінь зверху тримає смугу статусу читабельною.
            Box(
                Modifier.fillMaxWidth().align(Alignment.TopCenter)
                    .windowInsetsTopHeight(WindowInsets.statusBars.add(WindowInsets(top = Spacing.lg)))
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.32f), Color.Transparent)))
            )
            Box(Modifier.matchParentSize().background(PhotoScrim))
        }
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
            ScrimButton(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back)) { onIntent(DetailIntent.Back) }
            Spacer(Modifier.weight(1f))
            ScrimButton(
                if (state.saved) PoruchIcons.bookmarkFilled else PoruchIcons.bookmark,
                stringResource(if (state.saved) R.string.unsave else R.string.save)
            ) { onIntent(DetailIntent.ToggleSaved) }
        }
        Column(
            Modifier.align(Alignment.BottomStart).padding(horizontal = Spacing.page).padding(bottom = HERO_OVERLAP + Spacing.xl)
                // Текст їде зі стрічкою, а смуга статусу з'являється лише з аркушем: назва гасне, поки не дійшла до годинника.
                .graphicsLayer {
                    // Читання в шарі, а не в композиції: прокрутка не перескладає обкладинку.
                    val faded = 1f - (scroll.value - HERO_TEXT_FADE_FROM.toPx()) / HERO_TEXT_FADE.toPx()
                    alpha = faded.coerceIn(0f, 1f) * if (state.cancelled) 0.7f else 1f
                },
            verticalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                StatusBadge(stringResource(categoryLabel(event.category)), BadgeTone.Brand)
                when {
                    state.cancelled -> StatusBadge(stringResource(R.string.cancelled), BadgeTone.Danger)
                    // Афіша завжди підписана джерелом: атрибуція обов'язкова.
                    state.listing?.isWithdrawn == true -> StatusBadge(stringResource(R.string.listing_withdrawn), BadgeTone.Neutral)
                    state.listing != null -> StatusBadge(stringResource(R.string.listing_badge, state.listing!!.sourceName), BadgeTone.Neutral)
                    state.organizer -> StatusBadge(stringResource(R.string.you_organize), BadgeTone.Neutral, PoruchIcons.sparkle)
                    // Після кінця лишається лише факт участі: черга й місця вже нічого не значать.
                    state.ended -> if (room?.joined == true) StatusBadge(stringResource(R.string.went), BadgeTone.Neutral, PoruchIcons.check)
                    room?.joined == true -> StatusBadge(stringResource(R.string.going), BadgeTone.Success, PoruchIcons.check)
                    state.waitlisted -> StatusBadge(stringResource(R.string.in_queue), BadgeTone.Accent, PoruchIcons.queue)
                    room?.awaitingApproval == true -> StatusBadge(stringResource(R.string.request_pending), BadgeTone.Accent, PoruchIcons.clock)
                    room?.isScarce == true && !state.cancelled ->
                        StatusBadge(stringResource(R.string.seats_left, room.seatsLeft), BadgeTone.Accent)
                }
            }
            Text(overline, style = MaterialTheme.typography.labelSmall, color = Poruch.colors.accentOnPhoto, maxLines = 2)
            Text(event.displayTitle, style = PoruchType.serifDisplay, color = Color.White)
        }
    }
}

/** Висота обкладинки й скільки її низу ховається під аркушем секцій. */
internal val HERO_HEIGHT = 480.dp
internal val HERO_OVERLAP = 28.dp
/** Звідки й за скільки гасне текст на обкладинці при прокрутці. */
internal val HERO_TEXT_FADE_FROM = 100.dp
internal val HERO_TEXT_FADE = 140.dp
/** За скільки проявляється смуга під статусом, поки аркуш під'їжджає до неї. */
internal val SCRIM_FADE = 40.dp
