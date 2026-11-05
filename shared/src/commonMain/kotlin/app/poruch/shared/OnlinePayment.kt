package app.poruch.shared

import app.poruch.domain.Event
import app.poruch.domain.QuestionThread
import kotlin.time.Clock
import kotlin.time.Duration.Companion.days
import kotlin.time.Instant

/*
 * Оплата онлайн (docs/organizer-events.md). Організатор ставить ціну й «оплату онлайн». Людина подає заявку, і ця заявка —
 * їхня розмова на двох: організатор пише реквізити, людина надсилає скріншот оплати, організатор тисне «Оплату отримано»,
 * тобто схвалює заявку. Гроші йдуть повз «Поряд». Хто що може, вирішує сервер; тут — що показати на екрані.
 */

/**
 * Де заявка: реквізитів ще нема → організатор їх надіслав → людина надіслала скріншот → оплату отримано. Подію
 * скасовано — CANCELLED: організатор повертає гроші, розмова лишається для цього відкритою.
 */
enum class PaymentStatus { WAITING_FOR_DETAILS, WAITING_FOR_PAYMENT, PROOF_SENT, PAID, CANCELLED }

/** Стан оплати людини, з якою відкрито розмову. Null — розмова не про оплату онлайн. */
fun AppState.paymentInOpenChat(): PaymentStatus? {
    val open = chat ?: return null
    val person = open.thread ?: return null
    val event = detail.event?.takeIf { it.id == open.eventId } ?: return null
    val room = event.gathering?.takeIf { it.payOnline } ?: return null
    val (requested, going) = when {
        organizes(event) -> detail.joinRequests.any { it.userId == person } to detail.attendees.any { it.userId == person }
        person == session.userId -> room.awaitingApproval to room.joined
        else -> return null
    }
    return when {
        event.isCancelled && (requested || going) -> PaymentStatus.CANCELLED
        requested && open.messages.any { it.authorId == person && it.image != null } -> PaymentStatus.PROOF_SENT
        requested && open.messages.any { it.authorId != person && it.paymentDetails } -> PaymentStatus.WAITING_FOR_PAYMENT
        requested -> PaymentStatus.WAITING_FOR_DETAILS
        going -> PaymentStatus.PAID
        else -> null
    }
}

/** Організатор ще не написав цій людині, як оплатити, а іншим у цій події писав: «Вставити ті самі реквізити». */
fun AppState.repeatablePaymentDetails(): String? =
    chat?.savedPaymentDetails?.takeIf { paymentInOpenChat() == PaymentStatus.WAITING_FOR_DETAILS }

/** Скріншот оплати надсилає лише людина у своїй розмові з організатором онлайн-події, поки заявка чекає оплати. */
fun AppState.canSendPaymentProof(): Boolean {
    val open = chat ?: return false
    if (open.thread == null || open.thread != session.userId) return false
    val event = knownEvent(open.eventId) ?: return false
    val room = event.gathering ?: return false
    return room.payOnline && room.awaitingApproval && !event.isCancelled
}

/**
 * Розмова лише для читання — той самий поріг, що на сервері (send_message): скасовано чи тиждень після кінця. Розмова
 * про оплату онлайн-події — 30 днів після кінця й навіть скасована: домовитись про повернення грошей.
 */
fun Event.chatReadOnly(thread: Boolean): Boolean = chatReadOnlyAt(thread, Clock.System.now())

internal fun Event.chatReadOnlyAt(thread: Boolean, now: Instant): Boolean {
    val payment = thread && gathering?.payOnline == true
    if (isCancelled && !payment) return true
    val end = endInstant ?: return false
    return end + (if (payment) 30.days else 7.days) < now
}

/** Ім'я людини в розмові організатора — і тоді, коли вона ще нічого не написала (організатор почав першим). */
fun AppState.threadPersonName(eventId: String, thread: String): String? {
    val fromChat = chat?.takeIf { it.eventId == eventId }?.messages?.firstOrNull { it.authorId == thread }?.authorName
    val d = detail.takeIf { it.event?.id == eventId }
    return sequenceOf(
        fromChat,
        d?.questions?.firstOrNull { it.askerId == thread }?.askerName,
        d?.joinRequests?.firstOrNull { it.userId == thread }?.name,
        d?.attendees?.firstOrNull { it.userId == thread }?.name
    ).firstOrNull { !it.isNullOrBlank() }
}

/** Людина з заявкою на онлайн-подію: замість «Запит надіслано» на панелі — вхід у розмову з організатором. */
val DetailScreenState.opensPaymentChat: Boolean get() = payOnline && action == DetailAction.REQUESTED

/** Непрочитане в розмові з людиною: у онлайн-події лічильник стоїть на її заявці. */
fun DetailScreenState.unreadInThread(userId: String): Int = questions.firstOrNull { it.askerId == userId }?.unread ?: 0

/** Людина вже надіслала скріншот оплати: на її заявці — «Скріншот надіслано», щоб не відкривати кожну розмову. */
fun DetailScreenState.proofInThread(userId: String): Boolean = questions.firstOrNull { it.askerId == userId }?.hasProof == true

/** «Питання до вас» без людей із заявкою на онлайн-подію: їхня розмова вже відкривається з заявки. */
val DetailScreenState.questionsWithoutRequests: List<QuestionThread>
    get() = if (!payOnline) questions else questions.filter { question -> requests.none { it.userId == question.askerId } }
