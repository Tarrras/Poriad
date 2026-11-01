package app.poruch.domain

import kotlinx.coroutines.flow.StateFlow

interface SecureSessionStore {
    fun read(): String?
    fun write(value: String)
    fun clear()
}
/**
 * [providers] — чим входить акаунт (`email`, `google`, `apple`), з токена доступу. [methods] — чим відкрито саме цю сесію
 * (`amr` токена: `password`, `otp`, `oauth`…). Порожньо — невідомо.
 */
data class UserSession(
    val userId: String, val accessToken: String, val refreshToken: String, val expiresAt: Long,
    val providers: Set<String> = emptySet(), val methods: Set<String> = emptySet()
)

/** Вхід ID-токеном Google чи Apple: [key] — назва провайдера в Supabase Auth. */
enum class IdProvider(val key: String) { GOOGLE("google"), APPLE("apple") }
interface AuthRepository {
    val session: StateFlow<UserSession?>
    suspend fun signIn(email: String, password: String)
    /**
     * [birthDate] — ISO-8601, їде в метаданих реєстрації; мінімальний вік перевіряє сервер. Null — галочка «Мені вже є 18»
     * (docs/organizers-1.5.md, хвиля 2): у метадані йде `adult_confirmed`.
     */
    suspend fun signUp(email: String, password: String, name: String, birthDate: String?): Boolean
    /** Код входу на пошту (`/auth/v1/otp`). Нової пошти акаунт з'являється з першим входом, як на сайті. */
    suspend fun sendCode(email: String)
    /** Код з листа → сесія. Хибний чи прострочений — [AppError.InvalidCode]. */
    suspend fun verifyCode(email: String, code: String)
    /**
     * Новий nonce для входу ID-токеном: повертає його SHA-256 (hex) — це платформа передає Google чи
     * Apple, а сирий лишається тут і йде в [signInWithIdToken]. Так чужий токен не підсунути.
     */
    fun idTokenNonce(): String
    suspend fun signInWithIdToken(provider: IdProvider, idToken: String)
    suspend fun signOut()
    suspend fun accessToken(): String?
    suspend fun requestPasswordReset(email: String)
    /**
     * [current] — поточний пароль: з ним сервер сам перевіряє власника («Secure password change» у Supabase Auth),
     * і чужий токен пароль не змінить. Null — новий пароль після відновлення з листа: там сервер його не питає.
     */
    suspend fun updatePassword(password: String, current: String? = null)
    suspend fun handleCallback(url: String): Boolean
    /** Повторно підтверджує пароль поточного акаунта; помилка — [AppError.InvalidCredentials]. */
    suspend fun verifyPassword(password: String)
    /**
     * Видаляє акаунт на сервері (Edge Function `delete-account`). [password] — поточний пароль акаунта з паролем:
     * сервер перевіряє його сам, хибний — [AppError.InvalidCredentials]. [appleAuthorizationCode] — свіжий код
     * Sign in with Apple: з ним сервер відкликає токени Apple (App Store 5.1.1(v)). Локальну сесію чистить лише
     * після успіху або 401; мережевий збій лишає людину в акаунті, щоб могла повторити.
     */
    suspend fun deleteAccount(password: String?, appleAuthorizationCode: String?)
}
// Доступ до подій — в EventAccess.kt.

/**
 * Що акаунт про себе заявив і що про нього думає модерація. [adultConfirmedAt] — галочка «Мені вже є 18» замість дати:
 * її досить усюди, крім подій з віком від 19 чи верхньою межею (там сервер просить дату, `AGE_REQUIRED`).
 */
data class AccountFacts(
    val birthDate: String? = null, val status: AccountStatus = AccountStatus.ACTIVE, val adultConfirmedAt: String? = null
) {
    val ageDeclared get() = birthDate != null || adultConfirmedAt != null
    val restricted get() = status != AccountStatus.ACTIVE
}

/** Стан акаунта, як його називає `account_facts.status`. Невідомий — [UNKNOWN], і це вже обмеження. */
enum class AccountStatus(val key: String) {
    ACTIVE("active"), LIMITED("limited"), BANNED("banned"), UNKNOWN("");

    companion object {
        fun fromKey(key: String?): AccountStatus = entries.firstOrNull { it != UNKNOWN && it.key == key } ?: UNKNOWN
    }
}

/** Скарги й блокування. Окремо від подій, бо стосується людей. */
interface SafetyRepository {
    suspend fun account(): AccountFacts
    /** Дозволено один раз, поки дати нема: акаунти до питання про вік і з галочкою на подію з віком від 19 чи межею. */
    suspend fun declareBirthDate(date: String)
    /** Галочка «Мені вже є 18» (`confirm_adult`): повтор нічого не змінює. */
    suspend fun confirmAdult()
    suspend fun reportEvent(eventId: String, reason: ReportReason, details: String?)
    suspend fun reportUser(userId: String, reason: ReportReason, details: String?)
    /** Скарга на повідомлення в чаті: іде на автора, з подією і текстом для контексту. */
    suspend fun reportMessage(messageId: String, reason: ReportReason, details: String?)
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
    suspend fun interests(): List<EventCategory>
    suspend fun setInterests(categories: List<EventCategory>)
}

interface CreationIdentityStore {
    fun idFor(draft: EventDraft): String
    fun clear()
}
