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
    val confirmingCancel: Boolean = false,
    /** People asking to come. Only ever non-empty for the organizer of this event. */
    val requests: List<Attendee> = emptyList(),
    val reporting: ReportTarget? = null,
    val confirmingBlock: Boolean = false
) {
    val cancelled get() = event?.isCancelled == true

    /** Кімната цієї події, якщо вона взагалі кімната. Місця й участь питають тільки в неї. */
    val room get() = event?.gathering

    /** Оголошення, якщо це афіша. Тоді дій рівно одна — вийти на джерело. */
    val listing get() = event?.listing

    val full get() = room?.isFull == true

    /**
     * The one action the sticky bar offers. Deriving it here means the label, the tap and the
     * enabled state can never disagree — and the organizer is never offered a guest seat the
     * server would refuse.
     *
     * Афіша відгалужується першою й ніколи не доходить до участі. Це не дублювання серверного
     * `assert_can_join`, а його наслідок: кнопка «приєднатися», яка гарантовано отримає
     * `IMPORTED_EVENT`, гірша за відсутність кнопки.
     */
    val action: DetailAction
        get() = when {
            event == null -> DetailAction.NONE
            cancelled -> DetailAction.CANCELLED
            listing != null ->
                if (listing!!.isWithdrawn || !listing!!.hasSource) DetailAction.NONE else DetailAction.TICKETS
            organizer -> DetailAction.ORGANIZER
            // Ні кімнати, ні оголошення — зіпсований рядок. Показуємо подію, не пропонуємо дій.
            room == null -> DetailAction.NONE
            room!!.awaitingApproval -> DetailAction.REQUESTED
            room!!.joined -> DetailAction.LEAVE
            waitlisted -> DetailAction.LEAVE_WAITLIST
            room!!.approvalRequired -> DetailAction.REQUEST
            full -> DetailAction.JOIN_WAITLIST
            else -> DetailAction.JOIN
        }
}

enum class DetailAction {
    /** Немає що запропонувати: афіша без посилання, знята подія або зіпсований рядок. Кнопки теж немає. */
    NONE,
    JOIN, LEAVE, JOIN_WAITLIST, LEAVE_WAITLIST,
    /** Афіша: єдина дія — сторінка джерела, де її продають і де лежить повний опис. */
    TICKETS,
    /** This event vets its guests, so the button asks rather than takes a seat. */
    REQUEST,
    /** Asked, and waiting: a state of its own, because «Приєднатися» here would be a lie. */
    REQUESTED,
    /** Shown to the organizer, who runs the event rather than attending it. */
    ORGANIZER,
    CANCELLED;

    val isEnabled get() = this == JOIN || this == LEAVE || this == JOIN_WAITLIST ||
        this == LEAVE_WAITLIST || this == REQUEST || this == TICKETS
}

/** What a report is about: the event in front of the reader, or the person who published it. */
enum class ReportTarget { EVENT, ORGANIZER }

sealed interface DetailIntent {
    data object Load : DetailIntent
    data object Back : DetailIntent
    data object PrimaryAction : DetailIntent
    data object ToggleSaved : DetailIntent
    data object Share : DetailIntent
    data object AddToCalendar : DetailIntent
    data object OpenInMaps : DetailIntent
    /** Тап у міні-мапу: та сама подія, але на великій мапі поруч з усім, що є навколо. */
    data object OpenMap : DetailIntent
    /** «Читати повністю на джерелі» — те саме посилання, але з-під опису, а не з-під кнопки. */
    data object OpenSource : DetailIntent
    data object Edit : DetailIntent
    data class ConfirmCancel(val open: Boolean) : DetailIntent
    data class ShowReport(val target: ReportTarget?) : DetailIntent
    data class SendReport(val reason: String, val details: String) : DetailIntent
    data class ConfirmBlock(val open: Boolean) : DetailIntent
    data object BlockOrganizer : DetailIntent
    data class ApproveRequest(val userId: String) : DetailIntent
    data class DeclineRequest(val userId: String) : DetailIntent
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
    /** Сторінка джерела афіші. Виходить у браузер, бо всередині нам її показувати нічим. */
    data class OpenLink(val url: String) : DetailEffect
    /** Наша власна мапа, наведена на цю подію. */
    data class OpenMap(val id: String) : DetailEffect
}
