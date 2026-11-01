package app.poruch.android.feature.editor

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import app.poruch.android.feature.detail.readImage
import app.poruch.domain.DraftMedia
import app.poruch.domain.EventMedia
import app.poruch.domain.ImageRules
import app.poruch.domain.MediaBytes
import app.poruch.domain.MediaKind
import app.poruch.domain.MediaRules
import app.poruch.domain.PoruchLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Фото й відео чернетки на телефоні (docs/organizers-1.5.md, «Фото й відео в редакторі»): сховище пускає файл лише до
 * наявної події, тож до публікації вони лежать тут, уже стиснені. Імʼя файлу — ключ [DraftMedia.Local.key].
 */
class DraftMediaFiles(private val context: Context) {
    private val dir get() = File(context.filesDir, DIR).apply { mkdirs() }

    fun file(key: String, kind: MediaKind) = File(dir, if (kind == MediaKind.VIDEO) "$key.mp4" else "$key.jpg")
    private fun poster(key: String) = File(dir, "$key-poster.jpg")

    /** Файл чернетки з ключа: байти читаються лише під час вивантаження. */
    fun local(key: String, kind: MediaKind): DraftMedia.Local {
        val main = file(key, kind)
        val cover = poster(key).takeIf { kind == MediaKind.VIDEO }
        return DraftMedia.Local(key, kind, MediaBytes { main.readBytes() }, cover?.let { MediaBytes { it.readBytes() } })
    }

    /** Що показати на мініатюрі: файл на телефоні чи адреса, для відео — кадр-обкладинка. */
    fun thumbnail(media: DraftMedia): Any = when (media) {
        is DraftMedia.Local -> if (media.kind == MediaKind.VIDEO) poster(media.key) else file(media.key, media.kind)
        is DraftMedia.Remote -> media.media.preview
        is DraftMedia.Copied -> media.media.preview
    }

    fun delete(key: String) {
        MediaKind.entries.forEach { file(key, it).delete() }
        poster(key).delete()
    }

    /** Лишає тільки файли [keep]: решта — з прибраних, опублікованих чи покинутих чернеток. */
    fun prune(keep: Set<String>) {
        dir.listFiles()?.filter { it.name.substringBefore('.').removeSuffix("-poster") !in keep }?.forEach { it.delete() }
    }

    class Imported(val media: DraftMedia.Local, val trimmed: Boolean)

    /** Обране в системному виборі → стиснений файл чернетки. Null — не вдалося: файл не читається чи відео не стиснулось. */
    suspend fun import(uri: Uri): Imported? {
        val key = UUID.randomUUID().toString()
        return try {
            if (context.contentResolver.getType(uri).orEmpty().startsWith("video/")) video(uri, key)
            else withContext(Dispatchers.IO) {
                // Той самий шлях, що й аватар: JPEG без метаданих, довша сторона до 2048.
                file(key, MediaKind.PHOTO).writeBytes(context.readImage(uri).first)
                Imported(local(key, MediaKind.PHOTO), trimmed = false)
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            delete(key); throw e
        } catch (e: Exception) {
            PoruchLog.w("editor") { "media import failed: ${e.javaClass.simpleName} ${e.message}" }
            delete(key)
            null
        }
    }

    /**
     * Відео: перші [MediaRules.VIDEO_MAX_SECONDS] с, H.264 з коротшою стороною до 720, ≈ 2 Мбіт/с. Кодек сам може
     * перебрати бітрейт, тож завелике — ще раз тихіше. Обкладинка — перший кадр у JPEG.
     */
    @androidx.annotation.OptIn(UnstableApi::class)
    private suspend fun video(uri: Uri, key: String): Imported {
        val (durationMs, shortSide) = withContext(Dispatchers.IO) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, uri)
                fun read(key: Int) = retriever.extractMetadata(key)?.toLongOrNull() ?: 0L
                read(MediaMetadataRetriever.METADATA_KEY_DURATION) to
                    minOf(read(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH), read(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT))
            } finally { retriever.release() }
        }
        val out = file(key, MediaKind.VIDEO)
        for (bitrate in VIDEO_BITRATES) {
            transcode(uri, out, bitrate, scale = shortSide > SHORT_SIDE)
            if (out.length() <= MediaRules.VIDEO_MAX_BYTES) break
        }
        require(out.length() in 1..MediaRules.VIDEO_MAX_BYTES) { "video too large: ${out.length()}" }
        withContext(Dispatchers.IO) { poster(key).writeBytes(firstFrame(out)) }
        return Imported(local(key, MediaKind.VIDEO), trimmed = durationMs > MediaRules.VIDEO_MAX_SECONDS * 1000L)
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private suspend fun transcode(uri: Uri, out: File, bitrate: Int, scale: Boolean) = withContext(Dispatchers.Main) {
        // Transformer живе на потоці з Looper і там же кличе слухача; важка робота — у його власних потоках.
        suspendCancellableCoroutine { continuation ->
            val item = MediaItem.Builder().setUri(uri)
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder().setEndPositionMs(MediaRules.VIDEO_MAX_SECONDS * 1000L).build()
                ).build()
            val edited = EditedMediaItem.Builder(item)
                .setEffects(Effects(emptyList(), if (scale) listOf(Presentation.createForShortSide(SHORT_SIDE)) else emptyList()))
                .build()
            // HDR з камери в H.264 не влізе: тонуємо в SDR, інакше Safari й Chrome показали б вицвіле.
            val composition = Composition.Builder(EditedMediaItemSequence.Builder(edited).build())
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL).build()
            val transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(
                    DefaultEncoderFactory.Builder(context)
                        .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
                        .setRequestedAudioEncoderSettings(AudioEncoderSettings.Builder().setBitrate(AUDIO_BITRATE).build())
                        .build()
                )
                // Бакет публічний: без метаданих, як і фото (місце зйомки, модель телефона).
                .setMuxerFactory(InAppMp4Muxer.Factory { entries -> entries.clear() })
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) = continuation.resume(Unit)
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) =
                        continuation.resumeWithException(exportException)
                })
                .build()
            transformer.start(composition, out.path)
            continuation.invokeOnCancellation { Handler(Looper.getMainLooper()).post { transformer.cancel() } }
        }
    }

    private fun firstFrame(video: File): ByteArray {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(video.path)
            val frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: error("no frame")
            val output = ByteArrayOutputStream()
            try { frame.compress(Bitmap.CompressFormat.JPEG, POSTER_QUALITY, output) } finally { frame.recycle() }
            require(output.size() in 1..ImageRules.MAX_BYTES) { "poster too large" }
            return output.toByteArray()
        } finally { retriever.release() }
    }

    private companion object {
        const val DIR = "draft_media"
        const val SHORT_SIDE = 720
        /** 30 с × (1,8 Мбіт/с відео + 96 кбіт/с звук) ≈ 7 МБ; запасний — коли кодек перебрав. */
        val VIDEO_BITRATES = listOf(1_800_000, 1_100_000)
        const val AUDIO_BITRATE = 96_000
        const val POSTER_QUALITY = 85
    }
}

/** Мініатюра файлу з події: у відео — кадр-обкладинка. */
val EventMedia.preview: String get() = poster ?: url
