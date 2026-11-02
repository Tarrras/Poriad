package app.poruch.domain

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSData
import platform.posix.memcpy

/**
 * Байти `Data` зі Swift одним `memcpy`: побайтове копіювання через міст на відео у 8 МБ — мільйони викликів. Для
 * `MediaBytes.read` на iOS (фото й відео чернетки) і аватара.
 */
@OptIn(ExperimentalForeignApi::class)
fun bytesOf(data: NSData): ByteArray {
    val bytes = ByteArray(data.length.toInt())
    if (bytes.isNotEmpty()) bytes.usePinned { memcpy(it.addressOf(0), data.bytes, data.length) }
    return bytes
}
