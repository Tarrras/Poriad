package app.poruch.android.feature.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.Attendee
import app.poruch.domain.ChatMessage
import app.poruch.domain.ReportReason
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Чат події: список знизу вгору, поле внизу. Малює [ChatState], шле [ChatIntent]. */
@Composable
fun ChatScreen(state: ChatState, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding().imePadding()) {
        PageHeader(state.title.ifBlank { stringResource(R.string.chat_title) }, back = { onIntent(ChatIntent.Back) })
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when {
                !state.available -> EmptyState(
                    PoruchIcons.clock, stringResource(R.string.chat_unavailable_title), stringResource(R.string.chat_unavailable_hint)
                )
                state.loading && state.messages.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.ink)
                }
                state.messages.isEmpty() -> EmptyState(
                    PoruchIcons.social, stringResource(R.string.chat_empty_title), stringResource(R.string.chat_empty_hint)
                )
                else -> Messages(state, onIntent)
            }
        }
        // Правило платформи: сторонній чужий текст, а не наш. Лишається на екрані, а не в онбордингу.
        Text(
            stringResource(R.string.chat_disclaimer), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary,
            modifier = Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.xs)
        )
        if (state.readOnly) Text(
            stringResource(R.string.chat_read_only), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary,
            modifier = Modifier.fillMaxWidth().padding(Spacing.page).navigationBarsPadding()
        ) else Composer(state, onIntent)
    }
    state.selected?.let { message -> MessageActions(state, message, onIntent) }
    state.reporting?.let { message -> ReportMessageSheet(message, onIntent) }
}

@Composable
private fun Messages(state: ChatState, onIntent: (ChatIntent) -> Unit) {
    val list = rememberLazyListState()
    // Нове внизу; при появі нового прокручуємо туди, якщо людина й так була внизу.
    val reversed = remember(state.messages) { state.messages.asReversed() }
    LaunchedEffect(state.messages.size) {
        if (list.firstVisibleItemIndex <= 1) list.animateScrollToItem(0)
    }
    LazyColumn(
        state = list, reverseLayout = true, modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = Spacing.page, vertical = Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        items(reversed, key = { it.id }) { message -> Bubble(message, state, onIntent) }
    }
}

@Composable
private fun Bubble(message: ChatMessage, state: ChatState, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    val mine = state.isMine(message)
    val time = remember(message.createdAt) { messageTime(message.createdAt) }
    Row(
        Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start,
        verticalAlignment = Alignment.Bottom
    ) {
        if (!mine) AvatarStack(listOf(Attendee(message.authorId, message.authorName, message.avatarUrl)), total = 1, size = 28.dp)
        if (!mine) Spacer(Modifier.width(Spacing.sm))
        Column(
            Modifier.widthIn(max = 300.dp).clip(Radius.md)
                .background(if (mine) colors.ink else colors.surface)
                .combinedClickable(onClick = {}, onLongClick = { onIntent(ChatIntent.Select(message)) })
                .padding(horizontal = Spacing.md, vertical = Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            if (!mine) Text(
                message.authorName.ifBlank { stringResource(R.string.chat_member) },
                style = MaterialTheme.typography.labelMedium, color = colors.inkSecondary
            )
            Text(message.body, style = MaterialTheme.typography.bodyLarge, color = if (mine) colors.canvas else colors.ink)
            Text(time, style = MaterialTheme.typography.labelSmall, color = if (mine) colors.canvas.copy(alpha = 0.7f) else colors.inkTertiary)
        }
    }
}

@Composable
private fun Composer(state: ChatState, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    val canSend = state.draft.isNotBlank() && !state.sending
    Row(
        Modifier.fillMaxWidth().background(colors.surface).padding(horizontal = Spacing.page, vertical = Spacing.sm).navigationBarsPadding(),
        verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        OutlinedTextField(
            state.draft, { onIntent(ChatIntent.EditDraft(it)) }, Modifier.weight(1f),
            placeholder = { Text(stringResource(R.string.chat_placeholder)) }, maxLines = 5, shape = Radius.sm,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, keyboardType = KeyboardType.Text, imeAction = ImeAction.Default),
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = colors.canvas, unfocusedContainerColor = colors.canvas,
                focusedBorderColor = colors.ink, unfocusedBorderColor = colors.hairline,
                focusedTextColor = colors.ink, unfocusedTextColor = colors.ink, cursorColor = colors.ink
            )
        )
        FilledIconButton(
            { onIntent(ChatIntent.Send) }, enabled = canSend,
            colors = IconButtonDefaults.filledIconButtonColors(containerColor = colors.brand, contentColor = colors.onBrand)
        ) {
            if (state.sending) CircularProgressIndicator(Modifier.size(18.dp), color = colors.onBrand, strokeWidth = 2.dp)
            else Icon(Icons.AutoMirrored.Outlined.Send, stringResource(R.string.chat_send))
        }
    }
}

/** Довгий тап: видалити своє (або будь-яке — організатору), поскаржитись на чуже. */
@Composable
private fun MessageActions(state: ChatState, message: ChatMessage, onIntent: (ChatIntent) -> Unit) {
    val colors = Poruch.colors
    PoruchSheet({ onIntent(ChatIntent.Select(null)) }) { sheet ->
        Column(Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(message.body, style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary, maxLines = 3)
            if (state.canDelete(message)) SecondaryButton(
                stringResource(R.string.chat_delete), { sheet.close { onIntent(ChatIntent.Delete(message.id)) } },
                Modifier.fillMaxWidth(), tone = colors.danger
            )
            if (!state.isMine(message)) SecondaryButton(
                stringResource(R.string.chat_report), { sheet.close { onIntent(ChatIntent.ShowReport(message)) } },
                Modifier.fillMaxWidth()
            )
        }
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

private val timeFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM, HH:mm")

/** Час повідомлення в поясі пристрою: чат читають тут і зараз. */
private fun messageTime(iso: String): String =
    runCatching { Instant.parse(iso).atZone(ZoneId.systemDefault()).format(timeFormat) }.getOrDefault("")
