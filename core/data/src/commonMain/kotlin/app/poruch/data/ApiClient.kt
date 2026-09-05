package app.poruch.data

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*

class ApiClient(private val client: HttpClient, private val baseUrl: String, private val key: String) {
    val json = Json { ignoreUnknownKeys = true; isLenient = false }
    suspend fun request(path: String, method: HttpMethod = HttpMethod.Get, payload: JsonElement? = null, token: String? = null, query: Map<String, String> = emptyMap(), prefer: String = "return=representation"): JsonElement {
        if (key.isBlank()) throw AppException(Failure.VALIDATION, "Додайте публічний ключ Supabase у конфігурацію")
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
            if (!response.status.isSuccess()) throw apiFailure(response.status.value, text)
            return if (text.isBlank()) JsonNull else json.parseToJsonElement(text)
        } catch (e: CancellationException) { throw e }
        catch (e: AppException) { throw e }
        catch (e: Exception) { throw AppException(Failure.NETWORK, "Немає зв’язку. Перевірте інтернет і спробуйте ще раз") }
    }
    suspend fun upload(path: String, bytes: ByteArray, mime: String, token: String): String {
        try {
            val response=client.post(baseUrl.trimEnd('/') + "/storage/v1/object/event-images/" + path) {
                header("apikey",key); bearerAuth(token); contentType(ContentType.parse(mime)); setBody(bytes)
            }
            if(!response.status.isSuccess()) throw apiFailure(response.status.value,response.bodyAsText())
            return baseUrl.trimEnd('/') + "/storage/v1/object/public/event-images/" + path
        } catch(e: CancellationException) { throw e }
        catch(e: AppException) { throw e }
        catch(e: Exception) { throw AppException(Failure.NETWORK,"Не вдалося завантажити зображення") }
    }
    fun close() = client.close()
}
internal fun apiFailure(status: Int, body: String): AppException {
    val lower = body.lowercase()
    return when {
        status == 401 -> AppException(Failure.AUTH, "Увійдіть у свій обліковий запис")
        "full" in lower || "capacity" in lower -> AppException(Failure.FULL, "Вільних місць уже немає або місткість замала")
        "cancelled" in lower || "canceled" in lower -> AppException(Failure.CANCELLED, "Подію скасовано")
        status == 403 -> AppException(Failure.FORBIDDEN, "Ця дія доступна лише власнику")
        "invalid login" in lower -> AppException(Failure.AUTH, "Перевірте email і пароль")
        "email not confirmed" in lower -> AppException(Failure.AUTH, "Підтвердьте email за посиланням у листі")
        status == 429 -> AppException(Failure.UNKNOWN, "Забагато спроб. Спробуйте трохи пізніше")
        status in 400..499 -> AppException(Failure.VALIDATION, "Не вдалося виконати дію. Перевірте дані та час події")
        else -> AppException(Failure.UNKNOWN, "Сервіс тимчасово недоступний. Спробуйте ще раз")
    }
}
internal fun JsonObject.string(key: String) = this[key]?.jsonPrimitive?.contentOrNull.orEmpty()
