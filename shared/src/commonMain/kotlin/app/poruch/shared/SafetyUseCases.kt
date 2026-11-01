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
        store.update {
            it.copy(
                library = it.library.copy(account = it.library.account.copy(birthDate = declared.toString())),
                session = it.session.copy(askBirthDate = false)
            )
        }
        store.tell(AppMessage.AGE_CONFIRMED)
        ageDeclared()
    }

    /** Що чекало саме на вік: намір «Хочу піти з компанією» і публікація, відкладена до входу. */
    private fun ageDeclared() {
        library.consumePendingCompany()
        onAgeDeclared?.invoke()
    }

    /** Ставить [PoruchApp]: публікація гостя після входу ([EventUseCases.publishPending]). */
    var onAgeDeclared: (() -> Unit)? = null

    /**
     * Галочка «Мені вже є 18» (хвиля 2): після входу через Google, Apple чи код і з картки віку в профілі. Подія з віком
     * від 19 чи верхньою межею однаково попросить дату ([AppError.AgeRequired] → [declareBirthDate]).
     */
    fun confirmAdult() = store.mutate {
        repository().confirmAdult()
        store.update {
            val account = it.library.account
            it.copy(
                library = it.library.copy(account = account.copy(adultConfirmedAt = account.adultConfirmedAt ?: Clock.System.now().toString())),
                session = it.session.copy(askBirthDate = false)
            )
        }
        store.tell(AppMessage.AGE_CONFIRMED)
        ageDeclared()
    }

    fun reportEvent(eventId: String, reason: ReportReason, details: String?) = store.mutate {
        val repository = signedInRepository()
        PoruchLog.i("safety") { "report event ${eventId.shortId()} reason=${reason.key}" }
        repository.reportEvent(eventId, reason, details)
        store.tell(AppMessage.REPORT_SENT)
    }

    fun reportUser(userId: String, reason: ReportReason, details: String?) = store.mutate {
        val repository = signedInRepository()
        PoruchLog.i("safety") { "report user ${userId.shortId()} reason=${reason.key}" }
        repository.reportUser(userId, reason, details)
        store.tell(AppMessage.REPORT_SENT)
    }

    fun reportMessage(messageId: String, reason: ReportReason, details: String?) = store.mutate {
        val repository = signedInRepository()
        PoruchLog.i("safety") { "report message ${messageId.shortId()} reason=${reason.key}" }
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
