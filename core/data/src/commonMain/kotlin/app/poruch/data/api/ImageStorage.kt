package app.poruch.data.api

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.coroutines.CancellationException

/**
 * Supabase Storage — інша служба, ніж база: свій шлях, свій публічний URL, своя відмова.
 * Тому й окремий клас: у [ApiClient] цей метод був єдиним, що не повертав JSON.
 */
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

    private companion object {
        const val BUCKET = "/storage/v1/object/event-images/"
        const val PUBLIC = "/storage/v1/object/public/event-images/"
    }
}
