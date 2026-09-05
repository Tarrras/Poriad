package app.poruch.android

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.domain.Event
import app.poruch.shared.PoruchApp
import coil3.compose.AsyncImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable fun EventPhoto(event: Event, app: PoruchApp?, editable: Boolean = false, busy: Boolean = false) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    var reading by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            reading = true
            runCatching {
                withContext(Dispatchers.IO) {
                    val mime = context.contentResolver.getType(uri).orEmpty()
                    require(mime in listOf("image/jpeg", "image/png", "image/webp"))
                    val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) { val count = input.read(buffer); if (count < 0) break; output.write(buffer, 0, count); require(output.size() <= 5 * 1024 * 1024) }
                        output.toByteArray() } ?: error("Unreadable image")
                    require(bytes.isNotEmpty() && bytes.size <= 5 * 1024 * 1024)
                    bytes to mime
                }
            }.onSuccess { (bytes, mime) -> error = null; app?.uploadEventImage(event.id, bytes, mime) }
                .onFailure { error = context.getString(R.string.photo_error) }
            reading = false
        }
    }
    if (event.imageUrl != null) {
        var imageFailed by remember(event.imageUrl) { mutableStateOf(false) }
        AsyncImage(model = event.imageUrl, contentDescription = event.title, contentScale = ContentScale.Crop, onError = { imageFailed = true }, modifier = Modifier.fillMaxWidth().height(200.dp))
        if (imageFailed) Text(stringResource(R.string.photo_load_error), style = MaterialTheme.typography.bodySmall)
    }
    if (editable) OutlinedButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !busy && !reading) { Text(stringResource(R.string.add_photo)) }
    if (reading) LinearProgressIndicator(Modifier.fillMaxWidth())
    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
}
