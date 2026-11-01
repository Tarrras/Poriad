package app.poruch.data.account
import app.poruch.data.api.ApiClient

import app.poruch.domain.AppError
import app.poruch.domain.AppFailure
import app.poruch.domain.SecureSessionStore
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import kotlin.test.*

/** Вхід кодом з пошти й реєстрація з галочкою «Мені вже є 18» (docs/organizers-1.5.md, хвиля 2): що йде в GoTrue. */
class SignInCodeTest {
    private class Store(var value: String? = null): SecureSessionStore {
        override fun read()=value
        override fun write(value:String) { this.value=value }
        override fun clear() { value=null }
    }
    private suspend fun body(request: io.ktor.client.request.HttpRequestData)=
        Json.parseToJsonElement(request.body.toByteArray().decodeToString()).jsonObject

    /** Той самий запит, що на сайті: новий акаунт з першим кодом, без посилання й PKCE. */
    @Test fun aCodeIsRequestedForAnyEmail()=runTest {
        val api=ApiClient(HttpClient(MockEngine { request ->
            assertEquals("/auth/v1/otp",request.url.encodedPath)
            val sent=body(request)
            assertEquals("a@b.co",sent["email"]!!.jsonPrimitive.content)
            assertEquals(true,sent["create_user"]!!.jsonPrimitive.boolean)
            assertNull(sent["code_challenge"])
            respond("{}",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        SupabaseAuthRepository(api,Store()).sendCode(" a@b.co ")
        api.close()
    }

    @Test fun aRightCodeSignsIn()=runTest {
        val store=Store()
        val api=ApiClient(HttpClient(MockEngine { request ->
            assertEquals("/auth/v1/verify",request.url.encodedPath)
            val sent=body(request)
            assertEquals("email",sent["type"]!!.jsonPrimitive.content)
            assertEquals("123456",sent["token"]!!.jsonPrimitive.content)
            respond("""{"access_token":"token","refresh_token":"refresh","expires_in":3600,"user":{"id":"u1"}}""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,store)
        auth.verifyCode("a@b.co"," 123456 ")
        assertEquals("u1",auth.session.value?.userId)
        assertTrue(store.value!!.contains("refresh")); api.close()
    }

    /** GoTrue каже про хибний код `otp_expired`, як про старе посилання: людині — «код не підійшов». */
    @Test fun aWrongCodeIsNotAnExpiredLink()=runTest {
        val api=ApiClient(HttpClient(MockEngine {
            respond("""{"code":403,"error_code":"otp_expired","msg":"Token has expired or is invalid"}""",HttpStatusCode.Forbidden)
        }),"https://test.invalid","public")
        val auth=SupabaseAuthRepository(api,Store())
        assertEquals(AppError.InvalidCode,assertFailsWith<AppFailure> { auth.verifyCode("a@b.co","000000") }.error)
        assertNull(auth.session.value); api.close()
    }

    /** Галочка замість дати: у метаданих `adult_confirmed`, а `birth_date` нема, тож тригер акаунта не питає дати. */
    @Test fun aCheckboxSignUpSendsAdultConfirmed()=runTest {
        var data: JsonObject? = null
        val api=ApiClient(HttpClient(MockEngine { request ->
            data=body(request)["data"]!!.jsonObject
            respond("""{"id":"u1"}""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        assertFalse(SupabaseAuthRepository(api,Store()).signUp("a@b.co","password1","Імʼя",null))
        assertEquals(true,data!!["adult_confirmed"]!!.jsonPrimitive.boolean)
        assertNull(data!!["birth_date"])
        assertEquals("Імʼя",data!!["display_name"]!!.jsonPrimitive.content)
        api.close()
    }
}
