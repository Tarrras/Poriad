package app.poruch.domain

import kotlinx.serialization.SerializationException

enum class LogLevel { DEBUG, INFO, WARN, ERROR }

/**
 * Логування, вимкнене поза debug-збіркою. Тверде правило: паролі, токени й email сюди не
 * потрапляють, тіла запитів не логуються, ідентифікатори — лише короткі префікси.
 * Повідомлення — лямбди, щоб нічого не форматувалось, поки лог вимкнено.
 */
object PoruchLog {
    var enabled: Boolean = false

    /**
     * Хлібні крихти для звітів про збої (Crashlytics `log`) у будь-якій збірці: i/w/e ідуть сюди, щоб
     * у звіті було видно кроки перед ним. Правило приватності те саме, що й для логу. Ставить платформа.
     */
    var breadcrumbs: ((String) -> Unit)? = null

    /**
     * Non-fatal у Crashlytics. [issue] — стабільна назва проблеми без id і текстів: за нею звіти
     * групуються. [error] — виняток, якщо він є: платформа бере з нього стек, а текст — лише [summary].
     */
    var reporter: ((issue: String, error: Throwable?) -> Unit)? = null

    inline fun d(tag: String, message: () -> String) { if (enabled) platformLog(LogLevel.DEBUG, tag, message()) }
    inline fun i(tag: String, message: () -> String) { if (enabled || breadcrumbs != null) write(LogLevel.INFO, tag, message()) }
    inline fun w(tag: String, message: () -> String) { if (enabled || breadcrumbs != null) write(LogLevel.WARN, tag, message()) }
    inline fun e(tag: String, error: Throwable? = null, message: () -> String) {
        // Лише клас: `message` винятків Ktor несе повний URL з uuid і адресами.
        if (enabled || breadcrumbs != null) write(LogLevel.ERROR, tag, message() + (error?.let { " · ${it::class.simpleName}" } ?: ""))
    }

    /**
     * Збій, якого не мало бути: баг у нас або розбіжність із сервером. Очікувані відмови (нема мережі,
     * подія заповнена, сесія скінчилась) сюди не йдуть — вони не лагодяться кодом.
     */
    fun report(tag: String, issue: String, error: Throwable? = null) {
        e(tag, error) { issue }
        reporter?.invoke("$tag: $issue", error)
    }

    @PublishedApi internal fun write(level: LogLevel, tag: String, message: String) {
        if (enabled) platformLog(level, tag, message)
        breadcrumbs?.invoke("${level.name.first()}/$tag $message")
    }
}

expect fun platformLog(level: LogLevel, tag: String, message: String)

/** Префікс id: досить, щоб простежити подію в трейсі, замало, щоб перелічити користувачів. */
fun String?.shortId(): String = when {
    this == null -> "none"
    length <= 8 -> this
    else -> take(8)
}

/**
 * Що про виняток можна віддати назовні: клас, а для розбору JSON — ще й суть («поле X відсутнє»),
 * без самого JSON, у якому бувають чужі імена й тексти. Решта `message` не йде: у Ktor там URL з id.
 */
fun Throwable.summary(): String {
    val name = this::class.simpleName ?: "Throwable"
    val detail = (this as? SerializationException)?.message?.substringBefore("JSON input")?.trim()?.take(300)
    return if (detail.isNullOrEmpty()) name else "$name: $detail"
}
