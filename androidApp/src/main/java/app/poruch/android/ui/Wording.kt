package app.poruch.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.poruch.android.R
import app.poruch.domain.AppError
import app.poruch.domain.DraftField
import app.poruch.shared.AppMessage
import app.poruch.shared.AppNotice

/**
 * The one place that turns a named outcome into Ukrainian. Business logic reports cases; this maps
 * each case to a string resource, so a new language is a new `values-xx/strings.xml` and nothing else.
 */
@Composable
fun AppNotice.text(): String = when (this) {
    is AppNotice.Failed -> error.text()
    is AppNotice.Told -> stringResource(message.resource)
}

@Composable
fun AppError.text(): String = when (this) {
    // A rejected draft names its fields, so the message can point at them rather than at "the form".
    is AppError.InvalidDraft -> stringResource(
        R.string.err_invalid_draft,
        fields.map { stringResource(it.resource) }.joinToString()
    )
    else -> stringResource(resource)
}

private val AppError.resource: Int
    get() = when (this) {
        AppError.Network -> R.string.err_network
        AppError.NotConfigured -> R.string.err_not_configured
        AppError.ServiceUnavailable -> R.string.err_service
        AppError.Rejected -> R.string.err_rejected
        AppError.TooManyAttempts -> R.string.err_too_many
        AppError.SessionRequired -> R.string.err_session_required
        AppError.InvalidCredentials -> R.string.err_invalid_credentials
        AppError.EmailNotConfirmed -> R.string.err_email_not_confirmed
        AppError.NotOwner -> R.string.err_not_owner
        AppError.EventUnavailable -> R.string.err_event_unavailable
        AppError.EventCancelled -> R.string.err_event_cancelled
        AppError.EventFull -> R.string.err_event_full
        AppError.AlreadyMember -> R.string.err_already_member
        AppError.OrganizerCannotJoin -> R.string.err_organizer_cannot_join
        AppError.EventHasSpace -> R.string.err_event_has_space
        AppError.ImageUploadFailed -> R.string.err_image_upload
        AppError.InvalidEmail -> R.string.err_invalid_email
        AppError.InvalidName -> R.string.err_invalid_name
        AppError.WeakPassword -> R.string.err_weak_password
        is AppError.InvalidDraft -> R.string.err_rejected
    }

private val DraftField.resource: Int
    get() = when (this) {
        DraftField.TITLE -> R.string.field_title
        DraftField.DESCRIPTION -> R.string.field_description
        DraftField.CATEGORY -> R.string.field_category
        DraftField.ADDRESS -> R.string.field_address
        DraftField.LOCATION -> R.string.field_location
        DraftField.CAPACITY -> R.string.field_capacity
        DraftField.STARTS_AT -> R.string.field_starts_at
        DraftField.ENDS_AT -> R.string.field_ends_at
        DraftField.TIME_ZONE -> R.string.field_time_zone
        DraftField.IMAGE_URL -> R.string.field_image_url
    }

private val AppMessage.resource: Int
    get() = when (this) {
        AppMessage.JOINED_EVENT -> R.string.msg_joined_event
        AppMessage.JOINED_WAITLIST -> R.string.msg_joined_waitlist
        AppMessage.SIGNED_IN -> R.string.msg_signed_in
        AppMessage.ACCOUNT_CREATED -> R.string.msg_account_created
        AppMessage.CONFIRM_EMAIL_FIRST -> R.string.msg_confirm_email_first
        AppMessage.EVENT_PUBLISHED -> R.string.msg_event_published
        AppMessage.CHANGES_SAVED -> R.string.msg_changes_saved
        AppMessage.PHOTO_ADDED -> R.string.msg_photo_added
        AppMessage.RECOVERY_SENT -> R.string.msg_recovery_sent
        AppMessage.PASSWORD_CHANGED -> R.string.msg_password_changed
        AppMessage.SET_NEW_PASSWORD -> R.string.msg_set_new_password
        AppMessage.EMAIL_CONFIRMED -> R.string.msg_email_confirmed
        AppMessage.ZOOM_IN_FOR_MORE -> R.string.msg_zoom_in
    }
