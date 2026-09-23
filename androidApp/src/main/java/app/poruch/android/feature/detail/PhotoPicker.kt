package app.poruch.android.feature.detail

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import app.poruch.android.R
import app.poruch.android.ui.Poruch
import app.poruch.android.ui.SecondaryButton
import app.poruch.android.ui.Spacing
import app.poruch.domain.ImageRules
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/** Читає обраний файл, перекодовує в JPEG без метаданих і віддає байти інтентом. */
@Composable
fun PhotoPickerButton(busy: Boolean, onPicked: (ByteArray, String) -> Unit) {
    val colors = Poruch.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf(false) }
    var reading by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            reading = true
            val picked = withContext(Dispatchers.IO) { runCatching { context.readImage(uri) }.getOrNull() }
            reading = false
            error = picked == null
            picked?.let { (bytes, mime) -> onPicked(bytes, mime) }
        }
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SecondaryButton(
            stringResource(R.string.add_photo),
            { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            Modifier.fillMaxWidth(), enabled = !busy && !reading, icon = Icons.Outlined.PhotoCamera
        )
        if (reading) LinearProgressIndicator(Modifier.fillMaxWidth(), color = colors.brand, trackColor = colors.brandContainer)
        if (error) Text(stringResource(R.string.photo_error), style = MaterialTheme.typography.bodySmall, color = colors.danger)
    }
}

/**
 * Файл із галереї не йде на сервер як є: бакет публічний, а EXIF несе GPS і модель телефона.
 * Перекодування через bitmap лишає лише пікселі; заодно вкорочує довшу сторону до [MAX_SIDE].
 * Джерело — будь-яке зображення, яке декодує система (HEIC, AVIF з камери теж): на сервер однаково
 * йде JPEG. Ліміт розміру — до вже перекодованих байтів.
 */
private fun Context.readImage(uri: Uri): Pair<ByteArray, String> {
    require(contentResolver.getType(uri).orEmpty().startsWith("image/")) { "not an image" }
    val bitmap = decodeBounded(uri) ?: error("undecodable")
    val output = ByteArrayOutputStream()
    try {
        require(bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, output)) { "compress failed" }
    } finally { bitmap.recycle() }
    require(output.size() in 1..ImageRules.MAX_BYTES) { "too large" }
    return output.toByteArray() to "image/jpeg"
}

private fun Context.decodeBounded(uri: Uri): Bitmap? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        // ImageDecoder сам повертає кадр за EXIF-орієнтацією і не переносить метадані у bitmap.
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri)) { decoder, info, _ ->
            val longest = maxOf(info.size.width, info.size.height)
            if (longest > MAX_SIDE) {
                val scale = MAX_SIDE.toFloat() / longest
                decoder.setTargetSize((info.size.width * scale).toInt().coerceAtLeast(1), (info.size.height * scale).toInt().coerceAtLeast(1))
            }
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false
        }
    } else {
        // API 26–27: BitmapFactory. Грубо зменшуємо ще при декодуванні (inSampleSize), решту й поворот
        // з EXIF — однією матрицею. Самі метадані в bitmap не потрапляють.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }?.let { decoded ->
            val degrees = contentResolver.openInputStream(uri)?.use {
                when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
            } ?: 0f
            val scale = minOf(1f, MAX_SIDE.toFloat() / maxOf(decoded.width, decoded.height))
            if (degrees == 0f && scale == 1f) return@let decoded
            val matrix = Matrix().apply { postScale(scale, scale); postRotate(degrees) }
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true).also { if (it !== decoded) decoded.recycle() }
        }
    }

/** Довша сторона після перекодування: досить для картки й екрана деталей. */
private const val MAX_SIDE = 2048
private const val JPEG_QUALITY = 85
