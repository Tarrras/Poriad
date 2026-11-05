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

/** Ціна події від людей (20261124120000): що йде в `create_event`/`update_event` і що приходить з карток і деталей. */
class EventPriceTest {
    private val sent = mutableListOf<JsonObject>()
    private fun authoring(status: HttpStatusCode = HttpStatusCode.OK, body: String = "\"e1\"") = HttpClient(MockEngine { request ->
        sent += Json.parseToJsonElement(request.body.toByteArray().decodeToString().ifEmpty { "{}" }) as? JsonObject ?: JsonObject(emptyMap())
        respond(body, status, headersOf(HttpHeaders.ContentType, "application/json"))
    }).let { http ->
        val auth = SignedInAuth()
        SupabaseEventAuthoring(EventRpc(ApiClient(http, "https://test.invalid", "public"), auth), auth, ImageStorage(http, "https://test.invalid", "public"))
    }
    private val draft = EventDraft("Клуб", "Читаємо разом за чаєм", EventCategory.SOCIAL, "Київ", "Поділ", 50.45, 30.52,
        "2090-01-06T17:00:00Z", "2090-01-06T19:00:00Z", "Europe/Kyiv", 12)

    /** Ціна йде завжди: без неї — 0, і правка прибирає стару ціну (null сервер читає як старий клієнт). */
    @Test fun thePriceIsAlwaysSent() = runTest {
        authoring().create("e1", draft.copy(price = 300))
        assertEquals(300, sent.last()["p_price"]!!.jsonPrimitive.int)
        authoring().update("e1", draft)
        assertEquals(0, sent.last()["p_price"]!!.jsonPrimitive.int)
    }

    /** Коли платять — завжди явно: false повертає «на зустрічі»; без ціни передоплати не буває. */
    @Test fun prepayIsAlwaysSent() = runTest {
        authoring().create("e1", draft.copy(price = 300, prepay = true))
        assertTrue(sent.last()["p_prepay"]!!.jsonPrimitive.boolean)
        authoring().update("e1", draft.copy(prepay = true))
        assertFalse(sent.last()["p_prepay"]!!.jsonPrimitive.boolean)
        val json = Json { ignoreUnknownKeys = true }
        val base = """"id":"e1","title":"Клуб","category":"social","city":"Київ","address":"Поділ","starts_at":"2090-01-06T17:00:00Z",
            "ends_at":"2090-01-06T19:00:00Z","time_zone":"Europe/Kyiv","status":"published","latitude":50.0,"longitude":30.0,
            "origin":"community","organizer_id":"o1","capacity":12"""
        assertTrue(json.decodeFromString<EventDto>("""{$base,"price_min":300,"prepay":true}""").domain().gathering!!.prepay)
        assertFalse(json.decodeFromString<EventDto>("""{$base,"price_min":300}""").domain().gathering!!.prepay)
    }

    @Test fun aRefusedPriceNamesTheField() = runTest {
        val error = assertFailsWith<AppFailure> {
            authoring(HttpStatusCode.BadRequest, """{"code":"22023","message":"INVALID_PRICE"}""").update("e1", draft)
        }.error
        assertEquals(AppError.InvalidDraft(listOf(DraftField.PRICE)), error)
    }

    /** `price_min` спільний з афішею: у події від людей — точна ціна, 0 чи порожньо — безкоштовно. */
    @Test fun aCommunityEventCarriesItsPrice() {
        val json = Json { ignoreUnknownKeys = true }
        val base = """"id":"e1","title":"Клуб","category":"social","city":"Київ","address":"Поділ","starts_at":"2090-01-06T17:00:00Z",
            "ends_at":"2090-01-06T19:00:00Z","time_zone":"Europe/Kyiv","status":"published","latitude":50.0,"longitude":30.0,
            "origin":"community","organizer_id":"o1","capacity":12"""
        assertEquals(300, json.decodeFromString<EventDto>("""{$base,"price_min":300}""").domain().gathering!!.price)
        assertNull(json.decodeFromString<EventDto>("""{$base,"price_min":0}""").domain().gathering!!.price)
        assertNull(json.decodeFromString<EventDto>("{$base}").domain().gathering!!.price)
    }

    /** Оплата онлайн (docs/organizer-events.md): лише з ціною; старий сервер поля не несе — на місці. */
    @Test fun payOnlineNeedsAPrice() {
        val json = Json { ignoreUnknownKeys = true }
        val base = """"id":"e1","title":"Клуб","category":"social","city":"Київ","address":"Поділ","starts_at":"2090-01-06T17:00:00Z",
            "ends_at":"2090-01-06T19:00:00Z","time_zone":"Europe/Kyiv","status":"published","latitude":50.0,"longitude":30.0,
            "origin":"community","organizer_id":"o1","capacity":12"""
        assertTrue(json.decodeFromString<EventDto>("""{$base,"price_min":300,"pay_online":true}""").domain().gathering!!.payOnline)
        assertFalse(json.decodeFromString<EventDto>("""{$base,"price_min":300}""").domain().gathering!!.payOnline)
        assertFalse(json.decodeFromString<EventDto>("""{$base,"pay_online":true}""").domain().gathering!!.payOnline)
    }
}
