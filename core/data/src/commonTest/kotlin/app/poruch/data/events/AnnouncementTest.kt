package app.poruch.data.events

import app.poruch.data.SignedInAuth
import app.poruch.data.api.ApiClient
import app.poruch.data.api.ImageStorage
import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import kotlin.test.*

/** Клієнт `parse-announcement` (docs/organizers-1.5.md, 1.4): що йде у функцію і як відповідь стає полями чернетки. */
class AnnouncementTest {
    private fun authoring(status: HttpStatusCode, body: String, check: suspend (io.ktor.client.request.HttpRequestData) -> Unit = {}) =
        HttpClient(MockEngine { request ->
            check(request)
            respond(body, status, headersOf(HttpHeaders.ContentType, "application/json"))
        }).let { http ->
            val auth = SignedInAuth()
            SupabaseEventAuthoring(EventRpc(ApiClient(http, "https://test.invalid", "public"), auth), auth, ImageStorage(http, "https://test.invalid", "public"))
        }

    /** Без сесії (функцію кличе й гість), місцевий час форми — в UTC, адреса — рядком. */
    @Test fun fieldsComeBackInDraftTerms() = runTest {
        val fill = authoring(HttpStatusCode.OK, """{"title":"Книжковий клуб","description":"Читаємо разом","category":"social",
            "starts_at":"2026-11-07T19:00","ends_at":"2026-11-07T21:30","place":"Пекарня Протісто","capacity":20,"min_age":18,
            "contact_url":"https://t.me/club"}""") { request ->
            assertEquals("/functions/v1/parse-announcement", request.url.encodedPath)
            assertNull(request.headers[HttpHeaders.Authorization])
            val sent = Json.parseToJsonElement(request.body.toByteArray().decodeToString()).jsonObject
            assertEquals(listOf("text", "city", "today", "tz"), sent.keys.toList())
            assertEquals("Europe/Kyiv", sent["tz"]!!.jsonPrimitive.content)
        }.announcement("Анонс", "Київ", "2026-11-01", "Europe/Kyiv")
        assertEquals("2026-11-07T17:00:00Z", fill.startsAt)
        assertEquals("2026-11-07T19:30:00Z", fill.endsAt)
        assertEquals(EventCategory.SOCIAL, fill.category)
        assertEquals("Пекарня Протісто", fill.address)
        assertEquals(AnnounceField.entries.toList(), fill.filled)
        assertNull(fill.failure)
    }

    @Test fun onlyTheTitleAndDescriptionAreGuaranteed() = runTest {
        val fill = authoring(HttpStatusCode.OK, """{"title":"Клуб","description":"Текст","category":"karaoke"}""")
            .announcement("Клуб\nТекст", "Київ", "2026-11-01", "Europe/Kyiv")
        assertEquals(listOf(AnnounceField.TITLE, AnnounceField.DESCRIPTION), fill.filled)
    }

    @Test fun theLimitAndFailuresAreNamed() = runTest {
        assertEquals(AppError.TooManyAttempts, assertFailsWith<AppFailure> {
            authoring(HttpStatusCode.TooManyRequests, """{"error":"rate limited"}""").announcement("А", "Київ", "2026-11-01", "Europe/Kyiv")
        }.error)
        assertEquals(AppError.ServiceUnavailable, assertFailsWith<AppFailure> {
            authoring(HttpStatusCode.OK, """{"error":"failed"}""").announcement("А", "Київ", "2026-11-01", "Europe/Kyiv")
        }.error, "an answer off the schema is a failure, not empty fields")
    }
}
