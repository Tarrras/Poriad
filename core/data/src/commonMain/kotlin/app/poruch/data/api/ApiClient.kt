package app.poruch.data.api

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*
import kotlin.time.TimeSource

/**
 * Один спосіб постукати в Supabase — і більше нічого.
 *
 * Раніше цей клас заодно вантажив фото у Storage: інша служба, інший шлях, інша помилка. Тепер це
 * [ImageStorage], а тут лишився транспорт: заголовки, вимір часу, розбір відповіді. Переклад
 * серверної відмови в доменну — теж окремо, у `ApiErrors.kt`, бо це словник, а не транспорт.
 */
class ApiClient(private val client: HttpClient, private val baseUrl: String, private val key: String) {
    val json = Json { ignoreUnknownKeys = true; isLenient = false }

    suspend fun request(
        path: String,
        method: HttpMethod = HttpMethod.Get,
        payload: JsonElement? = null,
        token: String? = null,
        query: Map<String, String> = emptyMap(),
        prefer: String = "return=representation"
    ): JsonElement {
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
            PoruchLog.d("http") { "${method.value} $path → ${response.status.value} in ${started.elapsedNow().inWholeMilliseconds}ms" }
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

    fun close() = client.close()
}
