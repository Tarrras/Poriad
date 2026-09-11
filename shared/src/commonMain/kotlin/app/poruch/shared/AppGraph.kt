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
 * Isolated Koin container, so previews/tests do not share a global session.
 *
 * Доступ до подій зареєстрований п'ятьма гранями, а не одним інтерфейсом: тут це виглядає
 * багатослівніше, зате кожен, хто нижче просить `get()`, отримує рівно те, що йому дозволено
 * робити. Аргументи іменовані свідомо — позиційні `get()` мовчки переплутати легко, а компілятор
 * помітив би це лише там, де типи різні.
 */
class AppGraph(config: AppConfig, sessionStore: SecureSessionStore) {
    private val http = platformHttpClient()
    private val driver = platformDatabaseDriver()
    private val container = koinApplication {
        modules(module {
            single { ApiClient(http, config.supabaseUrl, config.publishableKey) }
            single { ImageStorage(http, config.supabaseUrl, config.publishableKey) }
            single { PoruchDatabase(driver) }
            single<AuthRepository> { SupabaseAuthRepository(get(), sessionStore) }

            // Реалізації подій сховані за EventData; граф бачить лише доменні грані.
            single { EventData(api = get(), auth = get(), database = get(), storage = get()) }
            single<EventDiscovery> { get<EventData>().discovery }
            single<SavedEvents> { get<EventData>().saved }
            single<EventAuthoring> { get<EventData>().authoring }
            single<EventParticipation> { get<EventData>().participation }
            single<EventRequests> { get<EventData>().requests }

            single<CreationIdentityStore> { PersistentCreationIdentity(get(), get()) }
            single<PreferencesRepository> { SupabasePreferencesRepository(get(), get()) }
            single<TasteStore> { LocalTasteStore(get()) }
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
                    creationIdentity = get(), timeZones = get(), addresses = get(), config = config,
                    // Обидва названі тут навмисно, замість того щоб покладатись на дефолти
                    // конструктора: композиційний корінь — єдине місце, де видно обидва потоки
                    // одразу, і де видно, що вони різні.
                    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
                    compute = Dispatchers.Default
                )
            }
        })
    }
    val app: PoruchApp = container.koin.get()
    fun close() { app.close(); http.close(); driver.close(); container.close() }
}
