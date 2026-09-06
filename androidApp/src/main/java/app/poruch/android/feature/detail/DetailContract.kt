package app.poruch.android.feature.detail

import app.poruch.domain.Attendee
import app.poruch.domain.Event

data class DetailState(
    val event: Event? = null,
    val attendees: List<Attendee> = emptyList(),
    val loading: Boolean = false,
    val mutating: Boolean = false,
    val signedIn: Boolean = false,
    val saved: Boolean = false,
    val waitlisted: Boolean = false,
    val organizer: Boolean = false,
    val confirmingCancel: Boolean = false
) {
    val cancelled get() = event?.isCancelled == true
    val full get() = event?.isFull == true

    /**
     * The one action the sticky bar offers. Deriving it here means the label, the tap and the
     * enabled state can never disagree — and the organizer is never offered a guest seat the
     * server would refuse.
     */
    val action: DetailAction
        get() = when {
            event == null -> DetailAction.NONE
            cancelled -> DetailAction.CANCELLED
            organizer -> DetailAction.ORGANIZER
            event.joined -> DetailAction.LEAVE
            waitlisted -> DetailAction.LEAVE_WAITLIST
            full -> DetailAction.JOIN_WAITLIST
            else -> DetailAction.JOIN
        }
}

enum class DetailAction {
    NONE, JOIN, LEAVE, JOIN_WAITLIST, LEAVE_WAITLIST,
    /** Shown to the organizer, who runs the event rather than attending it. */
    ORGANIZER,
    CANCELLED;

    val isEnabled get() = this == JOIN || this == LEAVE || this == JOIN_WAITLIST || this == LEAVE_WAITLIST
}

sealed interface DetailIntent {
    data object Load : DetailIntent
    data object Back : DetailIntent
    data object PrimaryAction : DetailIntent
    data object ToggleSaved : DetailIntent
    data object Share : DetailIntent
    data object AddToCalendar : DetailIntent
    data object OpenInMaps : DetailIntent
    data object Edit : DetailIntent
    data class ConfirmCancel(val open: Boolean) : DetailIntent
    data object CancelEvent : DetailIntent
    data class AttachPhoto(val bytes: ByteArray, val contentType: String) : DetailIntent {
        // Byte arrays are compared by identity by default, which would make two distinct picks
        // of the same file look like different intents. Data-class equality has to say so.
        override fun equals(other: Any?) = this === other ||
            (other is AttachPhoto && contentType == other.contentType && bytes.contentEquals(other.bytes))
        override fun hashCode() = 31 * bytes.contentHashCode() + contentType.hashCode()
    }
}

sealed interface DetailEffect {
    data object Back : DetailEffect
    data class Edit(val id: String) : DetailEffect
    data object RequireSignIn : DetailEffect
    data class ShareEvent(val event: Event) : DetailEffect
    data class OpenCalendar(val event: Event) : DetailEffect
    data class OpenMaps(val event: Event) : DetailEffect
}
