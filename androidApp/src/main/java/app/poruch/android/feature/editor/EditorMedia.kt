package app.poruch.android.feature.editor

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.AnnounceFailure
import app.poruch.domain.AnnounceField
import app.poruch.domain.AnnouncementFill
import app.poruch.domain.DraftMedia
import app.poruch.domain.MediaKind
import coil3.compose.AsyncImage

// Крок 1 редактора: «Є готовий анонс?» і «Фото й відео» (docs/organizers-1.5.md, хвиля 2).

/** Картка «Є готовий анонс?» над назвою, а після відповіді — рядок «Заповнили з анонсу…» з «Інший текст». */
@Composable
internal fun AnnounceCard(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val filled = state.announced
    if (filled != null) {
        Row(
            Modifier.fillMaxWidth().cardSurface(Radius.md).padding(start = Spacing.lg, top = Spacing.sm, bottom = Spacing.sm, end = Spacing.sm),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Icon(
                if (filled.failure == null) PoruchIcons.sparkle else PoruchIcons.alert, null, Modifier.size(18.dp),
                tint = if (filled.failure == null) colors.brand else colors.inkSecondary
            )
            Text(announceSummary(filled), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
            GhostButton(stringResource(R.string.announce_other), { onIntent(EditorIntent.ReopenAnnounce) }, tone = colors.brand)
        }
        return
    }
    Column(
        Modifier.fillMaxWidth().cardSurface(Radius.md).padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.announce_title), style = MaterialTheme.typography.titleSmall, color = colors.ink)
            Text(stringResource(R.string.announce_subtitle), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        // Біле поле на білій картці зникало: тут воно тихе, як у шторках.
        CompositionLocalProvider(LocalFieldSurface provides colors.surfaceMuted) {
            LabelledField(
                stringResource(R.string.announce_field), state.announce, { onIntent(EditorIntent.SetAnnounce(it)) },
                singleLine = false, minLines = 3
            )
        }
        SecondaryButton(
            stringResource(if (state.announcing) R.string.announce_filling else R.string.announce_fill),
            { onIntent(EditorIntent.FillFromAnnounce) }, Modifier.fillMaxWidth(),
            enabled = state.announce.isNotBlank() && !state.announcing, icon = PoruchIcons.sparkle
        )
    }
}

@Composable
private fun announceSummary(fill: AnnouncementFill): String = when (fill.failure) {
    AnnounceFailure.LIMIT -> stringResource(R.string.announce_limited)
    null -> stringResource(R.string.announce_filled, fill.filled.map { stringResource(it.label) }.joinToString(", "))
    else -> stringResource(R.string.announce_failed)
}

private val AnnounceField.label: Int
    get() = when (this) {
        AnnounceField.TITLE -> R.string.announce_part_title
        AnnounceField.DESCRIPTION -> R.string.announce_part_description
        AnnounceField.CATEGORY -> R.string.announce_part_category
        AnnounceField.DATE -> R.string.announce_part_date
        AnnounceField.PLACE -> R.string.announce_part_place
        AnnounceField.CAPACITY -> R.string.announce_part_capacity
        AnnounceField.AGE -> R.string.announce_part_age
        AnnounceField.CONTACT -> R.string.announce_part_contact
    }

/**
 * «Фото й відео»: плитки в ряд, «+» — системний вибір фото й відео, довгий тап — перетягнути, хрестик — прибрати.
 * Необовʼязково й публікацію не блокує.
 */
@Composable
internal fun MediaSection(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val context = LocalContext.current
    val files = remember { DraftMediaFiles(context.applicationContext) }
    val room = state.mediaRoom
    // Вибір кількох потребує щонайменше двох місць; на останнє — звичайний вибір одного.
    val pickMany = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(room.coerceAtLeast(2))) {
        if (it.isNotEmpty()) onIntent(EditorIntent.AddMedia(it))
    }
    val pickOne = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri?.let { onIntent(EditorIntent.AddMedia(listOf(it))) }
    }
    val request = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(stringResource(R.string.media_title).uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
        Text(stringResource(R.string.media_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        val media by rememberUpdatedState(state.form.media)
        var dragged by remember { mutableStateOf<String?>(null) }
        var offset by remember { mutableFloatStateOf(0f) }
        val slot = with(LocalDensity.current) { (TILE + Spacing.sm).toPx() }
        val cover = stringResource(R.string.media_cover)
        val makeCover = stringResource(R.string.media_make_cover_a11y)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            state.form.media.forEachIndexed { index, item ->
                key(item.id) {
                    val dragging = dragged == item.id
                    MediaTile(
                        files.thumbnail(item), item.kind, first = index == 0, trimmed = item.id in state.trimmed,
                        onRemove = { onIntent(EditorIntent.RemoveMedia(media.indexOf(item))) },
                        modifier = Modifier
                            .zIndex(if (dragging) 1f else 0f)
                            .graphicsLayer {
                                translationX = if (dragging) offset else 0f
                                if (dragging) { scaleX = 1.06f; scaleY = 1.06f; shadowElevation = 12f }
                            }
                            .semantics {
                                if (index == 0) contentDescription = cover
                                // Перетягування пальцем TalkBack не дістане: обкладинку роблять дією.
                                else customActions = listOf(CustomAccessibilityAction(makeCover) {
                                    onIntent(EditorIntent.MoveMedia(media.indexOf(item), 0)); true
                                })
                            }
                            .pointerInput(item.id) {
                                detectDragGesturesAfterLongPress(
                                    onDragStart = { dragged = item.id; offset = 0f },
                                    onDragEnd = { dragged = null; offset = 0f },
                                    onDragCancel = { dragged = null; offset = 0f }
                                ) { change, amount ->
                                    change.consume()
                                    offset += amount.x
                                    // Перейшли пів сусідньої плитки — міняємось місцями, і плитка далі під пальцем.
                                    val from = media.indexOf(item)
                                    if (offset > slot / 2 && from < media.lastIndex) {
                                        onIntent(EditorIntent.MoveMedia(from, from + 1)); offset -= slot
                                    } else if (offset < -slot / 2 && from > 0) {
                                        onIntent(EditorIntent.MoveMedia(from, from - 1)); offset += slot
                                    }
                                }
                            }
                    )
                }
            }
            repeat(state.importing) {
                Box(Modifier.size(TILE).background(colors.surfaceMuted, Radius.md), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(24.dp), color = colors.brand, strokeWidth = 2.dp)
                }
            }
            if (room > 0) {
                val add = stringResource(R.string.media_add_a11y)
                Box(
                    Modifier.size(TILE).background(colors.brandContainer, Radius.md).clip(Radius.md)
                        .semantics { contentDescription = add }
                        .pressable { if (room > 1) pickMany.launch(request) else pickOne.launch(request) },
                    contentAlignment = Alignment.Center
                ) { Icon(PoruchIcons.plus, null, Modifier.size(24.dp), tint = colors.onBrandContainer) }
            }
        }
        if (state.importing > 0) Text(stringResource(R.string.media_compressing), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        if (state.mediaFailed) Text(stringResource(R.string.media_not_added), style = MaterialTheme.typography.bodySmall, color = colors.danger)
    }
}

@Composable
private fun MediaTile(
    thumbnail: Any, kind: MediaKind, first: Boolean, trimmed: Boolean, onRemove: () -> Unit, modifier: Modifier
) {
    val colors = Poruch.colors
    Column(modifier.width(TILE), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Box(Modifier.size(TILE).clip(Radius.md).background(colors.surfaceMuted)) {
            AsyncImage(thumbnail, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            if (kind == MediaKind.VIDEO) Icon(
                PoruchIcons.play, null, Modifier.align(Alignment.Center).size(28.dp).background(Color.Black.copy(alpha = 0.4f), CircleShape).padding(6.dp),
                tint = Color.White
            )
            // Хрестик у куті: 24 dp кружок, а ціль дотику — 48.
            val remove = stringResource(R.string.media_remove_a11y)
            Box(
                Modifier.align(Alignment.TopEnd).size(40.dp).semantics { contentDescription = remove }.pressable(onClick = onRemove),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    PoruchIcons.close, null, Modifier.size(22.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape).padding(4.dp),
                    tint = Color.White
                )
            }
        }
        // Під плиткою, а не на ній: на 88 dp «Обкладинка» переносилась.
        if (first) Text(stringResource(R.string.media_cover), style = MaterialTheme.typography.labelSmall, color = colors.ink, maxLines = 1)
        if (trimmed) Text(stringResource(R.string.media_video_trimmed), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
    }
}

/** Стабільний ключ плитки: імʼя файлу на телефоні чи адреса в сховищі. */
private val DraftMedia.id: String
    get() = when (this) {
        is DraftMedia.Local -> key
        is DraftMedia.Remote -> media.url
        is DraftMedia.Copied -> media.url
    }

private val TILE = 88.dp
