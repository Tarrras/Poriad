package app.poruch.data.api

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Завантаження в Supabase Storage. Окремо від [ApiClient]: інший шлях, публічний URL і помилки. Бакети: [IMAGES] — фото,
 * постери відео й аватари, [VIDEOS] — відео подій (mp4), [PROOFS] — приватні скріншоти оплати ([download]).
 */
class ImageStorage(private val client: HttpClient, private val baseUrl: String, private val key: String) {
    suspend fun upload(path: String, bytes: ByteArray, mime: String, token: String, bucket: String = IMAGES): String {
        if (key.isBlank()) fail(AppError.NotConfigured)
        try {
            val response = client.post(base() + OBJECT + "$bucket/$path") {
                header("apikey", key); bearerAuth(token); contentType(ContentType.parse(mime)); setBody(bytes)
            }
            // У шляху файлу — id власника: у звіт іде лише дія.
            if (!response.status.isSuccess()) throw apiFailure(response.status.value, response.bodyAsText(), "storage upload")
            return base() + PUBLIC + "$bucket/$path"
        } catch (e: CancellationException) { throw e }
        catch (e: AppFailure) { throw e }
        catch (e: Exception) { fail(AppError.ImageUploadFailed) }
    }

    /**
     * Копія нашого файлу [url] у [path] того самого бакета («Повторити»): нова подія тримає власні файли, тож перевірка
     * теки в `assert_media` лишається суворою. Повертає публічну адресу копії. Чуже посилання — [AppError.ImageUploadFailed].
     */
    suspend fun copy(url: String, path: String, token: String): String {
        val (bucket, source) = located(url) ?: fail(AppError.ImageUploadFailed)
        try {
            val response = client.post(base() + OBJECT + "copy") {
                header("apikey", key); bearerAuth(token); contentType(ContentType.Application.Json)
                setBody(buildJsonObject { put("bucketId", bucket); put("sourceKey", source); put("destinationKey", path) }.toString())
            }
            if (!response.status.isSuccess()) throw apiFailure(response.status.value, response.bodyAsText(), "storage copy")
            return base() + PUBLIC + "$bucket/$path"
        } catch (e: CancellationException) { throw e }
        catch (e: AppFailure) { throw e }
        catch (e: Exception) { fail(AppError.ImageUploadFailed) }
    }

    /** Файл приватного бакета ([PROOFS]) з токеном людини; читати можуть лише ті, кого пускає RLS Storage. */
    suspend fun download(bucket: String, path: String, token: String): ByteArray {
        if (key.isBlank()) fail(AppError.NotConfigured)
        val response = client.get(base() + OBJECT + "authenticated/$bucket/$path") { header("apikey", key); bearerAuth(token) }
        if (!response.status.isSuccess()) throw apiFailure(response.status.value, response.bodyAsText(), "storage download")
        return response.readRawBytes()
    }

    /** Видаляє файл за публічною адресою, яку повернули [upload] чи [copy]. Чуже посилання — нічого. */
    suspend fun delete(url: String, token: String) {
        val (bucket, path) = located(url) ?: return
        val response = client.delete(base() + OBJECT + "$bucket/$path") {
            header("apikey", key); bearerAuth(token)
        }
        if (!response.status.isSuccess()) throw apiFailure(response.status.value, response.bodyAsText(), "storage delete")
    }

    /** Бакет і шлях нашого публічного файлу; чужий сервер чи бакет — null. */
    private fun located(url: String): Pair<String, String>? {
        val rest = url.takeIf { it.startsWith(base() + PUBLIC) }?.removePrefix(base() + PUBLIC) ?: return null
        val bucket = rest.substringBefore('/')
        return if (bucket in BUCKETS && '/' in rest) bucket to rest.substringAfter('/') else null
    }

    private fun base() = baseUrl.trimEnd('/')

    companion object {
        const val IMAGES = "event-images"
        const val VIDEOS = "event-videos"
        /** Скріншоти оплати в розмові з організатором: приватний, `<uid>/<подія>/<uuid>.jpg` (20261125130000). */
        const val PROOFS = "payment-proofs"
        private val BUCKETS = setOf(IMAGES, VIDEOS)
        private const val OBJECT = "/storage/v1/object/"
        private const val PUBLIC = "/storage/v1/object/public/"
    }
}
