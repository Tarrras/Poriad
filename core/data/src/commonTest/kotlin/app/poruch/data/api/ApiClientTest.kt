package app.poruch.data.api
import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlin.test.*
class ApiClientTest {
    @Test fun unauthorizedResponseIsTypedAuthError() = runTest {
        val client = ApiClient(HttpClient(MockEngine { respond("{}", HttpStatusCode.Unauthorized) }), "https://test.invalid", "public")
        val error = assertFailsWith<AppFailure> { client.request("/rest/v1/events") }
        assertEquals(AppError.SessionRequired, error.error)
        client.close()
    }
    @Test fun samePasswordRefusalIsTyped() = runTest {
        val body = """{"code":422,"error_code":"same_password","msg":"New password should be different from the old password."}"""
        val client = ApiClient(HttpClient(MockEngine { respond(body, HttpStatusCode.UnprocessableEntity) }), "https://test.invalid", "public")
        val error = assertFailsWith<AppFailure> { client.request("/auth/v1/user", HttpMethod.Put) }
        assertEquals(AppError.SamePassword, error.error)
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

    // ---- Повтор після збою шлюзу: 504 на закритому з'єднанні, який база навіть не помітила.

    private fun counting(vararg answers: HttpStatusCode, calls: IntArray) = HttpClient(MockEngine {
        val answer = answers[minOf(calls[0], answers.lastIndex)]
        calls[0]++
        respond(if (answer.isSuccess()) "[]" else "{}", answer)
    })

    @Test fun aReadIsRetriedOnceAfterAGatewayTimeout() = runTest {
        val calls = IntArray(1)
        val client = ApiClient(counting(HttpStatusCode.GatewayTimeout, HttpStatusCode.OK, calls = calls), "https://test.invalid", "public")
        val body = client.request("/rest/v1/rpc/event_details", HttpMethod.Post, idempotent = true)
        assertEquals(JsonArray(emptyList()), body)
        assertEquals(2, calls[0], "один повтор, і відповідь уже є")
        client.close()
    }

    @Test fun aWriteIsNeverRetried() = runTest {
        // `join_event` із загубленою відповіддю вдруге дав би дубль.
        val calls = IntArray(1)
        val client = ApiClient(counting(HttpStatusCode.GatewayTimeout, HttpStatusCode.OK, calls = calls), "https://test.invalid", "public")
        val error = assertFailsWith<AppFailure> { client.request("/rest/v1/rpc/join_event", HttpMethod.Post) }
        assertEquals(AppError.ServiceUnavailable, error.error)
        assertEquals(1, calls[0])
        client.close()
    }

    @Test fun aDatabaseErrorIsNotRetried() = runTest {
        // 500 — відповідь самої бази; повтор лише подвоїв би навантаження.
        val calls = IntArray(1)
        val client = ApiClient(counting(HttpStatusCode.InternalServerError, HttpStatusCode.OK, calls = calls), "https://test.invalid", "public")
        assertFailsWith<AppFailure> { client.request("/rest/v1/events") }
        assertEquals(1, calls[0])
        client.close()
    }

    @Test fun aReadGivesUpAfterOneRetry() = runTest {
        val calls = IntArray(1)
        val client = ApiClient(counting(HttpStatusCode.ServiceUnavailable, calls = calls), "https://test.invalid", "public")
        val error = assertFailsWith<AppFailure> { client.request("/rest/v1/events") }
        assertEquals(AppError.ServiceUnavailable, error.error)
        assertEquals(2, calls[0], "один повтор, не черга")
        client.close()
    }

    @Test fun aDroppedConnectionIsRetriedForAReadButNotForAWrite() = runTest {
        fun dropping(calls: IntArray) = HttpClient(MockEngine {
            calls[0]++
            if (calls[0] == 1) error("connection reset") else respond("[]", HttpStatusCode.OK)
        })
        val reads = IntArray(1)
        val reader = ApiClient(dropping(reads), "https://test.invalid", "public")
        reader.request("/rest/v1/saved_events")
        assertEquals(2, reads[0])
        reader.close()

        val writes = IntArray(1)
        val writer = ApiClient(dropping(writes), "https://test.invalid", "public")
        val error = assertFailsWith<AppFailure> { writer.request("/rest/v1/saved_events", HttpMethod.Post) }
        assertEquals(AppError.Network, error.error)
        assertEquals(1, writes[0])
        writer.close()
    }
}
