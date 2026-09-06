package app.poruch.shared

import app.poruch.domain.*
import app.poruch.data.*
import app.poruch.data.cache.PoruchDatabase
import app.poruch.events.EventActions
import app.poruch.account.AccountActions
import org.koin.dsl.koinApplication
import org.koin.dsl.module

/** Isolated Koin container, so previews/tests do not share a global session. */
class AppGraph(config: AppConfig, sessionStore: SecureSessionStore) {
    private val http=platformHttpClient()
    private val driver=platformDatabaseDriver()
    private val container=koinApplication {
        modules(module {
            single { ApiClient(http,config.supabaseUrl,config.publishableKey) }
            single<AuthRepository> { SupabaseAuthRepository(get(),sessionStore) }
            single { PoruchDatabase(driver) }
            single<EventRepository> { SupabaseEventRepository(get(),get(),get()) }
            single<CreationIdentityStore> { PersistentCreationIdentity(get(),get()) }
            single<PreferencesRepository> { SupabasePreferencesRepository(get(),get()) }
            single<GeoSearchRepository> { PhotonGeoSearchRepository(http) }
            single { EventActions(get(),get()) }
            single { AccountActions(get()) }
            single { PoruchApp(get(),get(),get(),get(),get(),get(),get(),config) }
        })
    }
    val app: PoruchApp = container.koin.get()
    fun close() { app.close(); http.close(); driver.close(); container.close() }
}
