package app.poruch.data

import app.poruch.domain.SecureSessionStore
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class AuthRepositoryTest {
    private class Store(var value: String? = null): SecureSessionStore {
        override fun read()=value
        override fun write(value:String) { this.value=value }
        override fun clear() { value=null }
    }
    @Test fun corruptStoredSessionIsCleared() {
        val store=Store("broken-json")
        val api=ApiClient(HttpClient(MockEngine { error("must not call network") }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,store)
        assertNull(auth.session.value); assertNull(store.value); api.close()
    }
    @Test fun expiredSessionRefreshesAndPersistsRotatedToken()=runTest {
        val store=Store("""{"user_id":"u1","access_token":"old","refresh_token":"r1","expires_at":1}""")
        val api=ApiClient(HttpClient(MockEngine { request ->
            assertEquals("refresh_token",request.url.parameters["grant_type"])
            respond("""{"access_token":"new","refresh_token":"r2","expires_in":3600,"user":{"id":"u1"}}""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,store)
        assertEquals("new",auth.accessToken())
        assertEquals("r2",auth.session.value?.refreshToken)
        assertTrue(store.value!!.contains("r2")); api.close()
    }
    @Test fun logoutClearsLocalSecretsEvenWhenRemoteIsUnavailable()=runTest {
        val store=Store("""{"user_id":"u1","access_token":"old","refresh_token":"r1","expires_at":9999999999}""")
        val api=ApiClient(HttpClient(MockEngine { respond("{}",HttpStatusCode.ServiceUnavailable) }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,store)
        runCatching { auth.signOut() }
        assertNull(store.value); assertNull(auth.session.value); api.close()
    }
    @Test fun callbackIdentityComesFromAuthServer()=runTest {
        val store=Store()
        val api=ApiClient(HttpClient(MockEngine { request ->
            assertEquals("Bearer token",request.headers["Authorization"])
            respond("""{"id":"verified-user"}""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,store)
        assertTrue(auth.handleCallback("poruch://auth/callback#access_token=token&refresh_token=refresh&type=recovery&expires_in=3600"))
        assertEquals("verified-user",auth.session.value?.userId); api.close()
    }
    @Test fun foreignCallbackCannotReplaceSession()=runTest {
        val api=ApiClient(HttpClient(MockEngine { error("must not call network") }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store())
        assertFails { auth.handleCallback("https://evil.invalid/callback#access_token=x&refresh_token=y") }
        assertNull(auth.session.value); api.close()
    }
    @Test fun creationKeySurvivesNewStoreInstance() {
        val api=ApiClient(HttpClient(MockEngine { error("must not call network") }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store())
        val driver=platformDatabaseDriver()
        val database=app.poruch.data.cache.PoruchDatabase(driver)
        val draft=app.poruch.domain.EventDraft("Прогулянка","Зустріч у центрі","outdoors","Київ","Поділ",50.45,30.5,"2090-01-01T10:00:00Z","2090-01-01T12:00:00Z","Europe/Kyiv",10)
        val first=PersistentCreationIdentity(database,auth).idFor(draft)
        assertEquals(first,PersistentCreationIdentity(database,auth).idFor(draft))
        val next=PersistentCreationIdentity(database,auth).idFor(draft.copy(title="Інша подія"))
        assertNotEquals(first,next)
        driver.close();api.close()
    }

}
