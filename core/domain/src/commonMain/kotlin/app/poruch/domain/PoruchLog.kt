package app.poruch.domain

enum class LogLevel { DEBUG, INFO, WARN, ERROR }

/**
 * Логування, вимкнене поза debug-збіркою. Тверде правило: паролі, токени й email сюди не
 * потрапляють, тіла запитів не логуються, ідентифікатори — лише короткі префікси.
 * Повідомлення — лямбди, щоб нічого не форматувалось, поки лог вимкнено.
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

/** Префікс id: досить, щоб простежити подію в трейсі, замало, щоб перелічити користувачів. */
fun String?.shortId(): String = when {
    this == null -> "none"
    length <= 8 -> this
    else -> take(8)
}
