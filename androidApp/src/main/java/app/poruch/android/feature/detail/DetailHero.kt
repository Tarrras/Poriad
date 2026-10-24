package app.poruch.android.feature.detail

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.platform.LocalConfiguration
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
import app.poruch.domain.ArtistRole
import app.poruch.domain.ContactRules
import app.poruch.domain.Event
import app.poruch.domain.Inviter
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
    val room = state.screen.room
    Box(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(heroHeight())) {
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
            ScrimButton(PoruchIcons.arrowLeft, stringResource(R.string.back)) { onIntent(DetailIntent.Back) }
            Spacer(Modifier.weight(1f))
            ScrimButton(
                if (state.screen.saved) PoruchIcons.bookmarkFilled else PoruchIcons.bookmark,
                stringResource(if (state.screen.saved) R.string.unsave else R.string.save)
            ) { onIntent(DetailIntent.ToggleSaved) }
        }
        Column(
            Modifier.align(Alignment.BottomStart).padding(horizontal = Spacing.page).padding(bottom = HERO_OVERLAP + Spacing.xl)
                // Текст їде зі стрічкою, а смуга статусу з'являється лише з аркушем: назва гасне, поки не дійшла до годинника.
                .graphicsLayer {
                    // Читання в шарі, а не в композиції: прокрутка не перескладає обкладинку.
                    val faded = 1f - (scroll.value - HERO_TEXT_FADE_FROM.toPx()) / HERO_TEXT_FADE.toPx()
                    // Скасування каже штамп над назвою; приглушена до 70 % біла назва на затемненні втрачала контраст.
                    alpha = faded.coerceIn(0f, 1f)
                },
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            // Стан квитка — штампом над назвою, лише коли з ним щось сталось (як на квитках стрічки). Жанр і джерело
            // афіші — тихим рядком під назвою: пігулки були окремою мовою міток, а жанр ще й надрукований на корінці панелі.
            val stamp: Triple<String, BadgeTone, ImageVector?>? = when {
                state.screen.cancelled -> Triple(stringResource(R.string.cancelled_short), BadgeTone.Danger, null)
                state.screen.listing != null -> listingStamp(state.screen.listing!!)?.let { Triple(it.first, it.second, null) }
                state.screen.organizer -> Triple(stringResource(R.string.you_organize), BadgeTone.Neutral, null)
                // Після кінця лишається лише факт участі: черга й місця вже нічого не значать.
                state.screen.ended -> if (room?.joined == true) Triple(stringResource(R.string.went), BadgeTone.Neutral, PoruchIcons.check) else null
                room?.joined == true -> Triple(stringResource(R.string.going), BadgeTone.Success, PoruchIcons.check)
                state.screen.waitlisted -> Triple(stringResource(R.string.in_queue), BadgeTone.Accent, PoruchIcons.queue)
                room?.awaitingApproval == true -> Triple(stringResource(R.string.request_pending), BadgeTone.Accent, PoruchIcons.clock)
                room?.isScarce == true -> Triple(stringResource(R.string.seats_left, room.seatsLeft), BadgeTone.Accent, null)
                else -> null
            }
            state.screen.inviter?.let { InviterLine(it) }
            stamp?.let { (text, tone, icon) -> TicketStamp(text, tone, icon, onFill = true) }
            // «Стендап · Афіша · Badseller»: афіша завжди підписана джерелом — атрибуція обов'язкова.
            val meta = listOfNotNull(
                stringResource(categoryLabel(event.category)).takeIf { it.isNotBlank() },
                state.screen.listing?.let {
                    stringResource(R.string.listing_badge, it.sellerNames)
                }
            ).joinToString(" · ")
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                // Дата й час — на корінці квитка внизу екрана, тож над назвою їх не повторюємо.
                Text(event.displayTitle, style = PoruchType.brandDisplay, color = Color.White)
                Text(
                    meta, style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.8f),
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

/**
 * «Тарас кличе тебе» (docs/invites.md): подію відкрили з посилання-запрошення. Над усім іншим на обкладинці — це
 * відповідь на «чому я тут», як рядок причини на квитках стрічки, лише голосом друга.
 */
@Composable
private fun InviterLine(inviter: Inviter) {
    Row(
        Modifier.semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
    ) {
        // Аватар росте разом із підписом, до 1,5×.
        val avatar = 28.dp * LocalDensity.current.fontScale.coerceIn(1f, 1.5f)
        Avatar(inviter.name, inviter.avatarUrl, avatar, Modifier.border(1.5.dp, Color.White.copy(alpha = 0.85f), CircleShape))
        Text(stringResource(R.string.invite_from, inviter.name), style = MaterialTheme.typography.labelLarge, color = Color.White, maxLines = 2)
    }
}

/** Висота обкладинки й скільки її низу ховається під аркушем секцій. */
/** Висота обкладинки: 480 dp, але не більше 60 % вікна — у ландшафті вона інакше була вища за екран. */
@Composable
internal fun heroHeight(): Dp = minOf(480.dp, (LocalConfiguration.current.screenHeightDp * 0.6f).dp)
internal val HERO_OVERLAP = 28.dp
/** Звідки й за скільки гасне текст на обкладинці при прокрутці. */
internal val HERO_TEXT_FADE_FROM = 100.dp
internal val HERO_TEXT_FADE = 140.dp
/** За скільки проявляється смуга під статусом, поки аркуш під'їжджає до неї. */
internal val SCRIM_FADE = 40.dp
