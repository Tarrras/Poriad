package app.poruch.data

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*
import kotlin.time.TimeSource

class ApiClient(private val client: HttpClient, private val baseUrl: String, private val key: String) {
    val json = Json { ignoreUnknownKeys = true; isLenient = false }
    suspend fun request(path: String, method: HttpMethod = HttpMethod.Get, payload: JsonElement? = null, token: String? = null, query: Map<String, String> = emptyMap(), prefer: String = "return=representation"): JsonElement {
        if (key.isBlank()) fail(AppError.NotConfigured)
        // Paths and statuses only: a request body here can hold a password or a session token.
        val started = TimeSource.Monotonic.markNow()
        try {
            val response = client.request(baseUrl.trimEnd('/') + path) {
                this.method = method
                header("apikey", key)
                if (token != null) bearerAuth(token)
                header("Prefer", prefer)
                contentType(ContentType.Application.Json)
                query.forEach { (k, v) -> parameter(k, v) }
                if (payload != null) setBody(payload.toString())
            }
            val text = response.bodyAsText()
            PoruchLog.d("http") { "${method.value} $path \u2192 ${response.status.value} in ${started.elapsedNow().inWholeMilliseconds}ms" }
            if (!response.status.isSuccess()) throw apiFailure(response.status.value, text)
            return if (text.isBlank()) JsonNull else json.parseToJsonElement(text)
        } catch (e: CancellationException) { throw e }
        catch (e: AppFailure) {
            PoruchLog.w("http") { "${method.value} $path failed: ${e.error}" }
            throw e
        }
        catch (e: Exception) {
            PoruchLog.e("http", e) { "${method.value} $path unreachable after ${started.elapsedNow().inWholeMilliseconds}ms" }
            fail(AppError.Network)
        }
    }
    suspend fun upload(path: String, bytes: ByteArray, mime: String, token: String): String {
        try {
            val response=client.post(baseUrl.trimEnd('/') + "/storage/v1/object/event-images/" + path) {
                header("apikey",key); bearerAuth(token); contentType(ContentType.parse(mime)); setBody(bytes)
            }
            if(!response.status.isSuccess()) throw apiFailure(response.status.value,response.bodyAsText())
            return baseUrl.trimEnd('/') + "/storage/v1/object/public/event-images/" + path
        } catch(e: CancellationException) { throw e }
        catch(e: AppFailure) { throw e }
        catch(e: Exception) { fail(AppError.ImageUploadFailed) }
    }
    fun close() = client.close()
}
/**
 * Maps a PostgREST / GoTrue failure onto a domain case. The server signals with codes and
 * `raise exception 'NAME'`, so the match is on those, never on wording — and nothing user-facing
 * is decided here.
 */
internal fun apiFailure(status: Int, body: String): AppFailure {
    val lower = body.lowercase()
    val error = when {
        "organizer_cannot_join" in lower -> AppError.OrganizerCannotJoin
        "already_member" in lower -> AppError.AlreadyMember
        "event_has_space" in lower -> AppError.EventHasSpace
        "full" in lower || "capacity" in lower -> AppError.EventFull
        "cancelled" in lower || "canceled" in lower -> AppError.EventCancelled
        "not_organizer" in lower -> AppError.NotOwner
        "invalid login" in lower -> AppError.InvalidCredentials
        "email not confirmed" in lower -> AppError.EmailNotConfirmed
        status == 401 -> AppError.SessionRequired
        status == 403 -> AppError.NotOwner
        status == 429 -> AppError.TooManyAttempts
        status in 400..499 -> AppError.Rejected
        else -> AppError.ServiceUnavailable
    }
    return AppFailure(error)
}

internal fun JsonObject.string(key: String) = this[key]?.jsonPrimitive?.contentOrNull.orEmpty()
