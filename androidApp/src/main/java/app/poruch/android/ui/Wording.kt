package app.poruch.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import app.poruch.android.R
import app.poruch.domain.AppError
import app.poruch.domain.DraftField
import app.poruch.domain.EventRules
import app.poruch.domain.ImageRules
import app.poruch.domain.ReportReason
import app.poruch.domain.SafetyRules
import app.poruch.shared.AppMessage
import app.poruch.shared.AppNotice

/** Єдине місце, де іменований випадок стає текстом: нова мова — новий `values-xx/strings.xml`. */
@Composable
fun AppNotice.text(): String = when (this) {
    is AppNotice.Failed -> error.text()
    is AppNotice.Told -> stringResource(message.resource)
}

@Composable
fun AppError.text(): String = when (this) {
    // Відхилена чернетка називає поля, тож повідомлення каже правило кожного.
    is AppError.InvalidDraft -> fields.map { it.rule() }.joinToString(". ")
    // Мінімальний вік показуємо числом.
    AppError.Underage -> stringResource(R.string.err_underage, SafetyRules.MIN_SIGNUP_AGE)
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
        AppError.LinkOnAnotherDevice -> R.string.err_link_other_device
        AppError.LinkExpired -> R.string.err_link_expired
        AppError.NotOwner -> R.string.err_not_owner
        AppError.EventUnavailable -> R.string.err_event_unavailable
        AppError.EventCancelled -> R.string.err_event_cancelled
        AppError.EventFull -> R.string.err_event_full
        AppError.AlreadyMember -> R.string.err_already_member
        AppError.OrganizerCannotJoin -> R.string.err_organizer_cannot_join
        AppError.EventHasSpace -> R.string.err_event_has_space
        AppError.CapacityBelowAttendance -> R.string.err_capacity_below_attendance
        AppError.ImageUploadFailed -> R.string.err_image_upload
        AppError.InvalidEmail -> R.string.err_invalid_email
        AppError.InvalidName -> R.string.err_invalid_name
        AppError.WeakPassword -> R.string.err_weak_password
        AppError.SamePassword -> R.string.err_same_password
        AppError.AgeRequired -> R.string.err_age_required
        AppError.TooYoung -> R.string.err_too_young
        AppError.TooOld -> R.string.err_too_old
        AppError.Blocked -> R.string.err_blocked
        AppError.AccountRestricted -> R.string.err_account_restricted
        AppError.AgeAlreadySet -> R.string.err_age_already_set
        AppError.Underage -> R.string.err_underage
        AppError.TooManyReports -> R.string.err_too_many_reports
        AppError.TooManyEvents -> R.string.err_too_many_events
        AppError.NotMember -> R.string.err_not_member
        AppError.ChatClosed -> R.string.err_chat_closed
        AppError.TooManyMessages -> R.string.err_too_many_messages
        AppError.InvalidMessage -> R.string.err_invalid_message
        AppError.ObjectionableContent -> R.string.err_objectionable
        is AppError.InvalidDraft -> R.string.err_rejected
    }

/**
 * Правило поля чернетки людськими словами, з межами з [EventRules]. Довжину згори тримає саме
 * поле введення, тож для назви й опису лишається сказати лише про мінімум.
 */
@Composable
fun DraftField.rule(): String = when (this) {
    DraftField.TITLE -> EventRules.titleLength.first.let { pluralStringResource(R.plurals.field_title, it, it) }
    DraftField.DESCRIPTION -> EventRules.descriptionLength.first.let { pluralStringResource(R.plurals.field_description, it, it) }
    DraftField.CATEGORY -> stringResource(R.string.field_category)
    DraftField.ADDRESS -> stringResource(R.string.field_address)
    DraftField.LOCATION -> stringResource(R.string.field_location)
    DraftField.CAPACITY -> stringResource(R.string.field_capacity, EventRules.capacity.first, EventRules.capacity.last)
    DraftField.STARTS_AT -> stringResource(R.string.field_starts_at)
    DraftField.ENDS_AT -> stringResource(R.string.field_ends_at)
    DraftField.TIME_ZONE -> stringResource(R.string.field_time_zone)
    DraftField.IMAGE_URL -> stringResource(R.string.field_image_url, ImageRules.MAX_BYTES / (1024 * 1024))
    DraftField.AGE_LIMITS -> stringResource(R.string.field_age_limits, SafetyRules.MIN_SIGNUP_AGE, SafetyRules.MAX_AGE_LIMIT)
    DraftField.CONTACT_URL -> stringResource(R.string.field_contact_url)
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
        AppMessage.REQUEST_SENT -> R.string.msg_request_sent
        AppMessage.REPORT_SENT -> R.string.msg_report_sent
        AppMessage.RATING_SENT -> R.string.msg_rating_sent
        AppMessage.USER_BLOCKED -> R.string.msg_user_blocked
        AppMessage.AGE_CONFIRMED -> R.string.msg_age_confirmed
        AppMessage.ACCOUNT_DELETED -> R.string.msg_account_deleted
    }

/** Причини скарги в порядку шторки. */
val reportReasons = listOf(
    ReportReason.MINORS to R.string.reason_minors,
    ReportReason.SAFETY to R.string.reason_safety,
    ReportReason.HARASSMENT to R.string.reason_harassment,
    ReportReason.SCAM to R.string.reason_scam,
    ReportReason.SPAM to R.string.reason_spam,
    ReportReason.OTHER to R.string.reason_other
)
