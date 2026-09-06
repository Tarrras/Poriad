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
    suspend fun signUp(email: String, password: String, name: String): Boolean
    suspend fun signOut()
    suspend fun accessToken(): String?
    suspend fun requestPasswordReset(email: String)
    suspend fun updatePassword(password: String)
    suspend fun handleCallback(url: String): Boolean
}
data class EventQuery(val south: Double, val west: Double, val north: Double, val east: Double, val category: String? = null, val from: String? = null, val to: String? = null, val text: String? = null, val available: Boolean = false)
interface EventRepository {
    suspend fun discover(query: EventQuery): List<Event>
    fun cached(query: EventQuery): List<Event>
    suspend fun details(id: String): Event?
    suspend fun myEvents(): List<Event>
    suspend fun savedIds(): List<String>
    suspend fun save(id: String)
    suspend fun unsave(id: String)
    suspend fun create(id: String, draft: EventDraft): String
    suspend fun update(id: String, draft: EventDraft): String
    suspend fun join(id: String)
    suspend fun leave(id: String)
    suspend fun cancel(id: String)
    suspend fun uploadImage(eventId: String, bytes: ByteArray, contentType: String): String
    /** Roster of an event. Identities are visible to its organizer and members only; others get none. */
    suspend fun attendees(id: String): List<Attendee> = emptyList()
    /** Events this account is queued for. Positions are private to their holder. */
    suspend fun waitlistIds(): List<String> = emptyList()
    suspend fun joinWaitlist(id: String)
    suspend fun leaveWaitlist(id: String)
    fun clearPrivateCache()
}
interface GeoSearchRepository { suspend fun search(query: String): List<CityResult> }
interface PreferencesRepository {
    suspend fun interests(): List<String>
    suspend fun setInterests(categories: List<String>)
}

interface CreationIdentityStore {
    fun idFor(draft: EventDraft): String
    fun clear()
}
