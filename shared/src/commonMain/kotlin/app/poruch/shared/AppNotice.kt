package app.poruch.shared

import app.poruch.domain.AppError

/** Повідомлення для банера: іменоване, без тексту. Текст бере платформа зі своїх ресурсів. */
sealed interface AppNotice {
    /** Щоб банер обрав тон, не знаючи випадку. */
    val isError: Boolean

    data class Failed(val error: AppError) : AppNotice {
        override val isError get() = true
    }

    data class Told(val message: AppMessage) : AppNotice {
        override val isError get() = false
    }
}

/** Усе, що застосунок каже, коли все гаразд. */
enum class AppMessage {
    JOINED_EVENT, JOINED_WAITLIST, SIGNED_IN, ACCOUNT_CREATED, CONFIRM_EMAIL_FIRST,
    EVENT_PUBLISHED, CHANGES_SAVED, PHOTO_ADDED, RECOVERY_SENT, PASSWORD_CHANGED,
    SET_NEW_PASSWORD, EMAIL_CONFIRMED, ZOOM_IN_FOR_MORE,
    REQUEST_SENT, REPORT_SENT, USER_BLOCKED, AGE_CONFIRMED, ACCOUNT_DELETED, RATING_SENT
}
