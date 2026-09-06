package app.poruch.domain

actual fun platformLog(level: LogLevel, tag: String, message: String) {
    println("[${level.name}] Poruch/$tag $message")
}
