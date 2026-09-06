package app.poruch.shared

import app.poruch.domain.*

/** Re-exported so a platform module depends on `shared` alone, not on `core:domain` as well. */
typealias SecureSessionStore = app.poruch.domain.SecureSessionStore

/** Everything the app knows, in one immutable snapshot. Screens select the slice they need. */
data class AppState(
    val events: List<Event> = emptyList(), val selectedEvent: Event? = null,
    val myEvents: List<Event> = emptyList(), val savedIds: List<String> = emptyList(),
    val userId: String? = null, val loading: Boolean = false, val mutating: Boolean = false,
    val notice: AppNotice? = null, val cityName: String = HomeLocation.Kyiv.city,
    val cityLatitude: Double = HomeLocation.Kyiv.latitude,
    val cityLongitude: Double = HomeLocation.Kyiv.longitude, val cities: List<CityResult> = emptyList(),
    val category: String = ALL_CATEGORIES, val dateFilter: String = DateFilter.ANY, val offline: Boolean = false,
    val passwordRecovery: Boolean = false, val completedEventId: String? = null,
    val interests: List<String> = emptyList(), val searchText: String = "", val onlyAvailable: Boolean = false,
    val attendees: List<Attendee> = emptyList(), val waitlistedIds: List<String> = emptyList()
) {
    val signedIn get() = userId != null
    fun isSaved(id: String) = id in savedIds
    fun isWaitlisted(id: String) = id in waitlistedIds
    fun organizes(event: Event) = userId != null && event.organizerId == userId
}

/** The category filter value that means "do not filter". Not a category, so it lives apart. */
const val ALL_CATEGORIES = "all"

/** The date filter values the map offers. Strings because both platforms persist them as such. */
object DateFilter {
    const val ANY = "all"
    const val TODAY = "today"
    const val WEEKEND = "weekend"
}

/**
 * A one-line notice for the banner: named, never worded. Presentation turns the name into text
 * from its own resources, which is what keeps Ukrainian out of the shared module.
 */
sealed interface AppNotice {
    /** True for failures, so the banner can pick its tone without knowing the case. */
    val isError: Boolean

    data class Failed(val error: AppError) : AppNotice {
        override val isError get() = true
    }

    data class Told(val message: AppMessage) : AppNotice {
        override val isError get() = false
    }
}

/** Everything the app tells the user when nothing went wrong. */
enum class AppMessage {
    JOINED_EVENT, JOINED_WAITLIST, SIGNED_IN, ACCOUNT_CREATED, CONFIRM_EMAIL_FIRST,
    EVENT_PUBLISHED, CHANGES_SAVED, PHOTO_ADDED, RECOVERY_SENT, PASSWORD_CHANGED,
    SET_NEW_PASSWORD, EMAIL_CONFIRMED, ZOOM_IN_FOR_MORE
}

/** Everything a build needs to reach its backend and decide where the map opens. */
data class AppConfig(
    val supabaseUrl: String,
    val publishableKey: String,
    val home: HomeLocation = HomeLocation.Kyiv
)

class Subscription(private val cancel: () -> Unit) { fun close() = cancel() }
