package app.poruch.data.api

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.coroutines.CancellationException

/** Завантаження в Supabase Storage. Окремо від [ApiClient]: інший шлях, публічний URL і помилки. */
class ImageStorage(private val client: HttpClient, private val baseUrl: String, private val key: String) {
    suspend fun upload(path: String, bytes: ByteArray, mime: String, token: String): String {
        if (key.isBlank()) fail(AppError.NotConfigured)
        try {
            val response = client.post(baseUrl.trimEnd('/') + BUCKET + path) {
                header("apikey", key); bearerAuth(token); contentType(ContentType.parse(mime)); setBody(bytes)
            }
            if (!response.status.isSuccess()) throw apiFailure(response.status.value, response.bodyAsText())
            return baseUrl.trimEnd('/') + PUBLIC + path
        } catch (e: CancellationException) { throw e }
        catch (e: AppFailure) { throw e }
        catch (e: Exception) { fail(AppError.ImageUploadFailed) }
    }

    /** Видаляє файл за публічною адресою, яку повернув [upload]. Чуже посилання — нічого. */
    suspend fun delete(url: String, token: String) {
        val prefix = baseUrl.trimEnd('/') + PUBLIC
        if (!url.startsWith(prefix)) return
        val response = client.delete(baseUrl.trimEnd('/') + BUCKET + url.removePrefix(prefix)) {
            header("apikey", key); bearerAuth(token)
        }
        if (!response.status.isSuccess()) throw apiFailure(response.status.value, response.bodyAsText())
    }

    private companion object {
        const val BUCKET = "/storage/v1/object/event-images/"
        const val PUBLIC = "/storage/v1/object/public/event-images/"
    }
}
