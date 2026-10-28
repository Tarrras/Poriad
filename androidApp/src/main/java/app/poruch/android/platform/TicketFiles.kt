package app.poruch.android.platform

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import app.poruch.domain.PoruchLog
import app.poruch.domain.TicketDraft
import app.poruch.domain.TicketKind
import app.poruch.domain.WalletTicket
import app.poruch.shared.PoruchApp
import androidx.core.content.FileProvider
import androidx.exifinterface.media.ExifInterface
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.multi.GenericMultipleBarcodeReader
import com.google.zxing.qrcode.detector.FinderPattern
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import java.io.File
import java.security.MessageDigest
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
    /** SHA-256 файлу: той самий квиток удруге не додається. */
    val fingerprint: String,
)

/** Що показати на весь екран: код квитка великим або сторінку, де коду не знайшли. */
data class TicketSlide(
    val page: Int,
    /** Код у частках сторінки (0…1, згори зліва), щільно; null — показуємо сторінку. */
    val code: RectF?,
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
        val read = runCatching { if (pdf) readPdf(context, target) else Triple("", 1, decodeUpright(target)) }
            .onFailure { PoruchLog.report("wallet", "read failed", it) }.getOrNull()
        if (read == null || read.second == 0 || read.third == null) {
            target.delete()
            return@withContext null
        }
        val (text, pages, preview) = read
        val draft = app.readTicket(text)
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(target.readBytes()).joinToString("") { "%02x".format(it) }
        // Сторінка на квиток (Multiplex), а на одній сторінці буває кілька місць.
        TicketImport(
            id, name, if (pdf) TicketKind.PDF else TicketKind.IMAGE, draft, maxOf(if (pdf) pages else 1, draft.seats.size), preview, source,
            fingerprint
        )
    }

    private fun readPdf(context: Context, file: File): Triple<String, Int, Bitmap?> =
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                val text = if (Build.VERSION.SDK_INT >= 35) {
                    (0 until renderer.pageCount).joinToString("\n") { index ->
                        renderer.openPage(index).use { page -> page.textContents.joinToString("\n") { it.text } }
                    }
                } else legacyText(context, file)
                val preview = if (renderer.pageCount > 0) renderer.openPage(0).use { trimmed(render(it, 900)) } else null
                Triple(text, renderer.pageCount, preview)
            }
        }

    /**
     * Текст PDF на Android 8–14: `PdfRenderer` читає його лише з 15, тож тут pdfbox. Не вийшло — порожньо, і людина
     * заповнює поля сама, як зі знімком.
     */
    private fun legacyText(context: Context, file: File): String = runCatching {
        PDFBoxResourceLoader.init(context.applicationContext)
        PDDocument.load(file).use { PDFTextStripper().getText(it) }
    }.onFailure { PoruchLog.report("wallet", "pdfbox failed", it) }.getOrDefault("")

    /**
     * Що гортати на вході: кожен код квитка окремо й великим (на аркуші їх буває кілька — по одному на людину), а
     * сторінку без коду — цілою. Квиток часто — кут аркуша A4 з умовами й рекламою, і цілою сторінкою QR на екрані
     * виходив міліметрів сім. Коди шукає ZXing на растрі 1600: QR у кутку A4 там ще читається.
     */
    suspend fun slides(context: Context, ticket: WalletTicket): List<TicketSlide> = withContext(Dispatchers.IO) {
        fun slides(page: Int, bitmap: Bitmap?): List<TicketSlide> =
            bitmap?.let(::codeBoxes).orEmpty().map { TicketSlide(page, it) }.ifEmpty { listOf(TicketSlide(page, null)) }
        val target = file(context, ticket.file)
        runCatching {
            if (ticket.kind != TicketKind.PDF) return@runCatching slides(0, decodeUpright(target))
            ParcelFileDescriptor.open(target, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    (0 until renderer.pageCount).flatMap { index -> slides(index, renderer.openPage(index).use { render(it, 1600) }) }
                }
            }
        }.onFailure { PoruchLog.report("wallet", "slides failed", it) }.getOrDefault(emptyList())
    }

    /**
     * Слайд на весь екран — коли до нього догорнули, а не всі разом. Код — наново з PDF (вектор, різкий) чи вирізкою
     * зі знімка; [whole] чи коду нема — сторінка без білих полів.
     */
    suspend fun slideImage(context: Context, ticket: WalletTicket, slide: TicketSlide, whole: Boolean, width: Int): Bitmap? =
        withContext(Dispatchers.IO) {
            val target = file(context, ticket.file)
            runCatching {
                if (ticket.kind != TicketKind.PDF) {
                    val bitmap = decodeUpright(target) ?: return@runCatching null
                    val code = slide.code?.takeIf { !whole } ?: return@runCatching bitmap
                    val x = (code.left * bitmap.width).toInt()
                    val y = (code.top * bitmap.height).toInt()
                    return@runCatching quiet(
                        Bitmap.createBitmap(bitmap, x, y, (code.width() * bitmap.width).toInt().coerceAtMost(bitmap.width - x),
                            (code.height() * bitmap.height).toInt().coerceAtMost(bitmap.height - y))
                    )
                }
                ParcelFileDescriptor.open(target, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { renderer ->
                        renderer.openPage(slide.page).use { page ->
                            slide.code?.takeIf { !whole }?.let { return@runCatching quiet(render(page, it, width)) }
                            contentBox(render(page, 600))?.let { render(page, it, width) } ?: render(page, width)
                        }
                    }
                }
            }.onFailure { PoruchLog.report("wallet", "slide failed", it) }.getOrNull()
        }

    /** Ціла сторінка: її й надсилаємо — з місцем, залом і умовами. */
    private suspend fun page(context: Context, ticket: WalletTicket, index: Int, width: Int): Bitmap? = withContext(Dispatchers.IO) {
        val target = file(context, ticket.file)
        runCatching {
            if (ticket.kind == TicketKind.PDF) {
                ParcelFileDescriptor.open(target, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { renderer -> renderer.openPage(index).use { render(it, width) } }
                }
            } else decodeUpright(target)
        }.getOrNull()
    }

    /**
     * Знімок прямо й не більший за 2560: камера пише повернуті пікселі з позначкою EXIF, і без неї квиток лежав би
     * на боці; повний кадр 12 Мп — 48 МБ на екран, якому стільки не треба.
     */
    private fun decodeUpright(file: File): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }.also { BitmapFactory.decodeFile(file.path, it) }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 2560) sample *= 2
        val bitmap = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val degrees = when (runCatching { ExifInterface(file).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
            .getOrDefault(ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees) }, true)
    }

    /**
     * Коди квитка у частках (0…1, згори зліва), згори вниз і зліва направо. ZXing віддає центри шукачів QR; до краю
     * коду від них — 3,5 модуля, тож рамку розширюємо на стільки (інші формати — на п'яту частину).
     */
    private fun codeBoxes(bitmap: Bitmap): List<RectF> {
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h).also { bitmap.getPixels(it, 0, w, 0, 0, w, h) }
        val hints = mapOf(
            DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE, BarcodeFormat.AZTEC, BarcodeFormat.DATA_MATRIX, BarcodeFormat.PDF_417),
            DecodeHintType.TRY_HARDER to true,
        )
        val results = runCatching {
            GenericMultipleBarcodeReader(MultiFormatReader()).decodeMultiple(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(w, h, pixels))), hints)
        }.getOrDefault(emptyArray())
        val boxes = mutableListOf<RectF>()
        for (result in results) {
            val points = result.resultPoints?.filterNotNull().orEmpty()
            if (points.size < 2) continue
            val left = points.minOf { it.x }; val right = points.maxOf { it.x }
            val top = points.minOf { it.y }; val bottom = points.maxOf { it.y }
            val module = points.filterIsInstance<FinderPattern>().map { it.estimatedModuleSize }.average().toFloat()
            val pad = if (module.isNaN()) maxOf(right - left, bottom - top) * 0.2f else module * 3.6f
            val box = RectF(
                ((left - pad) / w).coerceAtLeast(0f), ((top - pad) / h).coerceAtLeast(0f),
                ((right + pad) / w).coerceAtMost(1f), ((bottom + pad) / h).coerceAtMost(1f)
            )
            if (boxes.none { it.contains(box.centerX(), box.centerY()) }) boxes += box
        }
        return boxes.sortedWith(compareBy({ (it.top * 20).toInt() }, { it.left }))
    }

    /** Код на білому з тихою зоною в 12% ширини: вирізка щільна, тож сусідній текст у поле коду не лізе. */
    private fun quiet(code: Bitmap): Bitmap {
        val margin = (code.width * 0.12f).toInt()
        return Bitmap.createBitmap(code.width + margin * 2, code.height + margin * 2, Bitmap.Config.ARGB_8888).apply {
            eraseColor(Color.WHITE)
            android.graphics.Canvas(this).drawBitmap(code, margin.toFloat(), margin.toFloat(), null)
        }
    }

    /** Частина сторінки [box] (0…1, згори зліва) завширшки [width]: вектор PDF, а не збільшений растр, тож QR різкий. */
    private fun render(page: PdfRenderer.Page, box: RectF, width: Int): Bitmap {
        val scale = width / (box.width() * page.width).coerceAtLeast(1f)
        val height = (box.height() * page.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
            eraseColor(Color.WHITE)
            val transform = Matrix().apply {
                setScale(scale, scale)
                postTranslate(-box.left * page.width * scale, -box.top * page.height * scale)
            }
            page.render(this, null, transform, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
        }
    }

    /**
     * Одна сторінка окремим файлом (хвиля 2): з PDF на кількох той, з ким ідеш, отримує лише свій квиток. PDF — растр
     * сторінки (QR читається), знімок — як є. Null — не вийшло.
     */
    suspend fun share(context: Context, ticket: WalletTicket, page: Int, text: String): Boolean {
        val file = withContext(Dispatchers.IO) {
            runCatching {
                val folder = File(context.cacheDir, "send").apply { mkdirs() }
                val source = file(context, ticket.file)
                if (ticket.kind == TicketKind.PDF) {
                    val bitmap = TicketFiles.page(context, ticket, page, 1400) ?: return@runCatching null
                    val out = File(folder, "Квиток ${page + 1}.pdf")
                    // Растр тексту не має: унизу — справжній текст, і отримувач бачить квиток розібраним, а не порожнім.
                    val footer = footer(ticket, page)
                    val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { textSize = 26f; color = Color.DKGRAY }
                    val lineHeight = 36
                    val document = PdfDocument()
                    val info = PdfDocument.PageInfo.Builder(bitmap.width, bitmap.height + lineHeight * footer.size + 40, 1).create()
                    document.startPage(info).also { sheet ->
                        sheet.canvas.drawColor(Color.WHITE)
                        sheet.canvas.drawBitmap(bitmap, 0f, 0f, null)
                        footer.forEachIndexed { i, line -> sheet.canvas.drawText(line, 40f, bitmap.height + 20f + lineHeight * (i + 1), paint) }
                        document.finishPage(sheet)
                    }
                    out.outputStream().use { document.writeTo(it) }
                    document.close()
                    out
                } else File(folder, "Квиток ${page + 1}.jpg").also { source.copyTo(it, overwrite = true) }
            }.onFailure { PoruchLog.report("wallet", "share failed", it) }.getOrNull()
        } ?: return false
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = if (ticket.kind == TicketKind.PDF) "application/pdf" else "image/jpeg"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, text)
            clipData = ClipData.newRawUri(file.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, null))
        return true
    }

    /** Рядки з підписами, які читає `TicketReader`: назва, початок, майданчик, місце цієї сторінки. */
    private fun footer(ticket: WalletTicket, page: Int): List<String> {
        val start = runCatching {
            java.time.Instant.parse(ticket.startsAt).atZone(java.time.ZoneId.of(ticket.timeZone))
                .format(java.time.format.DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm"))
        }.getOrNull()
        val seat = ticket.seats.getOrNull(page)?.let { seat -> seat.row?.let { "Ряд $it Місце ${seat.seat}" } ?: "Місце ${seat.seat}" }
        return listOfNotNull("Назва: ${ticket.title}", start?.let { "Початок: $it" }, ticket.place?.let { "Майданчик: $it" }, seat)
    }

    /** Прев'ю без білих полів: квиток часто — смужка на аркуші A4, і в шторці інакше видно лише папір. */
    private fun trimmed(bitmap: Bitmap): Bitmap {
        val box = contentBox(bitmap) ?: return bitmap
        val x0 = (box.left * bitmap.width).toInt()
        val y0 = (box.top * bitmap.height).toInt()
        return Bitmap.createBitmap(bitmap, x0, y0, (box.right * bitmap.width).toInt() - x0, (box.bottom * bitmap.height).toInt() - y0)
    }

    /** Де на сторінці вміст: частки (0…1, згори зліва) з полем 1/30 ширини. Null — сторінка біла. */
    private fun contentBox(bitmap: Bitmap): RectF? {
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h).also { bitmap.getPixels(it, 0, w, 0, 0, w, h) }
        var minX = w; var minY = h; var maxX = -1; var maxY = -1
        for (y in 0 until h step 2) for (x in 0 until w step 2) {
            val c = pixels[y * w + x]
            if (Color.red(c) < 235 || Color.green(c) < 235 || Color.blue(c) < 235) {
                minX = minOf(minX, x); maxX = maxOf(maxX, x); minY = minOf(minY, y); maxY = maxOf(maxY, y)
            }
        }
        if (maxX < 0) return null
        val pad = w / 30
        return RectF(
            (minX - pad).coerceAtLeast(0).toFloat() / w, (minY - pad).coerceAtLeast(0).toFloat() / h,
            (maxX + pad).coerceAtMost(w).toFloat() / w, (maxY + pad).coerceAtMost(h).toFloat() / h
        )
    }

    /** Квиток — папір: білий під сторінкою, інакше прозорий PDF лягає на темне тло, і QR не читається. */
    private fun render(page: PdfRenderer.Page, width: Int): Bitmap =
        Bitmap.createBitmap(width, (width.toFloat() * page.height / page.width.coerceAtLeast(1)).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
            .apply {
                eraseColor(Color.WHITE)
                page.render(this, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            }
}
