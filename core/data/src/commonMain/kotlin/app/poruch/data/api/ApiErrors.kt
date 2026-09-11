package app.poruch.data.api

import app.poruch.domain.*
import kotlinx.serialization.json.*

/**
 * Maps a PostgREST / GoTrue failure onto a domain case. The server signals with codes and
 * `raise exception 'NAME'`, so the match is on those, never on wording — and nothing user-facing
 * is decided here.
 *
 * Живе окремо від транспорту свідомо: це словник між двома системами, і росте він разом із
 * серверними правилами, а не з тим, як ми ходимо в мережу.
 */
internal fun apiFailure(status: Int, body: String): AppFailure {
    val lower = body.lowercase()
    val error = when {
        // The safety cases come first: several of them arrive as a 403, which the generic rules
        // below would flatten into «not the owner».
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
    // Код сервера їде поруч із доменною помилкою, але не замість неї: за ним клієнт вирішує
    // питання сумісності (чи знає ця база потрібну функцію), а не що написати людині.
    return AppFailure(error, serverCode(body))
}

/** `{"code":"PGRST202", ...}` — усе, що нас тут цікавить. */
private fun serverCode(body: String): String? =
    runCatching { Json.parseToJsonElement(body).jsonObject["code"]?.jsonPrimitive?.contentOrNull }.getOrNull()

internal fun JsonObject.string(key: String) = this[key]?.jsonPrimitive?.contentOrNull.orEmpty()
