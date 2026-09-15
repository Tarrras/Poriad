package app.poruch.domain

/**
 * Усі помилки застосунку як іменовані випадки, без тексту. Логіка вирішує, що сталося;
 * екран бере формулювання з ресурсів платформи і може реагувати на випадок (запропонувати
 * реєстрацію, відкрити чергу), а не збігати рядок повідомлення.
 */
sealed interface AppError {
    /** Відповіді не було: нема мережі, DNS, TLS або обірваний зв'язок. */
    data object Network : AppError
    /** У збірці нема ключа Supabase: помилка пакування, не користувача. */
    data object NotConfigured : AppError
    /** Сервіс відповів, але не тим, з чим можна працювати. */
    data object ServiceUnavailable : AppError
    /** 4xx, який не можна назвати точніше. */
    data object Rejected : AppError
    data object TooManyAttempts : AppError

    // ---- Сесія
    data object SessionRequired : AppError
    data object InvalidCredentials : AppError
    data object EmailNotConfirmed : AppError
    data object NotOwner : AppError

    // ---- Події
    data object EventUnavailable : AppError
    data object EventCancelled : AppError
    data object EventFull : AppError
    data object AlreadyMember : AppError
    data object OrganizerCannotJoin : AppError
    /** Просилися в чергу, а місця є: треба приєднуватись. */
    data object EventHasSpace : AppError
    data object ImageUploadFailed : AppError

    // ---- Безпека
    /** Акаунт не вказав вік, а в кожної події є мінімум. */
    data object AgeRequired : AppError
    data object TooYoung : AppError
    data object TooOld : AppError
    /** Хтось із двох заблокував іншого. Хто саме — навмисно не кажемо. */
    data object Blocked : AppError
    /** Акаунт обмежений або заблокований модерацією. */
    data object AccountRestricted : AppError
    data object AgeAlreadySet : AppError
    data object Underage : AppError
    data object TooManyReports : AppError
    data object TooManyEvents : AppError

    // ---- Введення
    data class InvalidDraft(val fields: List<DraftField>) : AppError
    data object InvalidEmail : AppError
    data object InvalidName : AppError
    data object WeakPassword : AppError
}

/** Поля, які може відхилити [EventDraft.validate], щоб екран підсвітив потрібне. */
enum class DraftField { TITLE, DESCRIPTION, CATEGORY, ADDRESS, LOCATION, CAPACITY, STARTS_AT, ENDS_AT, TIME_ZONE, IMAGE_URL, AGE_LIMITS }

/** Єдиний виняток застосунку. Обробники дивляться на [error]. */
class AppFailure(
    val error: AppError,
    /**
     * Код помилки від сервера. Людині не показується. Потрібен для сумісності: `PGRST202` означає
     * «на цьому сервері нема такої функції», і так відрізняємо стару базу від відмови.
     */
    val serverCode: String? = null
) : Exception(error.toString())

/** Типізована помилка з будь-якого винятку. Чужі винятки — проблема сервісу. */
fun Throwable.asAppError(): AppError = (this as? AppFailure)?.error ?: AppError.ServiceUnavailable

/** Скорочення для `throw AppFailure(...)`. */
fun fail(error: AppError): Nothing = throw AppFailure(error)
