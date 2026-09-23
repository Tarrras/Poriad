package app.poruch.domain

import kotlinx.coroutines.flow.StateFlow

interface SecureSessionStore {
    fun read(): String?
    fun write(value: String)
    fun clear()
}
data class UserSession(val userId: String, val accessToken: String, val refreshToken: String, val expiresAt: Long)
interface AuthRepository {
    val session: StateFlow<UserSession?>
    suspend fun signIn(email: String, password: String)
    /** [birthDate] — ISO-8601, їде в метаданих реєстрації. Мінімальний вік перевіряє сервер. */
    suspend fun signUp(email: String, password: String, name: String, birthDate: String): Boolean
    suspend fun signOut()
    suspend fun accessToken(): String?
    suspend fun requestPasswordReset(email: String)
    suspend fun updatePassword(password: String)
    suspend fun handleCallback(url: String): Boolean
    /** Повторно підтверджує пароль поточного акаунта; помилка — [AppError.InvalidCredentials]. */
    suspend fun verifyPassword(password: String)
    /**
     * Видаляє акаунт на сервері (Edge Function `delete-account`). Локальну сесію чистить лише
     * після успіху або 401; мережевий збій лишає людину в акаунті, щоб могла повторити.
     */
    suspend fun deleteAccount()
}
// Доступ до подій — в EventAccess.kt.

/** Що акаунт про себе заявив і що про нього думає модерація. */
data class AccountFacts(val birthDate: String? = null, val status: String = AccountStatus.ACTIVE) {
    val ageDeclared get() = birthDate != null
    val restricted get() = status != AccountStatus.ACTIVE
}

object AccountStatus {
    const val ACTIVE = "active"
    const val LIMITED = "limited"
    const val BANNED = "banned"
}

/** Скарги й блокування. Окремо від подій, бо стосується людей. */
interface SafetyRepository {
    suspend fun account(): AccountFacts
    /** Дозволено один раз, для акаунтів, створених до появи питання про вік. */
    suspend fun declareBirthDate(date: String)
    suspend fun reportEvent(eventId: String, reason: String, details: String?)
    suspend fun reportUser(userId: String, reason: String, details: String?)
    /** Скарга на повідомлення в чаті: іде на автора, з подією і текстом для контексту. */
    suspend fun reportMessage(messageId: String, reason: String, details: String?)
    suspend fun block(userId: String)
    suspend fun unblock(userId: String)
    /** Кого заблокував цей акаунт, з іменами, щоб можна було розблокувати. */
    suspend fun blocked(): List<Attendee>
}
interface GeoSearchRepository { suspend fun search(query: String): List<CityResult> }

/**
 * Знайдена адреса. [label] — те, що шукали («Фролівська, 9»), [detail] — район і місто, щоб
 * відрізнити однакові вулиці. [city] окремо, бо в редакторі місто — власне поле.
 */
data class PlaceResult(
    val label: String,
    val detail: String,
    val city: String,
    val latitude: Double,
    val longitude: Double
)

/**
 * Пошук адреси для події. Окремо від [GeoSearchRepository]: місто шукають, щоб змістити мапу,
 * адресу — щоб поставити крапку, і тут важать близькість до події та підпис з будинком.
 */
interface AddressSearch {
    /** [latitude] і [longitude] — не фільтр, а пріоритет: однакова вулиця є в десятку міст. */
    suspend fun places(query: String, latitude: Double, longitude: Double): List<PlaceResult>

    /** Адреса в точці, зворотний бік [places]. Null — не помилка, у полі лишається старе. */
    suspend fun placeAt(latitude: Double, longitude: Double): PlaceResult?
}

/**
 * Часовий пояс місця події: подія зберігає власний пояс, а не пояс автора. Null — не
 * визначили, лишається пояс пристрою.
 */
interface TimeZoneLocator {
    suspend fun zoneAt(latitude: Double, longitude: Double): String?
}
interface PreferencesRepository {
    suspend fun interests(): List<String>
    suspend fun setInterests(categories: List<String>)
}

interface CreationIdentityStore {
    fun idFor(draft: EventDraft): String
    fun clear()
}
