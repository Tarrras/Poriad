package app.poruch.shared

import app.poruch.account.AccountActions
import app.poruch.data.account.SupabaseAuthRepository
import app.poruch.data.account.SupabasePreferencesRepository
import app.poruch.data.api.ApiClient
import app.poruch.data.api.ImageStorage
import app.poruch.data.cache.PoruchDatabase
import app.poruch.data.events.*
import app.poruch.data.geo.PhotonGeoSearchRepository
import app.poruch.data.geo.PlatformTimeZoneLocator
import app.poruch.data.local.LocalReminderPreference
import app.poruch.data.local.LocalSeenRequests
import app.poruch.data.local.LocalTasteStore
import app.poruch.data.local.PersistentCreationIdentity
import app.poruch.data.platformDatabaseDriver
import app.poruch.data.platformHttpClient
import app.poruch.data.safety.SupabaseSafetyRepository
import app.poruch.domain.*
import app.poruch.events.EventActions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.koin.dsl.koinApplication
import org.koin.dsl.module

/**
 * Ізольований контейнер Koin, щоб превʼю й тести не ділили глобальну сесію. Доступ до подій
 * зареєстровано п'ятьма інтерфейсами, аргументи іменовані: позиційні `get()` легко переплутати.
 */
class AppGraph(
    config: AppConfig,
    sessionStore: SecureSessionStore,
    reminders: ReminderScheduler? = null,
    /** Показ сповіщення про новий запит на участь. Null — лише бейджі на головній. */
    requestNotifier: RequestNotifier? = null
) {
    private val http = platformHttpClient()
    private val driver = platformDatabaseDriver()
    private val container = koinApplication {
        modules(module {
            single { ApiClient(http, config.supabaseUrl, config.publishableKey) }
            single { ImageStorage(http, config.supabaseUrl, config.publishableKey) }
            single { PoruchDatabase(driver) }
            single<AuthRepository> { SupabaseAuthRepository(get(), sessionStore) }

            // Реалізації сховані за EventData; граф бачить лише доменні інтерфейси.
            single { EventData(api = get(), auth = get(), database = get(), storage = get()) }
            single<EventDiscovery> { get<EventData>().discovery }
            single<SavedEvents> { get<EventData>().saved }
            single<EventAuthoring> { get<EventData>().authoring }
            single<EventParticipation> { get<EventData>().participation }
            single<EventRequests> { get<EventData>().requests }

            single<CreationIdentityStore> { PersistentCreationIdentity(get(), get()) }
            single<PreferencesRepository> { SupabasePreferencesRepository(get(), get()) }
            single<TasteStore> { LocalTasteStore(get()) }
            single<ReminderPreferenceStore> { LocalReminderPreference(get()) }
            single<SeenRequestStore> { LocalSeenRequests(get(), get()) }
            single<SafetyRepository> { SupabaseSafetyRepository(get(), get()) }
            // Один клас, два питання: місто зміщує мапу, адреса ставить крапку.
            single { PhotonGeoSearchRepository(http) }
            single<GeoSearchRepository> { get<PhotonGeoSearchRepository>() }
            single<AddressSearch> { get<PhotonGeoSearchRepository>() }
            single<TimeZoneLocator> { PlatformTimeZoneLocator() }

            single { EventActions(authoring = get(), participation = get(), auth = get()) }
            single { AccountActions(get()) }
            single {
                PoruchApp(
                    events = get(), saved = get(), authoring = get(), participation = get(),
                    requests = get(), auth = get(), geo = get(),
                    eventActions = get(), accountActions = get(),
                    preferences = get(), safety = get(), tasteStore = get(),
                    creationIdentity = get(), timeZones = get(), addresses = get(),
                    reminderStore = get(), reminders = reminders,
                    seenRequests = get(), requestNotifier = requestNotifier, config = config,
                    // Обидва потоки названі явно: тут єдине місце, де видно, що вони різні.
                    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
                    compute = Dispatchers.Default
                )
            }
        })
    }
    val app: PoruchApp = container.koin.get()
    fun close() { app.close(); http.close(); driver.close(); container.close() }
}
