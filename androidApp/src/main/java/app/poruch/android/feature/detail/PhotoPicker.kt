package app.poruch.android.feature.detail

import android.content.Context
import android.net.Uri
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

/**
 * Reading the picked file is Android's job, not the store's: this hands the bytes over as an
 * intent. The size ceiling is checked while reading so an oversized pick never reaches memory
 * whole, let alone the network.
 */
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

private fun Context.readImage(uri: Uri): Pair<ByteArray, String> {
    val mime = contentResolver.getType(uri).orEmpty()
    require(mime in ImageRules.extensions) { "unsupported type" }
    val bytes = contentResolver.openInputStream(uri)?.use { input ->
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(READ_CHUNK)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            output.write(buffer, 0, count)
            require(output.size() <= ImageRules.MAX_BYTES) { "too large" }
        }
        output.toByteArray()
    } ?: error("unreadable")
    require(bytes.isNotEmpty()) { "empty" }
    return bytes to mime
}

private const val READ_CHUNK = 8192
