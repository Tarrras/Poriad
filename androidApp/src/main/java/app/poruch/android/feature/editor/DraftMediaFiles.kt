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
import android.media.MediaCodecInfo
import androidx.media3.effect.FrameDropEffect
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
     * Відео: перші [MediaRules.VIDEO_MAX_SECONDS] с, H.264 з коротшою стороною до 720, до 30 кадрів, ≈ 1,6 Мбіт/с.
     * Завелике (кодек перебрав бітрейт) — ще раз у 540. Обкладинка — перший кадр у JPEG.
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
        for ((side, bitrate) in ATTEMPTS) {
            transcode(uri, out, bitrate, side.takeIf { shortSide > it })
            if (out.length() <= MediaRules.VIDEO_MAX_BYTES) break
        }
        require(out.length() in 1..MediaRules.VIDEO_MAX_BYTES) { "video too large: ${out.length()}" }
        withContext(Dispatchers.IO) { poster(key).writeBytes(firstFrame(out)) }
        return Imported(local(key, MediaKind.VIDEO), trimmed = durationMs > MediaRules.VIDEO_MAX_SECONDS * 1000L)
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private suspend fun transcode(uri: Uri, out: File, bitrate: Int, shortSide: Int?) = withContext(Dispatchers.Main) {
        // Transformer живе на потоці з Looper і там же кличе слухача; важка робота — у його власних потоках.
        suspendCancellableCoroutine { continuation ->
            val item = MediaItem.Builder().setUri(uri)
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder().setEndPositionMs(MediaRules.VIDEO_MAX_SECONDS * 1000L).build()
                ).build()
            // 60 кадрів з камери — удвічі більше байтів за той самий вигляд у стрічці.
            val video = listOfNotNull(FrameDropEffect.createDefaultFrameDropEffect(FRAME_RATE), shortSide?.let(Presentation::createForShortSide))
            val edited = EditedMediaItem.Builder(item).setEffects(Effects(emptyList(), video)).build()
            // HDR з камери в H.264 не влізе: тонуємо в SDR, інакше Safari й Chrome показали б вицвіле.
            val composition = Composition.Builder(EditedMediaItemSequence.Builder(edited).build())
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL).build()
            val transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(
                    DefaultEncoderFactory.Builder(context)
                        // CBR: на VBR Android 13+ піднімає бітрейт до своєї «мінімальної якості» (VQApply: 1,6 → 2,07 Мбіт/с
                        // для 720p30), і 30 с упиралися в 8 МБ. Кодек без CBR лишається на своєму режимі.
                        .setRequestedVideoEncoderSettings(
                            VideoEncoderSettings.Builder().setBitrate(bitrate)
                                .setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR).build()
                        )
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
        const val FRAME_RATE = 30f
        /** Коротша сторона й бітрейт: 30 с × (1,6 Мбіт/с + 96 кбіт/с звук) ≈ 6,4 МБ; запасний 540 — коли кодек перебрав. */
        val ATTEMPTS = listOf(720 to 1_600_000, 540 to 900_000)
        const val AUDIO_BITRATE = 96_000
        const val POSTER_QUALITY = 85
    }
}

/** Мініатюра файлу з події: у відео — кадр-обкладинка. */
val EventMedia.preview: String get() = poster ?: url
