package app.poruch.data.safety
import app.poruch.data.api.ApiClient

import app.poruch.domain.AuthRepository
import app.poruch.domain.IdProvider
import app.poruch.domain.UserSession
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlin.test.*

/** Галочка «Мені вже є 18»: вік заявлено датою або галочкою, і галочку ставить `confirm_adult`. */
class SafetyRepositoryTest {
    private class SignedIn: AuthRepository {
        override val session=MutableStateFlow<UserSession?>(UserSession("u1","token","refresh",9999999999))
        override suspend fun accessToken()="token"
        override suspend fun signIn(email:String,password:String) {}
        override suspend fun signUp(email:String,password:String,name:String,birthDate:String?)=true
        override suspend fun sendCode(email:String) {}
        override suspend fun verifyCode(email:String,code:String) {}
        override fun idTokenNonce()=""
        override suspend fun signInWithIdToken(provider:IdProvider,idToken:String) {}
        override suspend fun signOut() {}
        override suspend fun requestPasswordReset(email:String) {}
        override suspend fun updatePassword(password:String,current:String?) {}
        override suspend fun handleCallback(url:String)=false
        override suspend fun verifyPassword(password:String) {}
        override suspend fun deleteAccount(password:String?,appleAuthorizationCode:String?) {}
    }

    @Test fun theCheckboxCountsAsADeclaredAge()=runTest {
        val api=ApiClient(HttpClient(MockEngine { request ->
            assertEquals("birth_date,adult_confirmed_at,status",request.url.parameters["select"])
            respond("""[{"birth_date":null,"adult_confirmed_at":"2026-11-01T10:00:00+00:00","status":"active"}]""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        val facts=SupabaseSafetyRepository(api,SignedIn()).account()
        assertNull(facts.birthDate)
        assertTrue(facts.ageDeclared)
        api.close()
    }

    @Test fun confirmingAdultCallsTheRpc()=runTest {
        var path=""
        val api=ApiClient(HttpClient(MockEngine { request ->
            path=request.url.encodedPath
            assertEquals("{}",request.body.toByteArray().decodeToString())
            respond("",HttpStatusCode.NoContent)
        }),"https://test.invalid","public")
        SupabaseSafetyRepository(api,SignedIn()).confirmAdult()
        assertEquals("/rest/v1/rpc/confirm_adult",path)
        api.close()
    }
}
