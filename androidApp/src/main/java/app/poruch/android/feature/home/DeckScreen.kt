package app.poruch.android.feature.home

import android.Manifest
import android.annotation.SuppressLint
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
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
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
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
import kotlinx.coroutines.delay
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
    // Штамп «ЗБЕРЕЖЕНО» на квитку: 0 — нема, 1 — поставлено. Пружина дає штампу «удар» з легким відскоком.
    val stamp = remember { Animatable(0f) }
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
            if (yes) {
                if (reducedMotion) stamp.snapTo(1f) else stamp.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = 900f))
                delay(if (reducedMotion) 350 else 200)
            }
            if (!reducedMotion) drag.animateTo(if (yes) 1400f else -1400f, tween(180))
            drag.snapTo(0f)
            stamp.snapTo(0f)
            index++
            flying = false
        }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        app.digestPromptAnswered(granted, "deck")
        close(skipped = false)
    }
    BackHandler { close(skipped = !finished) }

    // На широкому вікні — колонка по центру, як решта екранів (ContentColumn): квиток на всю ширину планшета розтягувався.
    Box(Modifier.fillMaxSize().background(colors.canvas), contentAlignment = Alignment.TopCenter) { Column(
        Modifier.widthIn(max = ContentMaxWidth).fillMaxSize().systemBarsPadding()
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
            // Квиток по центру вільної висоти, а коли не вміщається (великий шрифт, альбомна) — прокрутка над кнопками:
            // без неї Column віддавав «Так» і «Ні» лише залишок висоти, тобто нуль.
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                val fill = maxHeight
                Column(
                    Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = fill),
                    verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        Text(stringResource(R.string.deck_title), style = PoruchType.brandTitle1, color = colors.ink)
                        Text(stringResource(R.string.deck_subtitle), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                    }
                    Spacer(Modifier.weight(1f))
                    // Квиток і під ним — що це за подія: людина має розуміти, що їй пропонують, а не вгадувати з назви.
                    key(cards[index].id) {
                        Column(
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
                            verticalArrangement = Arrangement.spacedBy(Spacing.md)
                        ) {
                            // Тут квиток — не кнопка: TalkBack читає його текстом, а відповідь — «Так» і «Ні».
                            val label = ticketA11yLabel(cards[index])
                            Box {
                                EventHeroCard(
                                    cards[index], Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = label },
                                    height = 300.dp, showSource = false
                                ) {}
                                // «Так» штампує квиток, як касир, — стан мовою «Корінця»; посередині обкладинки, а не корінця.
                                if (stamp.value > 0f) TicketStamp(
                                    stringResource(R.string.deck_saved), BadgeTone.Success, PoruchIcons.bookmarkFilled,
                                    onFill = cards[index].imageUrl != null,
                                    modifier = Modifier.align(Alignment.TopCenter).padding(top = 64.dp).offset(x = (-42).dp)
                                        .graphicsLayer {
                                            val scale = 2.4f - 0.9f * stamp.value
                                            scaleX = scale; scaleY = scale; alpha = stamp.value.coerceIn(0f, 1f)
                                        }
                                )
                            }
                            About(cards[index])
                        }
                    }
                    Spacer(Modifier.weight(1f))
                }
            }
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
                fun asked() = context.getSharedPreferences(PROMPTS, Context.MODE_PRIVATE).edit().putBoolean(DIGEST_ASKED, true).apply()
                PrimaryButton(stringResource(R.string.deck_remind), {
                    asked()
                    permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                }, Modifier.fillMaxWidth(), icon = PoruchIcons.bell)
                // «Не зараз» — теж відповідь: без позначки наступний запуск питав про дайджест удруге.
                Text(
                    stringResource(R.string.digest_prompt_no), style = MaterialTheme.typography.labelLarge, color = colors.inkSecondary,
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                        .pressable { asked(); app.digestPromptAnswered(false, "deck"); close(skipped = false) }
                        .heightIn(min = 44.dp).wrapContentHeight()
                )
            } else {
                PrimaryButton(stringResource(R.string.deck_finish), { close(skipped = false) }, Modifier.fillMaxWidth())
            }
        }
    } }
}

/** Що це за подія: речення «що це», уривок опису й ціна — щоб «так» було рішенням, а не вгадуванням з назви. */
@Composable
private fun About(event: Event) {
    val colors = Poruch.colors
    val about = event.about
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        about.line?.let {
            Text(it, style = MaterialTheme.typography.titleSmall, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        about.excerpt?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary, maxLines = 4, overflow = TextOverflow.Ellipsis)
        }
        event.listing?.takeIf { it.isFree == true || it.priceMin != null }?.let {
            Text(listingPrice(it), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        }
    }
}
