package app.poruch.data.events

import app.poruch.data.SignedInAuth
import app.poruch.data.api.ApiClient
import app.poruch.data.api.ImageStorage
import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.client.request.HttpRequestData
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import kotlin.test.*

/** Фото й відео події (docs/organizers-1.5.md, 1.3 і хвиля 2): що йде в `create_event` і Storage, що приходить з деталей. */
class EventMediaTest {
    private val base = "https://test.invalid"
    private val requests = mutableListOf<Pair<HttpRequestData, String>>()
    private fun authoring(respond: (HttpRequestData) -> String = { "\"e1\"" }): SupabaseEventAuthoring {
        val http = HttpClient(MockEngine { request ->
            requests += request to request.body.toByteArray().decodeToString()
            respond(respond(request), HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
        })
        val auth = SignedInAuth()
        return SupabaseEventAuthoring(EventRpc(ApiClient(http, base, "public"), auth), auth, ImageStorage(http, base, "public"))
    }
    private val draft = EventDraft("Прогулянка", "Зустріч у центрі міста", EventCategory.OUTDOORS, "Київ", "Поділ", 50.45, 30.5,
        "2090-01-01T10:00:00Z", "2090-01-01T12:00:00Z", "Europe/Kyiv", 10)

    /** `p_media` завжди, і лише те, що вже в теці події: нове вантажиться після створення. */
    @Test fun createSendsOnlyRemoteMedia() = runTest {
        val video = EventMedia(MediaKind.VIDEO, "$base/storage/v1/object/public/event-videos/u1/e1/v.mp4", "$base/storage/v1/object/public/event-images/u1/e1/p.jpg")
        authoring().create("e1", draft.copy(media = listOf(
            DraftMedia.Local("a", MediaKind.PHOTO, byteArrayOf(1)), DraftMedia.Remote(video),
            DraftMedia.Copied(EventMedia(MediaKind.PHOTO, "$base/x.jpg"))
        )))
        val media = Json.parseToJsonElement(requests.single().second).jsonObject["p_media"]!!.jsonArray
        assertEquals(1, media.size)
        assertEquals("video", media[0].jsonObject["kind"]!!.jsonPrimitive.content)
        assertEquals(video.poster, media[0].jsonObject["poster"]!!.jsonPrimitive.content)

        authoring().create("e2", draft)
        assertEquals(JsonArray(emptyList()), Json.parseToJsonElement(requests.last().second).jsonObject["p_media"], "empty, not missing")
    }

    @Test fun videosGoToTheirOwnBucket() = runTest {
        val url = authoring().uploadVideo("e1", byteArrayOf(1, 2))
        val (request, _) = requests.single()
        assertTrue(request.url.encodedPath.startsWith("/storage/v1/object/event-videos/u1/e1/"))
        assertTrue(request.url.encodedPath.endsWith(".mp4"))
        assertEquals("video/mp4", request.body.contentType?.toString())
        assertTrue(url.startsWith("$base/storage/v1/object/public/event-videos/u1/e1/"))
        assertEquals(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)),
            assertFailsWith<AppFailure> { authoring().uploadVideo("e1", ByteArray(MediaRules.VIDEO_MAX_BYTES + 1)) }.error)
    }

    /** «Повторити»: Storage `copy` у теку нової події, той самий бакет, нове імʼя. */
    @Test fun copyingKeepsTheBucket() = runTest {
        val url = authoring { "{\"Key\":\"x\"}" }.copyMedia("$base/storage/v1/object/public/event-videos/u1/old/v.mp4", "new")
        val (request, body) = requests.single()
        assertEquals("/storage/v1/object/copy", request.url.encodedPath)
        val sent = Json.parseToJsonElement(body).jsonObject
        assertEquals("event-videos", sent["bucketId"]!!.jsonPrimitive.content)
        assertEquals("u1/old/v.mp4", sent["sourceKey"]!!.jsonPrimitive.content)
        val destination = sent["destinationKey"]!!.jsonPrimitive.content
        assertTrue(destination.startsWith("u1/new/") && destination.endsWith(".mp4"))
        assertEquals("$base/storage/v1/object/public/event-videos/$destination", url)
        assertFailsWith<AppFailure>("not our file") { authoring().copyMedia("https://elsewhere.invalid/v.mp4", "new") }
    }

    @Test fun deletingFindsTheBucket() = runTest {
        authoring { "{}" }.deleteImage("$base/storage/v1/object/public/event-videos/u1/e1/v.mp4")
        assertEquals("/storage/v1/object/event-videos/u1/e1/v.mp4", requests.single().first.url.encodedPath)
        assertEquals(HttpMethod.Delete, requests.single().first.method)
    }

    /** З `event_details`: порядок організатора; невідомий вид і відео без постера — не показуємо. */
    @Test fun detailsCarryTheMedia() {
        val row = """{"id":"e1","title":"Т","category":"music","city":"Київ","address":"А","starts_at":"2030-01-01T10:00:00Z",
            "ends_at":"2030-01-01T12:00:00Z","time_zone":"Europe/Kyiv","status":"published","latitude":50.0,"longitude":30.0,
            "media":[{"kind":"video","url":"https://s/v.mp4","poster":"https://s/p.jpg"},{"kind":"photo","url":"https://s/1.jpg"},
            {"kind":"gif","url":"https://s/g.gif"},{"kind":"video","url":"https://s/nop.mp4"}]}"""
        val event = Json { ignoreUnknownKeys = true }.decodeFromString<EventDto>(row).domain()
        assertEquals(listOf(EventMedia(MediaKind.VIDEO, "https://s/v.mp4", "https://s/p.jpg"), EventMedia(MediaKind.PHOTO, "https://s/1.jpg")), event.media)
    }
}
