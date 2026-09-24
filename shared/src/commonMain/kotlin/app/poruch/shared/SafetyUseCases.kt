package app.poruch.shared

import app.poruch.domain.*
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.time.Clock

/** Скарги, блокування й вік. Усе потребує акаунта і сервера з міграцією безпеки. */
internal class SafetyUseCases(
    private val safety: SafetyRepository?,
    private val store: AppStore,
    private val library: UserLibrary,
    private val reloader: Reloader
) {
    private fun repository() = safety ?: fail(AppError.ServiceUnavailable)
    private fun signedInRepository() = repository().also { if (!store.value.signedIn) fail(AppError.SessionRequired) }

    /** Вік для акаунта, створеного до появи питання. Дозволено раз; далі це справа модерації. */
    fun declareBirthDate(birthDate: String) = store.mutate {
        val repository = repository()
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val declared = runCatching { LocalDate.parse(birthDate) }.getOrElse { fail(AppError.Rejected) }
        if (!SafetyRules.isSignupAge(declared, today)) fail(AppError.Underage)
        repository.declareBirthDate(declared.toString())
        store.update { it.copy(library = it.library.copy(account = it.library.account.copy(birthDate = declared.toString()))) }
        store.tell(AppMessage.AGE_CONFIRMED)
    }

    fun reportEvent(eventId: String, reason: String, details: String?) = store.mutate {
        val repository = signedInRepository()
        PoruchLog.i("safety") { "report event ${eventId.shortId()} reason=$reason" }
        repository.reportEvent(eventId, reason, details)
        store.tell(AppMessage.REPORT_SENT)
    }

    fun reportUser(userId: String, reason: String, details: String?) = store.mutate {
        val repository = signedInRepository()
        PoruchLog.i("safety") { "report user ${userId.shortId()} reason=$reason" }
        repository.reportUser(userId, reason, details)
        store.tell(AppMessage.REPORT_SENT)
    }

    fun reportMessage(messageId: String, reason: String, details: String?) = store.mutate {
        val repository = signedInRepository()
        PoruchLog.i("safety") { "report message ${messageId.shortId()} reason=$reason" }
        repository.reportMessage(messageId, reason, details)
        store.tell(AppMessage.REPORT_SENT)
    }

    /** Блокування взаємне й миттєве: події людини зникають з мапи при наступному читанні. */
    fun blockUser(userId: String) = store.mutate {
        val repository = signedInRepository()
        PoruchLog.i("safety") { "block ${userId.shortId()}" }
        repository.block(userId)
        // Блок діє на сервері, тож перечитуємо: мапа й «мої події» повертаються відфільтрованими.
        // Подія заблокованого організатора зникає разом з екраном; учасника — лише з ростеру.
        store.update { it.copy(person = null) }
        if (store.value.detail.event?.organizerId == userId) { library.dismiss(); reloader.lists() } else reloader.all()
        store.tell(AppMessage.USER_BLOCKED)
    }

    fun unblockUser(userId: String) = store.mutate {
        repository().unblock(userId)
        store.update { it.copy(library = it.library.copy(blocked = it.library.blocked.filterNot { person -> person.userId == userId })) }
        reloader.lists()
    }
}
