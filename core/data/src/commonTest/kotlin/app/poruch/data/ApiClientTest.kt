package app.poruch.data
import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*
class ApiClientTest {
    @Test fun unauthorizedResponseIsTypedAuthError() = runTest {
        val client = ApiClient(HttpClient(MockEngine { respond("{}", HttpStatusCode.Unauthorized) }), "https://test.invalid", "public")
        val error = assertFailsWith<AppException> { client.request("/rest/v1/events") }
        assertEquals(Failure.AUTH, error.kind)
        client.close()
    }
    @Test fun noBearerIsSentForGuestPublishableKey() = runTest {
        val client = ApiClient(HttpClient(MockEngine { request ->
            assertNull(request.headers["Authorization"])
            assertEquals("sb_publishable_test", request.headers["apikey"])
            respond("[]", HttpStatusCode.OK)
        }), "https://test.invalid", "sb_publishable_test")
        client.request("/rest/v1/events")
        client.close()
    }
}
