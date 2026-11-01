package app.poruch.data.safety
import app.poruch.data.api.ApiClient

import app.poruch.data.SignedInAuth
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

/** Галочка «Мені вже є 18»: вік заявлено датою або галочкою, і галочку ставить `confirm_adult`. */
class SafetyRepositoryTest {
    @Test fun theCheckboxCountsAsADeclaredAge()=runTest {
        val api=ApiClient(HttpClient(MockEngine { request ->
            assertEquals("birth_date,adult_confirmed_at,status",request.url.parameters["select"])
            respond("""[{"birth_date":null,"adult_confirmed_at":"2026-11-01T10:00:00+00:00","status":"active"}]""",HttpStatusCode.OK)
        }),"https://test.invalid","public")
        val facts=SupabaseSafetyRepository(api,SignedInAuth()).account()
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
        SupabaseSafetyRepository(api,SignedInAuth()).confirmAdult()
        assertEquals("/rest/v1/rpc/confirm_adult",path)
        api.close()
    }
}
