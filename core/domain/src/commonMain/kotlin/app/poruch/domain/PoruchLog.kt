package app.poruch.domain

enum class LogLevel { DEBUG, INFO, WARN, ERROR }

/**
 * Tracing for the whole app, off unless a debug build turns it on.
 *
 * The one hard rule: credentials, tokens and email addresses never reach a sink. A log that leaks
 * them is worse than no log at all, so request bodies are never passed here and identifiers are
 * carried as short prefixes — enough to follow one event through a trace, not enough to be a
 * user list. Messages are lambdas so nothing is formatted while logging is off.
 */
object PoruchLog {
    var enabled: Boolean = false

    inline fun d(tag: String, message: () -> String) { if (enabled) platformLog(LogLevel.DEBUG, tag, message()) }
    inline fun i(tag: String, message: () -> String) { if (enabled) platformLog(LogLevel.INFO, tag, message()) }
    inline fun w(tag: String, message: () -> String) { if (enabled) platformLog(LogLevel.WARN, tag, message()) }
    inline fun e(tag: String, error: Throwable? = null, message: () -> String) {
        if (enabled) platformLog(LogLevel.ERROR, tag, message() + (error?.let { " · ${it::class.simpleName}: ${it.message}" } ?: ""))
    }
}

expect fun platformLog(level: LogLevel, tag: String, message: String)

/** Enough of an identifier to follow one event through a trace, not enough to enumerate users. */
fun String?.shortId(): String = when {
    this == null -> "none"
    length <= 8 -> this
    else -> take(8)
}
