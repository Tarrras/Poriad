package app.poruch.data.api

import app.poruch.domain.*
import kotlinx.serialization.json.*

/**
 * Перекладає відмову PostgREST / GoTrue в доменну помилку. Збігаємо коди й імена з
 * `raise exception 'NAME'`, а не текст. Окремо від транспорту, бо росте разом із серверними правилами.
 */
internal fun apiFailure(status: Int, body: String): AppFailure {
    val lower = body.lowercase()
    val error = when {
        // Випадки безпеки першими: кілька з них приходять як 403, який нижче став би «не власник».
        "age_required" in lower -> AppError.AgeRequired
        "too_young" in lower -> AppError.TooYoung
        "too_old" in lower -> AppError.TooOld
        "underage" in lower -> AppError.Underage
        "age_already_set" in lower -> AppError.AgeAlreadySet
        "account_restricted" in lower -> AppError.AccountRestricted
        "blocked" in lower -> AppError.Blocked
        "too_many_reports" in lower -> AppError.TooManyReports
        "too_many_events" in lower -> AppError.TooManyEvents
        "invalid_age_limit" in lower -> AppError.InvalidDraft(listOf(DraftField.AGE_LIMITS))
        "invalid_contact_url" in lower -> AppError.InvalidDraft(listOf(DraftField.CONTACT_URL))
        "organizer_cannot_join" in lower -> AppError.OrganizerCannotJoin
        "already_member" in lower -> AppError.AlreadyMember
        "event_has_space" in lower -> AppError.EventHasSpace
        "full" in lower || "capacity" in lower -> AppError.EventFull
        "cancelled" in lower || "canceled" in lower -> AppError.EventCancelled
        "not_organizer" in lower -> AppError.NotOwner
        "invalid login" in lower -> AppError.InvalidCredentials
        "email not confirmed" in lower -> AppError.EmailNotConfirmed
        status == 401 -> AppError.SessionRequired
        status == 403 -> AppError.NotOwner
        status == 429 -> AppError.TooManyAttempts
        status in 400..499 -> AppError.Rejected
        else -> AppError.ServiceUnavailable
    }
    // Код сервера потрібен для сумісності (чи знає база функцію), а не для тексту людині.
    return AppFailure(error, serverCode(body))
}

/** Витягає `code` з тіла відповіді, напр. `PGRST202`. */
private fun serverCode(body: String): String? =
    runCatching { Json.parseToJsonElement(body).jsonObject["code"]?.jsonPrimitive?.contentOrNull }.getOrNull()

internal fun JsonObject.string(key: String) = this[key]?.jsonPrimitive?.contentOrNull.orEmpty()
