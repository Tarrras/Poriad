package app.poruch.android.feature.home

import android.Manifest
import android.annotation.SuppressLint
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import android.content.Context
import app.poruch.android.DIGEST_ASKED
import app.poruch.android.PROMPTS
import app.poruch.android.R
import app.poruch.android.platform.NotificationPermission
import app.poruch.android.ui.*
import app.poruch.domain.Event
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * Стос «Ваш тиждень» (docs/return-hooks.md, хвиля 2): «так/ні» по найближчих подіях «Для вас», «так» — закладка.
 * Наприкінці — «Нагадати мені» з системним питанням під зрозумілу обіцянку (Android 13+). Змах — лише прискорювач:
 * кнопки «Ні» й «Так» завжди є, а «вимкнути анімації» прибирає політ картки.
 */
@SuppressLint("InlinedApi") // POST_NOTIFICATIONS питаємо лише коли NotificationPermission.required (API 33+).
@Composable
fun DeckScreen(app: PoruchApp, cards: List<Event>, onDone: () -> Unit) {
    val colors = Poruch.colors
    val context = LocalContext.current
    val reducedMotion = LocalReducedMotion.current
    val scope = rememberCoroutineScope()
    var index by remember { mutableIntStateOf(0) }
    val kept = remember { mutableStateListOf<Event>() }
    val drag = remember { Animatable(0f) }
    // Картка ще летить: другий тап у цей час — подвійний тап, а не відповідь на наступну.
    var flying by remember { mutableStateOf(false) }
    val finished = index >= cards.size
    // Систему вже питали або дозволено (чи Android до 13, де питати нема про що): тоді наприкінці лише «Готово».
    val askable = remember { NotificationPermission(context).let { it.required && !it.granted() } }

    fun close(skipped: Boolean) {
        app.deckDone(kept.size, minOf(index + if (skipped) 1 else 0, cards.size), skipped)
        onDone()
    }

    fun answer(yes: Boolean) {
        if (flying || index >= cards.size) return
        val event = cards[index]
        app.deckAnswered(event.id, yes, index)
        if (yes) kept += event
        flying = true
        scope.launch {
            if (!reducedMotion) drag.animateTo(if (yes) 1400f else -1400f, tween(180))
            drag.snapTo(0f)
            index++
            flying = false
        }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        app.digestPromptAnswered(granted, "deck")
        close(skipped = false)
    }
    BackHandler { close(skipped = !finished) }

    Column(
        Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding()
            .padding(horizontal = Spacing.page, vertical = Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
    ) {
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
            if (!finished) Text(
                stringResource(R.string.deck_progress, index + 1, cards.size),
                style = MaterialTheme.typography.bodyMedium, color = colors.inkTertiary
            )
            Spacer(Modifier.weight(1f))
            if (!finished) Text(
                stringResource(R.string.onboarding_skip), style = MaterialTheme.typography.labelLarge, color = colors.inkSecondary,
                modifier = Modifier.pressable { close(skipped = true) }.heightIn(min = 44.dp).wrapContentHeight()
            )
        }
        if (!finished) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(stringResource(R.string.deck_title), style = PoruchType.brandTitle1, color = colors.ink)
                Text(stringResource(R.string.deck_subtitle), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            }
            Spacer(Modifier.weight(1f))
            key(cards[index].id) {
                EventHeroCard(
                    cards[index],
                    Modifier.fillMaxWidth()
                        .graphicsLayer { translationX = drag.value; rotationZ = if (reducedMotion) 0f else drag.value / 60f }
                        .pointerInput(index) {
                            detectHorizontalDragGestures(
                                onDragEnd = {
                                    if (abs(drag.value) > 280f) answer(drag.value > 0) else scope.launch { drag.animateTo(0f) }
                                },
                                onHorizontalDrag = { _, delta -> scope.launch { drag.snapTo(drag.value + delta) } }
                            )
                        },
                    height = 420.dp
                ) {}
            }
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SecondaryButton(stringResource(R.string.deck_no), { answer(false) }, Modifier.weight(1f))
                PrimaryButton(stringResource(R.string.deck_yes), { answer(true) }, Modifier.weight(1f), icon = PoruchIcons.bookmark)
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(
                    stringResource(if (kept.isEmpty()) R.string.deck_empty_title else R.string.deck_done_title),
                    style = PoruchType.brandTitle1, color = colors.ink
                )
                Text(
                    stringResource(if (kept.isEmpty()) R.string.deck_empty_body else R.string.deck_done_body),
                    style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary
                )
            }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                if (kept.isNotEmpty()) Column(Modifier.cardSurface(Radius.md)) {
                    kept.forEachIndexed { i, event ->
                        if (i > 0) HairLine()
                        Text(
                            event.displayTitle, style = MaterialTheme.typography.titleSmall, color = colors.ink,
                            maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(Spacing.lg)
                        )
                    }
                }
            }
            if (kept.isNotEmpty() && askable) {
                PrimaryButton(stringResource(R.string.deck_remind), {
                    context.getSharedPreferences(PROMPTS, Context.MODE_PRIVATE).edit().putBoolean(DIGEST_ASKED, true).apply()
                    permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                }, Modifier.fillMaxWidth(), icon = PoruchIcons.bell)
                Text(
                    stringResource(R.string.digest_prompt_no), style = MaterialTheme.typography.labelLarge, color = colors.inkSecondary,
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                        .pressable { app.digestPromptAnswered(false, "deck"); close(skipped = false) }
                        .heightIn(min = 44.dp).wrapContentHeight()
                )
            } else {
                PrimaryButton(stringResource(R.string.deck_finish), { close(skipped = false) }, Modifier.fillMaxWidth())
            }
        }
    }
}
