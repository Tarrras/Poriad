package app.poruch.android.feature.chat

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.Attendee
import app.poruch.domain.ChatMessage
import app.poruch.domain.ReportReason
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Чат події: повний екран зі своєю шапкою, стрічкою по днях і полем унизу.
 * Малює [ChatState], шле [ChatIntent]. Опитування веде спільний шар.
 */
@Composable
fun ChatScreen(state: ChatState, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding().imePadding()) {
        Header(state, onIntent)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when {
                !state.available -> EmptyState(
                    PoruchIcons.clock, stringResource(R.string.chat_unavailable_title), stringResource(R.string.chat_unavailable_hint)
                )
                state.loading && state.messages.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.ink)
                }
                else -> Feed(state, onIntent)
            }
        }
        if (state.readOnly) ClosedNote() else Composer(state, onIntent)
    }
    state.selected?.let { message -> MessageActions(state, message, onIntent) }
    state.deleting?.let { message ->
        PoruchConfirmSheet(
            title = stringResource(R.string.chat_delete_title),
            message = stringResource(R.string.chat_delete_body),
            confirmLabel = stringResource(R.string.chat_delete_confirm),
            dismissLabel = stringResource(R.string.chat_delete_keep),
            onConfirm = { onIntent(ChatIntent.Delete(message.id)) },
            onDismiss = { onIntent(ChatIntent.ConfirmDelete(null)) },
            tone = colors.danger
        )
    }
    state.reporting?.let { message -> ReportMessageSheet(message, onIntent) }
}

// ---- Шапка

@Composable
private fun Header(state: ChatState, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    val subtitle = if (state.members > 0) stringResource(
        R.string.chat_subtitle, pluralStringResource(R.plurals.chat_members, state.members, state.members)
    ) else stringResource(R.string.chat_subtitle_plain)
    Column {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.page, vertical = Spacing.sm),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Box(
                Modifier.size(40.dp).cardSurface(CircleShape, Elevation.card).pressable(onClick = { onIntent(ChatIntent.Back) }),
                contentAlignment = Alignment.Center
            ) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back), Modifier.size(18.dp), tint = colors.ink) }
            Column(Modifier.weight(1f)) {
                Text(
                    state.title.ifBlank { stringResource(R.string.chat_title) }, style = MaterialTheme.typography.titleMedium,
                    color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Box(Modifier.size(40.dp).background(colors.surfaceMuted, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Forum, null, Modifier.size(18.dp), tint = colors.inkSecondary)
            }
        }
        HorizontalDivider(color = colors.hairline)
    }
}

// ---- Стрічка

@Composable
private fun Feed(state: ChatState, onIntent: (ChatIntent) -> Unit) {
    val list = rememberLazyListState()
    val zone = remember { ZoneId.systemDefault() }
    // Список перевернутий: індекс 0 — найновіше внизу. Мітки дня й серії рахуємо від сусіда, що старіший.
    val rows = remember(state.messages) {
        val stamps = state.messages.map { parse(it.createdAt, zone) }
        state.messages.indices.reversed().map { i ->
            val previous = if (i > 0) stamps[i - 1] else null
            val current = stamps[i]
            FeedRow(
                message = state.messages[i],
                day = if (previous == null || current == null || previous.toLocalDate() != current.toLocalDate()) current?.toLocalDate() else null,
                continued = previous != null && current != null && state.messages[i - 1].authorId == state.messages[i].authorId &&
                    java.time.Duration.between(previous, current).toMinutes() < 5
            )
        }
    }
    // Нове внизу; при появі нового прокручуємо туди, якщо людина й так була внизу.
    LaunchedEffect(state.messages.size) {
        if (list.firstVisibleItemIndex <= 1) list.animateScrollToItem(0)
    }
    LazyColumn(
        state = list, reverseLayout = true, modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = Spacing.page, vertical = Spacing.md)
    ) {
        items(rows.size, key = { rows[it].message.id }) { index ->
            val row = rows[index]
            Column {
                row.day?.let { DayLabel(it) }
                Spacer(Modifier.height(if (row.continued) 3.dp else Spacing.md))
                Bubble(row.message, row.continued, state, onIntent)
            }
        }
        item(key = "rules") {
            Column {
                Rules()
                if (state.messages.isEmpty()) EmptyState(
                    PoruchIcons.social, stringResource(R.string.chat_empty_title), stringResource(R.string.chat_empty_hint),
                    Modifier.padding(top = Spacing.section)
                )
            }
        }
    }
}

private class FeedRow(val message: ChatMessage, val day: LocalDate?, val continued: Boolean)

/** Правило платформи, один раз угорі стрічки: сторонній чужий текст, а не наш. */
@Composable
private fun Rules() {
    val colors = Poruch.colors
    Row(Modifier.padding(vertical = Spacing.md), horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.Top) {
        Icon(Icons.Outlined.PanTool, null, Modifier.size(14.dp).padding(top = 1.dp), tint = colors.inkTertiary)
        Text(stringResource(R.string.chat_disclaimer), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
    }
}

@Composable
private fun DayLabel(day: LocalDate) {
    val colors = Poruch.colors
    val today = remember { LocalDate.now() }
    val label = when (day) {
        today -> stringResource(R.string.chat_today)
        today.minusDays(1) -> stringResource(R.string.chat_yesterday)
        else -> remember(day) { day.format(dayFormat) }
    }
    Box(Modifier.fillMaxWidth().padding(top = Spacing.lg), contentAlignment = Alignment.Center) {
        Text(
            label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkSecondary,
            modifier = Modifier.background(colors.surfaceMuted, CircleShape).padding(horizontal = Spacing.md, vertical = 5.dp)
        )
    }
}

@Composable
private fun Bubble(message: ChatMessage, continued: Boolean, state: ChatState, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    val mine = state.isMine(message)
    val name = message.authorName.ifBlank { stringResource(R.string.chat_member) }
    val time = remember(message.createdAt) { clock(message.createdAt) }
    val shape = bubbleShape(mine, continued)
    val who = if (mine) stringResource(R.string.chat_you) else name
    Row(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = "$who, $time: ${message.body}" },
        horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start, verticalAlignment = Alignment.Bottom
    ) {
        if (mine) Spacer(Modifier.width(56.dp))
        else {
            if (continued) Spacer(Modifier.size(28.dp))
            else AvatarStack(listOf(Attendee(message.authorId, name, message.avatarUrl)), total = 1, size = 28.dp)
            Spacer(Modifier.width(Spacing.sm))
        }
        Column(
            Modifier.weight(1f, fill = false).widthIn(max = 300.dp).clip(shape)
                .background(if (mine) colors.brand else colors.surface)
                .then(if (mine) Modifier else Modifier.border(1.dp, colors.hairline, shape))
                .combinedClickable(onClick = {}, onLongClick = { onIntent(ChatIntent.Select(message)) })
                .padding(horizontal = Spacing.md, vertical = Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            if (!mine && !continued) Text(name, style = MaterialTheme.typography.labelMedium, color = colors.inkSecondary)
            Text(message.body, style = MaterialTheme.typography.bodyLarge, color = if (mine) colors.onBrand else colors.ink)
            // Час у правому нижньому куті, як у месенджерах.
            Text(
                time, style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.sp, lineHeight = 14.sp),
                color = if (mine) colors.onBrand.copy(alpha = 0.65f) else colors.inkTertiary,
                modifier = Modifier.align(Alignment.End)
            )
        }
        if (!mine) Spacer(Modifier.width(56.dp))
    }
}

/** Бульбашка з «хвостиком»: кут біля співрозмовника гострий, у продовженні серії — усі округлі. */
private fun bubbleShape(mine: Boolean, continued: Boolean): RoundedCornerShape {
    val big = 18.dp; val small = if (continued) 18.dp else 5.dp
    return RoundedCornerShape(topStart = big, topEnd = big, bottomStart = if (mine) big else small, bottomEnd = if (mine) small else big)
}

// ---- Низ

@Composable
private fun ClosedNote() {
    val colors = Poruch.colors
    Column {
        HorizontalDivider(color = colors.hairline)
        Row(
            Modifier.fillMaxWidth().background(colors.surface).padding(Spacing.lg).navigationBarsPadding(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Outlined.Lock, null, Modifier.size(16.dp), tint = colors.inkSecondary)
            Text(stringResource(R.string.chat_read_only), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
        }
    }
}

@Composable
private fun Composer(state: ChatState, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    val canSend = state.draft.isNotBlank() && !state.sending
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val border by animateColorAsState(if (focused) colors.ink.copy(alpha = 0.35f) else colors.hairline, label = "border")
    val sendTint by animateColorAsState(if (canSend) colors.brand else colors.inkTertiary, label = "send")
    Column {
        HorizontalDivider(color = colors.hairline)
        Row(
            Modifier.fillMaxWidth().background(colors.surface).padding(horizontal = Spacing.page, vertical = Spacing.sm).navigationBarsPadding(),
            verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            BasicTextField(
                state.draft, { onIntent(ChatIntent.EditDraft(it)) },
                Modifier.weight(1f).clip(RoundedCornerShape(22.dp)).background(colors.canvas).border(1.dp, border, RoundedCornerShape(22.dp))
                    .padding(horizontal = Spacing.lg, vertical = 11.dp),
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.ink), cursorBrush = SolidColor(colors.ink),
                maxLines = 5, interactionSource = interaction,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, keyboardType = KeyboardType.Text, imeAction = ImeAction.Default),
                decorationBox = { field ->
                    Box(contentAlignment = Alignment.CenterStart) {
                        if (state.draft.isEmpty()) Text(
                            stringResource(R.string.chat_placeholder), style = MaterialTheme.typography.bodyLarge, color = colors.inkTertiary
                        )
                        field()
                    }
                }
            )
            Box(
                Modifier.size(44.dp).background(sendTint, CircleShape).pressable(enabled = canSend, onClick = { onIntent(ChatIntent.Send) }),
                contentAlignment = Alignment.Center
            ) {
                if (state.sending) CircularProgressIndicator(Modifier.size(18.dp), color = colors.onBrand, strokeWidth = 2.dp)
                else Icon(Icons.Outlined.ArrowUpward, stringResource(R.string.chat_send), Modifier.size(20.dp), tint = colors.onBrand)
            }
        }
    }
}

// ---- Меню й скарга

/** Довгий тап: скопіювати, поскаржитись на чуже, видалити своє (або будь-яке — організатору). */
@Composable
private fun MessageActions(state: ChatState, message: ChatMessage, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    PoruchSheet({ onIntent(ChatIntent.Select(null)) }) { sheet ->
        Column(Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(
                message.body, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary, maxLines = 3, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(bottom = Spacing.md)
            )
            ActionRow(Icons.Outlined.ContentCopy, stringResource(R.string.chat_copy)) { sheet.close { onIntent(ChatIntent.Copy(message)) } }
            if (!state.isMine(message)) ActionRow(Icons.Outlined.Flag, stringResource(R.string.chat_report)) {
                sheet.close { onIntent(ChatIntent.ShowReport(message)) }
            }
            if (state.canDelete(message)) ActionRow(Icons.Outlined.DeleteOutline, stringResource(R.string.chat_delete), tone = colors.danger) {
                sheet.close { onIntent(ChatIntent.ConfirmDelete(message)) }
            }
        }
    }
}

@Composable
private fun ActionRow(icon: ImageVector, label: String, tone: androidx.compose.ui.graphics.Color? = null, onClick: () -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().clip(Radius.sm).pressable(onClick = onClick).padding(horizontal = Spacing.sm, vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Icon(icon, null, Modifier.size(20.dp), tint = tone ?: colors.ink)
        Text(label, style = MaterialTheme.typography.bodyLarge, color = tone ?: colors.ink)
    }
}

@Composable
private fun ReportMessageSheet(message: ChatMessage, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    var reason by remember { mutableStateOf(ReportReason.HARASSMENT) }
    var details by remember { mutableStateOf("") }
    PoruchSheet({ onIntent(ChatIntent.ShowReport(null)) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(stringResource(R.string.chat_report_title), style = MaterialTheme.typography.titleLarge, color = colors.ink)
            Text(stringResource(R.string.report_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                reportReasons.forEach { (value, label) ->
                    Row(
                        Modifier.fillMaxWidth().clip(Radius.sm).selectable(reason == value, role = Role.RadioButton) { reason = value }
                            .padding(vertical = Spacing.md, horizontal = Spacing.sm),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                    ) {
                        Box(
                            Modifier.size(20.dp).background(if (reason == value) colors.brand else colors.surfaceMuted, CircleShape),
                            contentAlignment = Alignment.Center
                        ) { if (reason == value) Icon(Icons.Outlined.Check, null, Modifier.size(12.dp), tint = colors.onBrand) }
                        Text(stringResource(label), style = MaterialTheme.typography.bodyLarge, color = colors.ink)
                    }
                }
            }
            LabelledField(stringResource(R.string.report_details), details, { details = it }, singleLine = false, minLines = 3)
            PrimaryButton(
                stringResource(R.string.report_send), { sheet.close { onIntent(ChatIntent.SendReport(message, reason, details)) } },
                Modifier.fillMaxWidth()
            )
        }
    }
}

// ---- Час

private val clockFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")
private val dayFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMMM", Locale("uk"))

private fun parse(iso: String, zone: ZoneId): ZonedDateTime? = runCatching { Instant.parse(iso).atZone(zone) }.getOrNull()

/** Час повідомлення в поясі пристрою: чат читають тут і зараз. */
private fun clock(iso: String): String = parse(iso, ZoneId.systemDefault())?.format(clockFormat) ?: ""
