package app.poruch.android.feature.detail

import app.poruch.domain.Attendee
import app.poruch.domain.Event
import app.poruch.domain.EventSession

data class DetailState(
    val event: Event? = null,
    /** Сеанси прокату для каруселі. Менше двох — каруселі нема. */
    val sessions: List<EventSession> = emptyList(),
    /** Сеанс на екрані: з яким відкрили або обраний у каруселі. */
    val sessionId: String = "",
    /** Сеанс прокату вже почався: показати можна, купити квиток — ні. Тижневої виставки не стосується. */
    val sessionStarted: Boolean = false,
    val attendees: List<Attendee> = emptyList(),
    val loading: Boolean = false,
    /** Потяг вниз у дорозі. */
    val refreshing: Boolean = false,
    val mutating: Boolean = false,
    val signedIn: Boolean = false,
    val saved: Boolean = false,
    val waitlisted: Boolean = false,
    val organizer: Boolean = false,
    val confirmingCancel: Boolean = false,
    /** Хто проситься. Непорожньо лише для організатора. */
    val requests: List<Attendee> = emptyList(),
    val reporting: ReportTarget? = null,
    val confirmingBlock: Boolean = false,
    /** Попередження перед виходом у чужий чат: спершу кажемо, куди й хто це додав. */
    val confirmingContact: Boolean = false
) {
    val cancelled get() = event?.isCancelled == true

    /** Кімната, якщо це кімната. Місця й участь лише в неї. */
    val room get() = event?.gathering

    /** Оголошення, якщо це афіша. Тоді дія одна: вийти на джерело. */
    val listing get() = event?.listing

    val full get() = room?.isFull == true

    /** Чат є для своїх: організатора й підтверджених. Скасована подія лишає його для читання. */
    val hasChat get() = room != null && (organizer || room!!.joined)

    /**
     * Єдина дія нижньої панелі. Рахується тут, щоб підпис, тап і доступність не розходились.
     * Афіша відгалужується першою: кнопка «приєднатися», яка гарантовано отримає відмову, гірша за відсутність кнопки.
     */
    val action: DetailAction
        get() = when {
            event == null -> DetailAction.NONE
            cancelled -> DetailAction.CANCELLED
            listing != null ->
                if (listing!!.isWithdrawn || !listing!!.hasSource || sessionStarted) DetailAction.NONE
                else DetailAction.TICKETS
            organizer -> DetailAction.ORGANIZER
            // Ні кімнати, ні оголошення — зіпсований рядок: без дій.
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
    /** Кнопки нема: афіша без посилання, знята подія або зіпсований рядок. */
    NONE,
    JOIN, LEAVE, JOIN_WAITLIST, LEAVE_WAITLIST,
    /** Афіша: сторінка джерела. */
    TICKETS,
    /** Подія з підтвердженням: кнопка просить, а не бере місце. */
    REQUEST,
    /** Запит надіслано, чекаємо. */
    REQUESTED,
    /** Для організатора. */
    ORGANIZER,
    CANCELLED;

    val isEnabled get() = this == JOIN || this == LEAVE || this == JOIN_WAITLIST ||
        this == LEAVE_WAITLIST || this == REQUEST || this == TICKETS
}

/** На що скарга: на подію чи на того, хто її опублікував. */
enum class ReportTarget { EVENT, ORGANIZER }

sealed interface DetailIntent {
    data object Back : DetailIntent
    /** Відповідь системи на [DetailEffect.AskNotificationPermission]. */
    data class NotificationPermissionAnswered(val granted: Boolean) : DetailIntent
    /** Потяг вниз: перечитати місця, членство й запити. */
    data object Refresh : DetailIntent
    /** Інша дата в каруселі прокату. */
    data class PickSession(val id: String) : DetailIntent
    data object PrimaryAction : DetailIntent
    data object ToggleSaved : DetailIntent
    data object Share : DetailIntent
    data object AddToCalendar : DetailIntent
    data object OpenInMaps : DetailIntent
    /** Тап у міні-мапу: та сама подія на великій мапі. */
    data object OpenMap : DetailIntent
    /** «Читати повністю на джерелі»: те саме посилання з-під опису. */
    data object OpenSource : DetailIntent
    data object Edit : DetailIntent
    data class ConfirmCancel(val open: Boolean) : DetailIntent
    data class ShowReport(val target: ReportTarget?) : DetailIntent
    /** Ціль їде всередині: шторка спершу закривається (і скидає [DetailState.reporting]), а вже потім шле це. */
    data class SendReport(val target: ReportTarget, val reason: String, val details: String) : DetailIntent
    data class ConfirmBlock(val open: Boolean) : DetailIntent
    data object BlockOrganizer : DetailIntent
    /** Відкрити чат учасників: спершу попередження, потім браузер. */
    data class ConfirmContact(val open: Boolean) : DetailIntent
    data object OpenContact : DetailIntent
    /** Чат події всередині застосунку. */
    data object OpenChat : DetailIntent
    data class ApproveRequest(val userId: String) : DetailIntent
    data class DeclineRequest(val userId: String) : DetailIntent
    data object CancelEvent : DetailIntent
    data class AttachPhoto(val bytes: ByteArray, val contentType: String) : DetailIntent {
        // Масиви байтів порівнюються за посиланням: два вибори того самого файлу — різні інтенти.
        override fun equals(other: Any?) = this === other ||
            (other is AttachPhoto && contentType == other.contentType && bytes.contentEquals(other.bytes))
        override fun hashCode() = 31 * bytes.contentHashCode() + contentType.hashCode()
    }
}

sealed interface DetailEffect {
    data object Back : DetailEffect
    data class Edit(val id: String) : DetailEffect
    data object RequireSignIn : DetailEffect
    /** Приєднались, а нагадування ще не ввімкнені: питаємо дозвіл системи, маршрут повертає відповідь у [DetailIntent.NotificationPermissionAnswered]. */
    data object AskNotificationPermission : DetailEffect
    data class ShareEvent(val event: Event) : DetailEffect
    data class OpenCalendar(val event: Event) : DetailEffect
    data class OpenMaps(val event: Event) : DetailEffect
    /** Сторінка джерела афіші в браузері. */
    data class OpenLink(val url: String) : DetailEffect
    /** Наша власна мапа, наведена на цю подію. */
    data class OpenMap(val id: String) : DetailEffect
    data class OpenChat(val id: String) : DetailEffect
}
