package app.poruch.data.api

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.serialization.json.*
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeSource

/**
 * Транспорт до Supabase: заголовки, вимір часу, розбір відповіді. Фото вантажить [ImageStorage],
 * серверні відмови в доменні перекладає `ApiErrors.kt`.
 */
class ApiClient(private val client: HttpClient, private val baseUrl: String, private val key: String) {
    // `explicitNulls = false` — відсутнє поле як null; `coerceInputValues` — null або невідоме
    // значення enum у полі з дефолтом бере дефолт, а не валить увесь список подій.
    val json = Json { ignoreUnknownKeys = true; isLenient = false; explicitNulls = false; coerceInputValues = true }

    /**
     * Дає свіжий токен замість відхиленого (401): один примусовий refresh і один повтор запиту.
     * Ставить [app.poruch.data.account.SupabaseAuthRepository]; null — повторів нема.
     */
    var reauthorize: (suspend (rejected: String) -> String?)? = null

    suspend fun request(
        path: String,
        method: HttpMethod = HttpMethod.Get,
        payload: JsonElement? = null,
        token: String? = null,
        query: Map<String, String> = emptyMap(),
        prefer: String = "return=representation",
        /**
         * Чи безпечно повторити запит (див. [TRANSIENT]). За замовчуванням лише GET; читальні
         * RPC — це POST, тож позначають себе самі (`EventRpc.read`). Запис не повторюємо ніколи:
         * `join_event` із загубленою відповіддю вдруге дав би дубль.
         */
        idempotent: Boolean = method == HttpMethod.Get,
        /**
         * Чи можна на 401 оновити [token] і повторити. Ні — коли токен чужий для поточної сесії
         * (зняття пуш-токена акаунта, що вже вийшов) або запит іде зсередини м'ютекса сесії.
         */
        reauthorizable: Boolean = true
    ): JsonElement {
        if (key.isBlank()) fail(AppError.NotConfigured)
        var retriesLeft = if (idempotent) RETRIES else 0
        var token = token
        var reauthorized = !reauthorizable
        while (true) {
            // У лог ідуть лише шлях і статус: у тілі може бути пароль або токен.
            val started = TimeSource.Monotonic.markNow()
            val (status, text) = try {
                client.request(baseUrl.trimEnd('/') + path) {
                    this.method = method
                    header("apikey", key)
                    if (token != null) bearerAuth(token)
                    header("Prefer", prefer)
                    contentType(ContentType.Application.Json)
                    query.forEach { (k, v) -> parameter(k, v) }
                    if (payload != null) setBody(payload.toString())
                }.let { it.status to it.bodyAsText() }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) {
                PoruchLog.e("http", e) { "${method.value} $path unreachable after ${started.elapsedNow().inWholeMilliseconds}ms" }
                if (retriesLeft-- > 0) { delay(RETRY_DELAY); continue }
                fail(AppError.Network)
            }
            PoruchLog.d("http") { "${method.value} $path → ${status.value} in ${started.elapsedNow().inWholeMilliseconds}ms" }
            if (status.value in TRANSIENT && retriesLeft-- > 0) {
                PoruchLog.w("http") { "${method.value} $path → ${status.value}, retrying once" }
                delay(RETRY_DELAY)
                continue
            }
            // Токен прострочився раніше, ніж думав годинник пристрою: оновлюємо і повторюємо раз.
            // Запис теж: 401 означає, що база його не бачила.
            if (status.value == 401 && token != null && !reauthorized) {
                reauthorized = true
                val fresh = try { reauthorize?.invoke(token) } catch (e: CancellationException) { throw e } catch (e: Exception) { null }
                if (fresh != null && fresh != token) {
                    PoruchLog.w("http") { "${method.value} $path → 401, retrying with a refreshed token" }
                    token = fresh
                    continue
                }
            }
            if (!status.isSuccess()) {
                val failure = apiFailure(status.value, text)
                PoruchLog.w("http") { "${method.value} $path failed: ${failure.error}" }
                throw failure
            }
            return try {
                if (text.isBlank()) JsonNull else json.parseToJsonElement(text)
            } catch (e: Exception) {
                PoruchLog.e("http", e) { "${method.value} $path returned unreadable body" }
                fail(AppError.Network)
            }
        }
    }

    fun close() = client.close()

    private companion object {
        /**
         * Статуси «до бази не дійшли»: шлюз Supabase часом віддає 504 на щойно закрите з'єднання
         * PostgREST. 500 сюди не входить — це відповідь самої бази, повтор лише подвоїв би навантаження.
         */
        val TRANSIENT = setOf(502, 503, 504)

        /** Один повтор лікує гонку з'єднань, довша черга лише затягує відмову. */
        const val RETRIES = 1

        /** Досить, щоб шлюз узяв свіже з'єднання, замало, щоб людина помітила. */
        val RETRY_DELAY = 300.milliseconds
    }
}
