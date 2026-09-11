package app.poruch.data.events

import app.poruch.data.api.ApiClient
import app.poruch.domain.*
import io.ktor.http.HttpMethod
import kotlinx.serialization.json.*

/**
 * Спільний канал до подій: усе, що робить сервер з подіями, — це `POST /rest/v1/rpc/<name>` з
 * токеном поточної сесії.
 *
 * Класи навколо різні, бо різні їхні права й обов'язки; спосіб постукати в базу — один, і саме він
 * тут. Без цього кожна з п'яти граней носила б власну копію рядка шляху й розбору відповіді, а
 * зміна контракту вимагала б п'яти однакових правок.
 */
internal class EventRpc(private val api: ApiClient, private val auth: AuthRepository) {
    val json get() = api.json

    /** Порожні параметри теж треба надіслати: PostgREST чекає тіло навіть у функції без аргументів. */
    private val noParams = JsonObject(emptyMap())

    suspend fun call(name: String, params: JsonObject = noParams): JsonElement =
        api.request("/rest/v1/rpc/$name", HttpMethod.Post, params, auth.accessToken())

    suspend fun events(name: String, params: JsonObject = noParams): List<Event> =
        json.decodeFromJsonElement<List<EventDto>>(call(name, params)).map { it.domain() }

    /**
     * Люди приходять лише тому, хто має право їх бачити. Гостю сервер відмовив би, тож ми його
     * навіть не питаємо — порожній список тут не помилка, а відповідь.
     */
    suspend fun people(name: String, params: JsonObject): List<Attendee> {
        if (auth.session.value == null) return emptyList()
        return json.decodeFromJsonElement<List<AttendeeDto>>(call(name, params)).map { it.domain() }
    }

    fun eventParams(id: String) = buildJsonObject { put("p_event_id", id) }
}
