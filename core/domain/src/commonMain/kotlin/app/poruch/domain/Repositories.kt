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
    /** [birthDate] is ISO-8601 and travels in sign-up metadata; the server enforces the floor. */
    suspend fun signUp(email: String, password: String, name: String, birthDate: String): Boolean
    suspend fun signOut()
    suspend fun accessToken(): String?
    suspend fun requestPasswordReset(email: String)
    suspend fun updatePassword(password: String)
    suspend fun handleCallback(url: String): Boolean
}
// Доступ до подій живе в EventAccess.kt: він поділений на грані, а не на один інтерфейс.

/** What this account declared and where moderation currently stands with it. */
data class AccountFacts(val birthDate: String? = null, val status: String = AccountStatus.ACTIVE) {
    val ageDeclared get() = birthDate != null
    val restricted get() = status != AccountStatus.ACTIVE
}

object AccountStatus {
    const val ACTIVE = "active"
    const val LIMITED = "limited"
    const val BANNED = "banned"
}

/**
 * Reporting and blocking. Separate from events because it is about people: an app that can only
 * report the thing in front of you cannot answer «this person keeps showing up».
 */
interface SafetyRepository {
    suspend fun account(): AccountFacts
    /** Allowed once, for accounts that predate the question. */
    suspend fun declareBirthDate(date: String)
    suspend fun reportEvent(eventId: String, reason: String, details: String?)
    suspend fun reportUser(userId: String, reason: String, details: String?)
    suspend fun block(userId: String)
    suspend fun unblock(userId: String)
    /** Who this account has blocked, named — a list of opaque ids cannot be undone by a person. */
    suspend fun blocked(): List<Attendee>
}
interface GeoSearchRepository { suspend fun search(query: String): List<CityResult> }

/**
 * Адреса, знайдена за текстом.
 *
 * [label] — те, що людина шукала: «Фролівська, 9». [detail] — те, що відрізняє одну Фролівську від
 * іншої: район і місто. Розділені, бо в списку вони мають різну вагу, а не тому, що так зручніше
 * складати рядок.
 *
 * [city] повторює частину [detail] окремим полем: у редактора місто — власне поле, і воно має
 * їхати за адресою, а не лишатись від попередньої.
 */
data class PlaceResult(
    val label: String,
    val detail: String,
    val city: String,
    val latitude: Double,
    val longitude: Double
)

/**
 * Пошук адреси для події.
 *
 * Окремо від [GeoSearchRepository] не через реалізацію — вона та сама, — а через питання. Місто
 * шукають, щоб змістити мапу; адресу — щоб поставити крапку, і тоді важать інші речі: близькість
 * до міста події та підпис, у якому видно вулицю з будинком.
 */
interface AddressSearch {
    /**
     * [latitude] і [longitude] — не фільтр, а зсув: та сама вулиця є в десятку міст, і першою має
     * бути та, що поруч із подією.
     */
    suspend fun places(query: String, latitude: Double, longitude: Double): List<PlaceResult>

    /**
     * Що за адреса в цій точці.
     *
     * Зворотний бік [places]: там адресу набирають і отримують крапку, тут крапку ставлять і
     * отримують адресу. Обидва напрямки потрібні, бо поле й мапа показують одне й те саме, і
     * змінити його можна з будь-якого боку.
     *
     * `null` — не помилка: у полі просто лишається те, що там було.
     */
    suspend fun placeAt(latitude: Double, longitude: Double): PlaceResult?
}

/**
 * Часовий пояс місця події.
 *
 * Подія зберігає власний пояс, а не пояс того, хто її створив: киянин, що планує зустріч у
 * Варшаві, вказує варшавський час, і читач у Львові має побачити саме його.
 *
 * Відповідь необов'язкова. `null` означає «не вдалося визначити» — і тоді лишається пояс
 * пристрою, тобто рівно те, що було типовим значенням і доти.
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
