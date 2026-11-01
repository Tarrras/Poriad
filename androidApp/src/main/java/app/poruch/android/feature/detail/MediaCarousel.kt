package app.poruch.android.feature.detail

import android.view.TextureView
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.media3.common.AudioAttributes
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.EventMedia
import app.poruch.domain.MediaKind
import coil3.compose.AsyncImage

// Фото й відео події замість обкладинки (docs/organizers-1.5.md, «Фото й відео в редакторі», «Показ»).

/**
 * Карусель на всю обкладинку. Відео на екрані грає без звуку в циклі, лише поки його сторінка зупинилась, а тап
 * відкриває його на весь екран зі звуком. Зі зменшеним рухом — кадр і ▶, без автозапуску.
 */
@Composable
internal fun MediaCarousel(media: List<EventMedia>, pager: PagerState, modifier: Modifier = Modifier) {
    var opened by remember { mutableStateOf<EventMedia?>(null) }
    val reduced = Poruch.reducedMotion
    val play = stringResource(R.string.media_play_a11y)
    HorizontalPager(pager, modifier, key = { media[it].url }) { page ->
        val item = media[page]
        if (item.kind == MediaKind.PHOTO) AsyncImage(item.url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else Box(Modifier.fillMaxSize().clickable(onClickLabel = play) { opened = item }) {
            AsyncImage(item.poster, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            // Відкрили на весь екран — обкладинка стоїть: два плеєри тягнули б той самий файл двічі.
            if (!reduced && pager.settledPage == page && opened == null) VideoSurface(rememberVideoPlayer(item.url, muted = true), crop = true, Modifier.fillMaxSize())
            else Icon(
                PoruchIcons.play, null,
                Modifier.align(Alignment.Center).size(56.dp).background(Color.Black.copy(alpha = 0.4f), CircleShape).padding(14.dp),
                tint = Color.White
            )
        }
    }
    opened?.let { FullScreenVideo(it) { opened = null } }
}

/** Крапки сторінок у верхньому ряду обкладинки, між «назад» і закладкою. */
@Composable
internal fun PagerDots(pager: PagerState, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(pager.pageCount) {
            Box(Modifier.size(if (it == pager.currentPage) 8.dp else 6.dp).background(Color.White.copy(alpha = if (it == pager.currentPage) 1f else 0.55f), CircleShape))
        }
    }
}

/** Відео на весь екран зі звуком: тап — пауза й далі, хрестик — назад. */
@Composable
private fun FullScreenVideo(media: EventMedia, onClose: () -> Unit) {
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val player = rememberVideoPlayer(media.url, muted = false)
        Box(Modifier.fillMaxSize().background(Color.Black).clickable { if (player.isPlaying) player.pause() else player.play() }) {
            AsyncImage(media.poster, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            VideoSurface(player, crop = false, Modifier.fillMaxSize())
            Box(Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(Spacing.md)) {
                ScrimButton(PoruchIcons.close, stringResource(R.string.close), onClose)
            }
        }
    }
}

/**
 * Плеєр на час, поки відео на екрані: без звуку не бере аудіофокус і не спиняє музику людини, зі звуком — бере.
 * Застосунок у фоні — пауза.
 */
@OptIn(UnstableApi::class)
@Composable
private fun rememberVideoPlayer(url: String, muted: Boolean): ExoPlayer {
    val context = LocalContext.current
    val player = remember(url, muted) {
        ExoPlayer.Builder(context).build().apply {
            setAudioAttributes(AudioAttributes.DEFAULT, !muted)
            volume = if (muted) 0f else 1f
            repeatMode = Player.REPEAT_MODE_ONE
            setMediaItem(MediaItem.fromUri(url))
            playWhenReady = true
            prepare()
        }
    }
    DisposableEffect(player) { onDispose { player.release() } }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { player.pause() }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { player.play() }
    return player
}

/**
 * Кадри плеєра в TextureView: [crop] — заповнити, обрізавши краї (обкладинка), інакше вписати (весь екран). Поки перший
 * кадр не прийшов, видно постер під ним.
 */
@Composable
private fun VideoSurface(player: ExoPlayer, crop: Boolean, modifier: Modifier) {
    var aspect by remember(player) { mutableFloatStateOf(0f) }
    var rendered by remember(player) { mutableStateOf(false) }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.height > 0) aspect = videoSize.width * videoSize.pixelWidthHeightRatio / videoSize.height
            }
            override fun onRenderedFirstFrame() { rendered = true }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    BoxWithConstraints(modifier.clipToBounds(), contentAlignment = Alignment.Center) {
        val box = maxWidth / maxHeight
        val ratio = aspect.takeIf { it > 0f } ?: box
        // Ширше за рамку й обрізаємо — або вужче й вписуємо: тоді висота рамки, інакше ширина.
        val (width, height) = if ((ratio > box) == crop) maxHeight * ratio to maxHeight else maxWidth to maxWidth / ratio
        AndroidView(
            { TextureView(it).also(player::setVideoTextureView) },
            Modifier.requiredSize(width, height).alpha(if (rendered) 1f else 0f),
            onRelease = player::clearVideoTextureView
        )
    }
}
