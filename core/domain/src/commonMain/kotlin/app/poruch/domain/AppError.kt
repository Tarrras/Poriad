package app.poruch.domain

/**
 * Every failure the app can report, named rather than worded.
 *
 * Business logic decides *which* case happened; presentation decides how to say it, from the
 * platform's own string resources. That keeps user-facing language — and its translations — out
 * of `core` and `feature`, and lets a screen react to a case (offer registration, open the queue)
 * instead of matching on a message.
 */
sealed interface AppError {
    /** The request never reached an answer: no network, DNS, TLS or a dropped connection. */
    data object Network : AppError
    /** The build has no Supabase key: a packaging mistake, not a user error. */
    data object NotConfigured : AppError
    /** The service answered, but not with anything we can act on. */
    data object ServiceUnavailable : AppError
    /** A 4xx we cannot name more precisely. */
    data object Rejected : AppError
    data object TooManyAttempts : AppError

    // ---- session
    data object SessionRequired : AppError
    data object InvalidCredentials : AppError
    data object EmailNotConfirmed : AppError
    data object NotOwner : AppError

    // ---- events
    data object EventUnavailable : AppError
    data object EventCancelled : AppError
    data object EventFull : AppError
    data object AlreadyMember : AppError
    data object OrganizerCannotJoin : AppError
    /** Asked for the queue on an event that has free places — join instead. */
    data object EventHasSpace : AppError
    data object ImageUploadFailed : AppError

    // ---- input
    data class InvalidDraft(val fields: List<DraftField>) : AppError
    data object InvalidEmail : AppError
    data object InvalidName : AppError
    data object WeakPassword : AppError
}

/** The fields [EventDraft.validate] can reject, so a screen can highlight the right one. */
enum class DraftField { TITLE, DESCRIPTION, CATEGORY, ADDRESS, LOCATION, CAPACITY, STARTS_AT, ENDS_AT, TIME_ZONE, IMAGE_URL }

/**
 * The only throwable this app raises. It exists because suspend functions still need a way to
 * unwind; the payload that matters is [error], and every handler matches on that.
 */
class AppFailure(val error: AppError) : Exception(error.toString())

/** Reads the typed error out of any throwable; anything foreign is a service problem to the user. */
fun Throwable.asAppError(): AppError = (this as? AppFailure)?.error ?: AppError.ServiceUnavailable

/** Shorthand for the throw sites, which read better as `fail(AppError.EventFull)`. */
fun fail(error: AppError): Nothing = throw AppFailure(error)
