package app.poruch.android.platform

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import app.poruch.domain.PoruchLog
import app.poruch.domain.TicketDraft
import app.poruch.domain.TicketKind
import app.poruch.domain.WalletTicket
import app.poruch.shared.PoruchApp
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Квиток, що прийшов файлом і чекає підтвердження (docs/ticket-wallet.md). Файл уже скопійовано до себе. */
data class TicketImport(
    val id: String,
    val file: String,
    val kind: TicketKind,
    val draft: TicketDraft,
    val count: Int,
    val preview: Bitmap?,
    /** `share` — «Поділитися» чи «Відкрити за допомогою», `picker` — вибір у «Моїх подіях». */
    val source: String,
)

/**
 * Файли квитків — лише на телефоні: копія в `filesDir/tickets`, текст — `PdfRenderer` з Android 15. Старіший Android і
 * знімок (ML Kit не читає кирилицю) — без тексту: людина заповнює поля сама. Сервер файлів не бачить.
 */
object TicketFiles {
    private fun folder(context: Context) = File(context.filesDir, "tickets").apply { mkdirs() }

    fun file(context: Context, name: String) = File(folder(context), name)

    fun remove(context: Context, name: String) {
        file(context, name).delete()
    }

    /** Файл квитка з вхідного інтенту: «Поділитися» (`SEND`) чи «Відкрити за допомогою» (`VIEW`). Null — не квиток. */
    fun uriOf(intent: Intent): Uri? {
        val type = intent.type.orEmpty()
        if (!type.startsWith("application/pdf") && !type.startsWith("image/")) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> intent.data?.takeIf { it.scheme == "content" || it.scheme == "file" }
            else -> null
        }
    }

    /** Копія до себе й читання. Null — не PDF і не знімок або файл не відкрився. */
    suspend fun load(context: Context, uri: Uri, app: PoruchApp, source: String): TicketImport? = withContext(Dispatchers.IO) {
        val type = context.contentResolver.getType(uri).orEmpty()
        val pdf = type == "application/pdf" || uri.lastPathSegment?.endsWith(".pdf", ignoreCase = true) == true
        if (!pdf && !type.startsWith("image/")) return@withContext null
        val id = UUID.randomUUID().toString()
        val name = id + if (pdf) ".pdf" else ".jpg"
        val target = file(context, name)
        runCatching {
            context.contentResolver.openInputStream(uri)!!.use { input -> target.outputStream().use { input.copyTo(it) } }
        }.getOrElse {
            PoruchLog.report("wallet", "copy failed", it)
            return@withContext null
        }
        val read = runCatching { if (pdf) readPdf(target) else Triple("", 1, BitmapFactory.decodeFile(target.path)) }
            .onFailure { PoruchLog.report("wallet", "read failed", it) }.getOrNull()
        if (read == null || read.second == 0 || read.third == null) {
            target.delete()
            return@withContext null
        }
        val (text, pages, preview) = read
        val draft = app.readTicket(text)
        // Сторінка на квиток (Multiplex), а на одній сторінці буває кілька місць.
        TicketImport(id, name, if (pdf) TicketKind.PDF else TicketKind.IMAGE, draft, maxOf(if (pdf) pages else 1, draft.seats.size), preview, source)
    }

    private fun readPdf(file: File): Triple<String, Int, Bitmap?> =
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                val text = if (Build.VERSION.SDK_INT >= 35) {
                    (0 until renderer.pageCount).joinToString("\n") { index ->
                        renderer.openPage(index).use { page -> page.textContents.joinToString("\n") { it.text } }
                    }
                } else ""
                val preview = if (renderer.pageCount > 0) renderer.openPage(0).use { render(it, 900) } else null
                Triple(text, renderer.pageCount, preview)
            }
        }

    /** Сторінки квитка для показу на весь екран: PDF — кожна сторінка, знімок — він сам. */
    suspend fun pages(context: Context, ticket: WalletTicket, width: Int): List<Bitmap> = withContext(Dispatchers.IO) {
        val target = file(context, ticket.file)
        runCatching {
            if (ticket.kind == TicketKind.PDF) {
                ParcelFileDescriptor.open(target, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { renderer -> (0 until renderer.pageCount).map { i -> renderer.openPage(i).use { render(it, width) } } }
                }
            } else listOfNotNull(BitmapFactory.decodeFile(target.path))
        }.getOrDefault(emptyList())
    }

    /** Квиток — папір: білий під сторінкою, інакше прозорий PDF лягає на темне тло, і QR не читається. */
    private fun render(page: PdfRenderer.Page, width: Int): Bitmap =
        Bitmap.createBitmap(width, (width.toFloat() * page.height / page.width.coerceAtLeast(1)).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
            .apply {
                eraseColor(Color.WHITE)
                page.render(this, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            }
}
