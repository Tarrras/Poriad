package app.poruch.shared
import app.poruch.domain.*

typealias SecureSessionStore = app.poruch.domain.SecureSessionStore

data class AppConfig(val supabaseUrl: String, val publishableKey: String)
data class AppState(
    val events: List<Event> = emptyList(), val selectedEvent: Event? = null,
    val myEvents: List<Event> = emptyList(), val savedIds: List<String> = emptyList(),
    val userId: String? = null, val loading: Boolean = false, val mutating: Boolean = false,
    val message: String? = null, val cityName: String = "Київ", val cityLatitude: Double = 50.4501,
    val cityLongitude: Double = 30.5234, val cities: List<CityResult> = emptyList(),
    val category: String = "all", val dateFilter: String = "all", val offline: Boolean = false, val passwordRecovery: Boolean = false, val completedEventId: String? = null, val interests: List<String> = emptyList()
)
class Subscription(private val cancel: () -> Unit) { fun close() = cancel() }
