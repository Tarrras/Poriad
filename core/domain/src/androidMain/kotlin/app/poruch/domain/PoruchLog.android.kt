package app.poruch.domain

import android.util.Log

actual fun platformLog(level: LogLevel, tag: String, message: String) {
    val full = "Poruch/$tag"
    when (level) {
        LogLevel.DEBUG -> Log.d(full, message)
        LogLevel.INFO -> Log.i(full, message)
        LogLevel.WARN -> Log.w(full, message)
        LogLevel.ERROR -> Log.e(full, message)
    }
}
