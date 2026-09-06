package app.poruch.domain

import platform.Foundation.NSLog

actual fun platformLog(level: LogLevel, tag: String, message: String) {
    NSLog("%s", "[${level.name}] Poruch/$tag $message")
}
