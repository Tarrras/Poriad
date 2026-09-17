package app.poruch.data.account
import app.poruch.data.api.ApiClient
import app.poruch.data.cache.PoruchDatabase
import app.poruch.data.local.PersistentCreationIdentity
import app.poruch.data.platformDatabaseDriver

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
    @Test fun callbackExchangesCodeWithStoredVerifier()=runTest {
        val store=Store("""{"pkce_verifier":"v-secret","pkce_flow":"recovery"}""")
        val api=ApiClient(HttpClient(MockEngine { request ->
            assertEquals("pkce",request.url.parameters["grant_type"])
            val body=request.body.toByteArray().decodeToString()
            assertTrue("\"auth_code\":\"c1\"" in body && "\"code_verifier\":\"v-secret\"" in body)
            respond("""{"access_token":"token","refresh_token":"refresh","expires_in":3600,"user":{"id":"verified-user"}}""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,store)
        assertTrue(auth.handleCallback("poriad://auth/callback?code=c1"))
        assertEquals("verified-user",auth.session.value?.userId)
        assertFalse(store.value!!.contains("pkce_verifier")); api.close()
    }
    @Test fun implicitTokensInCallbackAreRejected()=runTest {
        val api=ApiClient(HttpClient(MockEngine { error("must not call network") }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store())
        assertFails { auth.handleCallback("poriad://auth/callback#access_token=token&refresh_token=refresh&type=recovery") }
        assertNull(auth.session.value); api.close()
    }
    @Test fun callbackWithoutVerifierExplainsOtherDevice()=runTest {
        val api=ApiClient(HttpClient(MockEngine { error("must not call network") }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store())
        val failure=assertFailsWith<app.poruch.domain.AppFailure> { auth.handleCallback("poriad://auth/callback?code=c1") }
        assertEquals(app.poruch.domain.AppError.LinkOnAnotherDevice,failure.error); api.close()
    }
    @Test fun signUpSendsChallengeAndKeepsVerifier()=runTest {
        val store=Store()
        val api=ApiClient(HttpClient(MockEngine { request ->
            val body=request.body.toByteArray().decodeToString()
            assertTrue("code_challenge_method" in body && "\"code_challenge\"" in body)
            respond("""{"id":"u1"}""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,store)
        assertFalse(auth.signUp("a@b.co","password1","Імʼя","2000-01-01"))
        assertTrue(store.value!!.contains("pkce_verifier")); assertNull(auth.session.value); api.close()
    }
    @Test fun sha256MatchesKnownVector() {
        val hex=Pkce.sha256("abc".encodeToByteArray()).joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2,'0') }
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",hex)
        assertEquals(43,Pkce.newVerifier().length)
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
