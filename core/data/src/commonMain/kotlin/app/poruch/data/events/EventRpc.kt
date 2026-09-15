package app.poruch.data.events

import app.poruch.data.api.ApiClient
import app.poruch.domain.*
import io.ktor.http.HttpMethod
import kotlinx.serialization.json.*

/** Спільний канал до RPC подій: `POST /rest/v1/rpc/<name>` з токеном сесії. Одне місце для шляху й розбору. */
internal class EventRpc(private val api: ApiClient, private val auth: AuthRepository) {
    val json get() = api.json

    /** PostgREST чекає тіло навіть у функції без аргументів. */
    private val noParams = JsonObject(emptyMap())

    /** Запис: приєднатися, створити, скасувати. Не повторюється, див. [read]. */
    suspend fun call(name: String, params: JsonObject = noParams): JsonElement =
        api.request("/rest/v1/rpc/$name", HttpMethod.Post, params, auth.accessToken())

    /** Читання: повторюється після збою шлюзу. Транспорт POST від POST не відрізнить, тому окрема функція. */
    suspend fun read(name: String, params: JsonObject = noParams): JsonElement =
        api.request("/rest/v1/rpc/$name", HttpMethod.Post, params, auth.accessToken(), idempotent = true)

    suspend fun events(name: String, params: JsonObject = noParams): List<Event> =
        json.decodeFromJsonElement<List<EventDto>>(read(name, params)).map { it.domain() }

    /** Гостю сервер відмовив би, тож не питаємо: порожній список — відповідь, а не помилка. */
    suspend fun people(name: String, params: JsonObject): List<Attendee> {
        if (auth.session.value == null) return emptyList()
        return json.decodeFromJsonElement<List<AttendeeDto>>(read(name, params)).map { it.domain() }
    }

    fun eventParams(id: String) = buildJsonObject { put("p_event_id", id) }
}

/** PostgREST: функції з такою сигнатурою на сервері немає. Так відрізняємо стару базу від відмови. */
internal fun Throwable.isMissingFunction() = (this as? AppFailure)?.serverCode == "PGRST202"
