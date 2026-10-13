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

// Листи деталей: скарга, оцінка, «Шукаю компанію». Розрізано з DetailScreen.kt.

/** Скарга: іменована причина для сортування черги модерації плюс необов'язковий текст. */
@Composable
internal fun ReportSheet(target: ReportTarget, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    var reason by remember { mutableStateOf(ReportReason.MINORS) }
    var details by remember { mutableStateOf("") }
    PoruchSheet({ onIntent(DetailIntent.ShowReport(null)) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(
                stringResource(
                    when (target) {
                        ReportTarget.EVENT -> R.string.report_event_title
                        ReportTarget.ORGANIZER -> R.string.report_user_title
                        ReportTarget.PERSON -> R.string.report_person_title
                    }
                ),
                style = PoruchType.serifTitle2, color = colors.ink
            )
            Text(stringResource(R.string.report_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                reportReasons.forEach { (value, label) ->
                    Row(
                        Modifier.fillMaxWidth().clip(Radius.sm)
                            .selectable(reason == value, role = Role.RadioButton) { reason = value }
                            .padding(vertical = Spacing.md, horizontal = Spacing.sm),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                    ) {
                        Box(
                            Modifier.size(20.dp).background(if (reason == value) colors.brand else colors.surfaceMuted, CircleShape),
                            contentAlignment = Alignment.Center
                        ) { if (reason == value) Icon(PoruchIcons.check, null, Modifier.size(12.dp), tint = colors.onBrand) }
                        Text(stringResource(label), style = MaterialTheme.typography.bodyLarge, color = colors.ink)
                    }
                }
            }
            LabelledField(
                stringResource(R.string.report_details), details, { details = it },
                singleLine = false, minLines = 3
            )
            PrimaryButton(
                stringResource(R.string.report_send),
                { sheet.close { onIntent(DetailIntent.SendReport(target, reason, details)) } },
                Modifier.fillMaxWidth()
            )
        }
    }
}

/**
 * «Як пройшло?»: бал 1–5, що сподобалось, кілька слів організатору. Повторна відправка замінює
 * попередню. Спільна для деталей і «Моїх подій».
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun RatingSheet(
    event: Event, mine: EventRating?, mutating: Boolean,
    /** Початковий стан перемикача «Стежити за організатором»; null — перемикача нема. */
    followOrganizer: Boolean?,
    onDismiss: () -> Unit,
    onSend: (score: Int, comment: String, tags: List<RatingTag>, follow: Boolean?) -> Unit
) {
    val colors = Poruch.colors
    var score by remember(mine) { mutableStateOf(mine?.score ?: 0) }
    var tags by remember(mine) { mutableStateOf(mine?.tags.orEmpty().toSet()) }
    var comment by remember(mine) { mutableStateOf(mine?.comment.orEmpty()) }
    var follow by remember(mine, followOrganizer) { mutableStateOf(followOrganizer ?: false) }
    val offered = remember(event.category) { RatingRules.tagsFor(event.category) }
    PoruchSheet(onDismiss) { sheet ->
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.page).padding(bottom = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                EventImage(event, Modifier.size(52.dp).clip(Radius.xs))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(cardOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
                    Text(event.displayTitle, style = PoruchType.serifTitle3, color = colors.ink, maxLines = 2)
                }
            }
            Text(stringResource(R.string.rate_title), style = PoruchType.serifTitle2, color = colors.ink)
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Row(Modifier.selectableGroup(), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    (1..5).forEach { value ->
                        val picked = value == score
                        val label = stringResource(R.string.rate_star, value)
                        Box(
                            Modifier.weight(1f).height(56.dp)
                                .background(if (picked) brandGradient() else SolidColor(LocalFieldSurface.current ?: colors.surface), Radius.sm)
                                .clip(Radius.sm)
                                .selectable(picked, role = Role.RadioButton) { score = value }
                                .semantics { contentDescription = label },
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                value.toString(), style = MaterialTheme.typography.titleMedium,
                                color = if (picked) colors.onBrand else colors.ink
                            )
                        }
                    }
                }
                Row {
                    Text(stringResource(R.string.rate_low), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
                    Text(stringResource(R.string.rate_high), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(stringResource(R.string.rate_liked).uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    offered.forEach { tag ->
                        PoruchChip(stringResource(tag.label), tag in tags, { tags = if (tag in tags) tags - tag else tags + tag })
                    }
                }
            }
            LabelledField(
                stringResource(R.string.rate_comment), comment, { comment = it.take(RatingRules.COMMENT_MAX) },
                placeholder = stringResource(R.string.rate_optional), singleLine = false, minLines = 3
            )
            if (followOrganizer != null) Row(
                Modifier.fillMaxWidth().cardSurface(Radius.md).padding(horizontal = Spacing.lg, vertical = Spacing.md),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(stringResource(R.string.rate_follow_title), style = MaterialTheme.typography.titleSmall, color = colors.ink)
                    Text(stringResource(R.string.rate_follow_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                }
                PoruchSwitch(follow, { follow = it })
            }
        }
        HairLine()
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.lg, bottom = Spacing.md).navigationBarsPadding().imePadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            PrimaryButton(
                stringResource(if (mine == null) R.string.rate_send else R.string.rate_update),
                // Порядок шторки, не порядок тапів: так і на сервері, і в тестах.
                { sheet.close { onSend(score, comment, offered.filter { it in tags }, follow.takeIf { followOrganizer != null }) } },
                Modifier.fillMaxWidth(), enabled = score > 0 && !mutating, loading = mutating
            )
            GhostButton(stringResource(R.string.rate_skip), { sheet.close() }, tone = colors.inkSecondary)
        }
    }
}

internal val RatingTag.label: Int
    get() = when (this) {
        RatingTag.ATMOSPHERE -> R.string.rate_tag_atmosphere
        RatingTag.ORGANIZATION -> R.string.rate_tag_organization
        RatingTag.PLACE -> R.string.rate_tag_place
        RatingTag.PEOPLE -> R.string.rate_tag_people
        RatingTag.ON_TIME -> R.string.rate_tag_on_time
        RatingTag.MUSIC -> R.string.rate_tag_music
        RatingTag.SOUND -> R.string.rate_tag_sound
        RatingTag.HUMOR -> R.string.rate_tag_humor
        RatingTag.HOST -> R.string.rate_tag_host
        RatingTag.PROGRAM -> R.string.rate_tag_program
        RatingTag.COACH -> R.string.rate_tag_coach
        RatingTag.WORKOUT -> R.string.rate_tag_workout
        RatingTag.ROUTE -> R.string.rate_tag_route
        RatingTag.VIEWS -> R.string.rate_tag_views
        RatingTag.PACE -> R.string.rate_tag_pace
        RatingTag.GUIDE -> R.string.rate_tag_guide
        RatingTag.STORIES -> R.string.rate_tag_stories
        RatingTag.FOOD -> R.string.rate_tag_food
        RatingTag.DRINKS -> R.string.rate_tag_drinks
        RatingTag.GAME_CHOICE -> R.string.rate_tag_game_choice
        RatingTag.RULES -> R.string.rate_tag_rules
        RatingTag.CONVERSATION -> R.string.rate_tag_conversation
        RatingTag.KIDS_LIKED -> R.string.rate_tag_kids_liked
        RatingTag.SAFETY -> R.string.rate_tag_safety
        RatingTag.SPEAKERS -> R.string.rate_tag_speakers
        RatingTag.USEFUL -> R.string.rate_tag_useful
        RatingTag.NETWORKING -> R.string.rate_tag_networking
    }

/**
 * Коротка шторка замість повного редактора: лише час зустрічі, де зустрітись і скільки людей.
 * Назву, місце й кінець сервер бере з афіші.
 */
@Composable
internal fun CompanionSheet(event: Event, mutating: Boolean, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val times = remember(event.startsAt) { CompanionRules.meetTimes(event.startsAt, kotlin.time.Clock.System.now()) }
    var at by remember(times) {
        mutableStateOf(times.indexOf(CompanionRules.defaultMeetAt(event.startsAt, kotlin.time.Clock.System.now())).coerceAtLeast(0))
    }
    var note by remember { mutableStateOf("") }
    var capacity by remember { mutableStateOf(CompanionRules.DEFAULT_CAPACITY) }
    val words = dateWords()
    PoruchSheet({ onIntent(DetailIntent.SeekCompany(false)) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Text(stringResource(R.string.companion_seek), style = PoruchType.serifTitle2, color = colors.ink)
            Text(event.displayTitle, style = PoruchType.serifTitle3, color = colors.inkSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(stringResource(R.string.companion_sheet_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            val meetAt = times.getOrNull(at)
            if (meetAt != null) {
                val lead = (times.size - 1 - at) * CompanionRules.STEP_MINUTES
                Stepper(
                    stringResource(R.string.companion_meet_time),
                    sessionLabel(EventSession(event.id, meetAt, event.timeZone), words).second,
                    if (lead == 0) stringResource(R.string.companion_at_start) else stringResource(R.string.companion_lead, durationWords(lead)),
                    stringResource(R.string.companion_earlier) to { at-- }, at > 0,
                    stringResource(R.string.companion_later) to { at++ }, at < times.lastIndex
                )
            }
            LabelledField(
                stringResource(R.string.companion_meet_note), note, { note = it.take(CompanionRules.NOTE_MAX) },
                placeholder = stringResource(R.string.companion_meet_note_hint)
            )
            Stepper(
                stringResource(R.string.companion_capacity), capacity.toString(), null,
                stringResource(R.string.companion_fewer) to { capacity-- }, capacity > CompanionRules.MIN_CAPACITY,
                stringResource(R.string.companion_more) to { capacity++ }, capacity < CompanionRules.MAX_CAPACITY
            )
            PrimaryButton(
                stringResource(R.string.companion_create),
                { if (meetAt != null) sheet.close { onIntent(DetailIntent.CreateCompanion(meetAt, note, capacity)) } },
                Modifier.fillMaxWidth(), enabled = meetAt != null && !mutating, loading = mutating, icon = PoruchIcons.share
            )
        }
    }
}

/** Значення з кнопками «−» і «+». Підписи кнопок — для TalkBack. */
@Composable
internal fun Stepper(
    label: String, value: String, caption: String?,
    minus: Pair<String, () -> Unit>, minusEnabled: Boolean,
    plus: Pair<String, () -> Unit>, plusEnabled: Boolean
) {
    val colors = Poruch.colors
    Row(
        // Тло поля, а не картки: у шторці картка біла на білому.
        Modifier.fillMaxWidth().background(LocalFieldSurface.current ?: colors.surface, Radius.md)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(value, style = MaterialTheme.typography.titleLarge, color = colors.ink)
            caption?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary) }
        }
        StepButton(PoruchIcons.minus, minus.first, minusEnabled, minus.second)
        StepButton(PoruchIcons.plus, plus.first, plusEnabled, plus.second)
    }
}

@Composable
internal fun StepButton(icon: ImageVector, description: String, enabled: Boolean, onClick: () -> Unit) {
    val colors = Poruch.colors
    Box(
        Modifier.minimumInteractiveComponentSize().size(40.dp).clip(CircleShape).background(colors.surface)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(icon, description, Modifier.size(20.dp), tint = if (enabled) colors.ink else colors.inkTertiary) }
}
