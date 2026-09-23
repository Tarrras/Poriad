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
        assertFalse(store.value!!.contains("pkce_")); api.close()
    }
    @Test fun implicitTokensInCallbackAreRejected()=runTest {
        val api=ApiClient(HttpClient(MockEngine { error("must not call network") }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store())
        assertFails { auth.handleCallback("poriad://auth/callback#access_token=token&refresh_token=refresh&type=recovery") }
        assertNull(auth.session.value); api.close()
    }
    @Test fun callbackOnlyAcceptsItsEnvironmentScheme()=runTest {
        val api=ApiClient(HttpClient(MockEngine { error("must not call network") }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store(),"poriad-dev")
        assertFails { auth.handleCallback("poriad://auth/callback?code=c1") }
        val failure=assertFailsWith<app.poruch.domain.AppFailure> { auth.handleCallback("poriad-dev://auth/callback?code=c1") }
        assertEquals(app.poruch.domain.AppError.LinkExpired,failure.error); api.close()
    }
    /** Verifier-а нема: посилання вже використане чи старе — не «інший пристрій». */
    @Test fun callbackWithoutVerifierSaysTheLinkExpired()=runTest {
        val api=ApiClient(HttpClient(MockEngine { error("must not call network") }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store())
        val failure=assertFailsWith<app.poruch.domain.AppFailure> { auth.handleCallback("poriad://auth/callback?code=c1") }
        assertEquals(app.poruch.domain.AppError.LinkExpired,failure.error); api.close()
    }
    /** Лист реєстрації й лист відновлення чекають разом: другий не затирає перший, код знаходить свій verifier. */
    @Test fun signupAndRecoveryVerifiersLiveSideBySide()=runTest {
        val store=Store()
        var recoveryChallenge=""
        fun field(body:String,name:String)=Regex("\"$name\":\"([^\"]+)\"").find(body)!!.groupValues[1]
        val api=ApiClient(HttpClient(MockEngine { request ->
            val body=request.body.toByteArray().decodeToString()
            when {
                request.url.encodedPath.endsWith("/signup") -> respond("""{"id":"u1"}""",HttpStatusCode.OK)
                request.url.encodedPath.endsWith("/recover") -> { recoveryChallenge=field(body,"code_challenge"); respond("{}",HttpStatusCode.OK) }
                // Сервер приймає лише verifier відновлення, решту відхиляє як bad_code_verifier.
                Pkce.challenge(field(body,"code_verifier"))==recoveryChallenge ->
                    respond("""{"access_token":"t","refresh_token":"r","expires_in":3600,"user":{"id":"u1"}}""",HttpStatusCode.OK)
                else -> respond("""{"code":400,"error_code":"bad_code_verifier","msg":"code challenge does not match"}""",HttpStatusCode.BadRequest)
            }
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,store)
        auth.signUp("a@b.co","password1","Імʼя","2000-01-01")
        auth.requestPasswordReset("a@b.co")
        assertTrue(auth.handleCallback("poriad://auth/callback?code=c1"),"це відновлення")
        assertTrue(store.value!!.contains("pkce_signup"),"лист реєстрації досі можна відкрити")
        assertFalse(store.value!!.contains("pkce_recovery")); api.close()
    }
    /** Сервер каже «прострочено» — так і кажемо людині. */
    @Test fun anExpiredCodeSaysSo()=runTest {
        val api=ApiClient(HttpClient(MockEngine { respond("""{"code":403,"error_code":"flow_state_expired","msg":"expired"}""",HttpStatusCode.Forbidden) }),"https://test.invalid","public")
        val failure=assertFailsWith<app.poruch.domain.AppFailure> { SupabaseAuthRepository(api,Store("""{"pkce_signup":"v"}""")).handleCallback("poriad://auth/callback?code=c1") }
        assertEquals(app.poruch.domain.AppError.LinkExpired,failure.error); api.close()
    }
    /** Строк сесії — від годинника пристрою: `expires_at` сервера з іншим годинником не вірний. */
    @Test fun expiryIsCountedFromTheLocalClock()=runTest {
        val api=ApiClient(HttpClient(MockEngine {
            respond("""{"access_token":"t","refresh_token":"r","expires_in":3600,"expires_at":1,"user":{"id":"u1"}}""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store())
        auth.signIn("a@b.co","password1")
        val left=auth.session.value!!.expiresAt-kotlin.time.Clock.System.now().epochSeconds
        assertTrue(left in 3500..3600,"лишилось $left с"); api.close()
    }
    /** 401 на «свіжому» токені: один примусовий refresh і повтор того самого запиту. */
    @Test fun anUnauthorizedRequestRefreshesOnceAndRetries()=runTest {
        val calls=mutableListOf<String>()
        val api=ApiClient(HttpClient(MockEngine { request ->
            val bearer=request.headers["Authorization"]
            calls+="${request.url.encodedPath} $bearer"
            when {
                request.url.encodedPath=="/auth/v1/token" -> respond("""{"access_token":"new","refresh_token":"r2","expires_in":3600,"user":{"id":"u1"}}""",HttpStatusCode.OK)
                bearer=="Bearer old" -> respond("""{"code":"PGRST301","message":"JWT expired"}""",HttpStatusCode.Unauthorized)
                else -> respond("[]",HttpStatusCode.OK)
            }
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store("""{"user_id":"u1","access_token":"old","refresh_token":"r1","expires_at":9999999999}"""))
        api.request("/rest/v1/rpc/join_event",HttpMethod.Post,token=auth.accessToken())
        assertEquals(listOf("/rest/v1/rpc/join_event Bearer old","/auth/v1/token null","/rest/v1/rpc/join_event Bearer new"),calls)
        assertEquals("new",auth.session.value?.accessToken); api.close()
    }
    /** Видалення: мережевий збій лишає сесію; успіх — стирає; тіло й заголовки — як чекає Edge Function. */
    @Test fun deletingTheAccountClearsTheSessionOnlyOnSuccess()=runTest {
        val session="""{"user_id":"u1","access_token":"a1","refresh_token":"r1","expires_at":9999999999}"""
        val offline=ApiClient(HttpClient(MockEngine { error("offline") }),"https://test.invalid","public")
        val kept=SupabaseAuthRepository(offline,Store(session))
        assertEquals(app.poruch.domain.AppError.Network,assertFailsWith<app.poruch.domain.AppFailure> { kept.deleteAccount() }.error)
        assertEquals("u1",kept.session.value?.userId); offline.close()

        val api=ApiClient(HttpClient(MockEngine { request ->
            assertEquals("/functions/v1/delete-account",request.url.encodedPath)
            assertEquals("Bearer a1",request.headers["Authorization"]); assertEquals("public",request.headers["apikey"])
            assertEquals("{}",request.body.toByteArray().decodeToString())
            respond("""{"deleted":true}""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        val store=Store(session); val auth=SupabaseAuthRepository(api,store)
        auth.deleteAccount()
        assertNull(auth.session.value); assertNull(store.value); api.close()
    }
    /** Перевірка пароля створює сесію на сервері — її одразу закриваємо, і лише її (`scope=local`). */
    @Test fun verifyingThePasswordClosesItsOwnSession()=runTest {
        val calls=mutableListOf<String>()
        val api=ApiClient(HttpClient(MockEngine { request ->
            calls+="${request.method.value} ${request.url.encodedPath} ${request.url.parameters["scope"]} ${request.headers["Authorization"]}"
            when (request.url.encodedPath) {
                "/auth/v1/user" -> respond("""{"email":"a@b.co"}""",HttpStatusCode.OK)
                "/auth/v1/token" -> respond("""{"access_token":"proof","refresh_token":"r","expires_in":3600,"user":{"id":"u1"}}""",HttpStatusCode.OK)
                else -> respond("",HttpStatusCode.NoContent)
            }
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store("""{"user_id":"u1","access_token":"a1","refresh_token":"r1","expires_at":9999999999}"""))
        auth.verifyPassword("password1")
        assertEquals("POST /auth/v1/logout local Bearer proof",calls.last())
        assertEquals("a1",auth.session.value?.accessToken,"наша сесія не змінилась"); api.close()
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
        assertTrue(store.value!!.contains("pkce_signup")); assertNull(auth.session.value); api.close()
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
        // Зміна безпеки — теж інша чернетка: повтор не має опублікувати подію без схвалення.
        val approval=PersistentCreationIdentity(database,auth).idFor(draft.copy(title="Інша подія",approvalRequired=true))
        assertNotEquals(next,approval)
        driver.close();api.close()
    }

}
