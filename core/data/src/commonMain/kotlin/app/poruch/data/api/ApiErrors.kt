package app.poruch.data.api

import app.poruch.domain.*
import kotlinx.serialization.json.*

/**
 * Перекладає відмову PostgREST / GoTrue в доменну помилку. Збігаємо точні імена з
 * `raise exception 'NAME'` (поле `message` PostgREST) і `error_code` GoTrue, а не підрядки:
 * `"capacity" in body` колись робило з CAPACITY_BELOW_ATTENDANCE «Подія заповнена».
 * Окремо від транспорту, бо росте разом із серверними правилами.
 */
internal fun apiFailure(status: Int, body: String): AppFailure {
    val parsed = runCatching { Json.parseToJsonElement(body).jsonObject }.getOrNull()
    val name = parsed?.string("message")?.trim()?.uppercase()
    val authCode = parsed?.string("error_code")?.takeIf { it.isNotEmpty() } ?: parsed?.string("error")
    // Старі відповіді GoTrue без `error_code` мають лише текст.
    val authText = (parsed?.string("msg")?.takeIf { it.isNotEmpty() } ?: parsed?.string("error_description")).orEmpty().lowercase()
    val error = SERVER_ERRORS[name] ?: AUTH_ERRORS[authCode] ?: when {
        "invalid login" in authText -> AppError.InvalidCredentials
        "email not confirmed" in authText -> AppError.EmailNotConfirmed
        "different from the old password" in authText -> AppError.SamePassword
        status == 401 -> AppError.SessionRequired
        status == 403 -> AppError.NotOwner
        status == 429 -> AppError.TooManyAttempts
        status in 400..499 -> AppError.Rejected
        else -> AppError.ServiceUnavailable
    }
    // Код сервера потрібен для сумісності (чи знає база функцію), а не для тексту людині.
    return AppFailure(error, authCode?.takeIf { it.isNotEmpty() } ?: serverCode(parsed))
}

/** Імена з `raise exception` у міграціях. Невідоме ім'я падає до статусу. */
private val SERVER_ERRORS: Map<String, AppError> = mapOf(
    "AUTH_REQUIRED" to AppError.SessionRequired,
    "AGE_REQUIRED" to AppError.AgeRequired,
    "TOO_YOUNG" to AppError.TooYoung,
    "TOO_OLD" to AppError.TooOld,
    "UNDERAGE" to AppError.Underage,
    "AGE_ALREADY_SET" to AppError.AgeAlreadySet,
    "ACCOUNT_RESTRICTED" to AppError.AccountRestricted,
    "BLOCKED" to AppError.Blocked,
    "TOO_MANY_REPORTS" to AppError.TooManyReports,
    "TOO_MANY_EVENTS" to AppError.TooManyEvents,
    "TOO_MANY_MESSAGES" to AppError.TooManyMessages,
    "TOO_MANY_JOINS" to AppError.TooManyAttempts,
    "INVALID_MESSAGE" to AppError.InvalidMessage,
    "OBJECTIONABLE_CONTENT" to AppError.ObjectionableContent,
    "CHAT_CLOSED" to AppError.ChatClosed,
    "NOT_MEMBER" to AppError.NotMember,
    "INVALID_TITLE" to AppError.InvalidDraft(listOf(DraftField.TITLE)),
    "INVALID_DESCRIPTION" to AppError.InvalidDraft(listOf(DraftField.DESCRIPTION)),
    "INVALID_AGE_LIMIT" to AppError.InvalidDraft(listOf(DraftField.AGE_LIMITS)),
    "INVALID_CONTACT_URL" to AppError.InvalidDraft(listOf(DraftField.CONTACT_URL)),
    "ORGANIZER_CANNOT_JOIN" to AppError.OrganizerCannotJoin,
    "ALREADY_MEMBER" to AppError.AlreadyMember,
    "EVENT_HAS_SPACE" to AppError.EventHasSpace,
    "EVENT_FULL" to AppError.EventFull,
    "CAPACITY_BELOW_ATTENDANCE" to AppError.CapacityBelowAttendance,
    "EVENT_CANCELLED" to AppError.EventCancelled,
    "EVENT_NOT_FOUND" to AppError.EventUnavailable,
    "NOT_ORGANIZER" to AppError.NotOwner
)

/** `error_code` GoTrue. */
private val AUTH_ERRORS: Map<String?, AppError> = mapOf(
    "invalid_credentials" to AppError.InvalidCredentials,
    "email_not_confirmed" to AppError.EmailNotConfirmed,
    "same_password" to AppError.SamePassword,
    "over_request_rate_limit" to AppError.TooManyAttempts,
    "over_email_send_rate_limit" to AppError.TooManyAttempts,
    // PKCE: код прострочено або вже обміняно.
    "flow_state_expired" to AppError.LinkExpired,
    "flow_state_not_found" to AppError.LinkExpired,
    "otp_expired" to AppError.LinkExpired
)

/** Витягає `code` з тіла відповіді, напр. `PGRST202`. */
private fun serverCode(body: JsonObject?): String? = body?.get("code")?.jsonPrimitive?.contentOrNull

internal fun JsonObject.string(key: String) = this[key]?.jsonPrimitive?.contentOrNull.orEmpty()
