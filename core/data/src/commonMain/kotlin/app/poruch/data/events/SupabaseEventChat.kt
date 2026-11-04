package app.poruch.data.events

import app.poruch.data.api.ImageStorage
import app.poruch.domain.AppError
import app.poruch.domain.AppFailure
import app.poruch.domain.AuthRepository
import app.poruch.domain.ChatMessage
import app.poruch.domain.ChatRules
import app.poruch.domain.ChatUnread
import app.poruch.domain.EventChat
import app.poruch.domain.ImageRules
import app.poruch.domain.QuestionThread
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import app.poruch.domain.fail
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** Чат події через RPC. Хто читає й пише — вирішує сервер; тут лише транспорт. Скріншоти оплати — Storage. */
internal class SupabaseEventChat(
    private val rpc: EventRpc,
    private val auth: AuthRepository,
    private val storage: ImageStorage
) : EventChat {

    // `p_thread` лише для розмови: без нього той самий запит іде й на сервер до 20261116 (загальний чат).
    override suspend fun messages(eventId: String, after: String?, thread: String?): List<ChatMessage> =
        rpc.json.decodeFromJsonElement(
            ListSerializer(ChatMessageDto.serializer()),
            rpc.read("event_messages", buildJsonObject {
                put("p_event_id", eventId)
                if (after != null) put("p_after", after) else put("p_after", JsonNull)
                put("p_limit", ChatRules.PAGE)
                if (thread != null) put("p_thread", thread)
            })
        ).map { it.domain() }

    override suspend fun send(eventId: String, body: String, thread: String?, image: String?): String =
        rpc.call("send_message", buildJsonObject {
            put("p_event_id", eventId); put("p_body", body)
            if (thread != null) put("p_thread", thread)
            if (image != null) put("p_image", image)
        }).jsonPrimitive.content

    @OptIn(ExperimentalUuidApi::class)
    override suspend fun uploadProof(eventId: String, jpeg: ByteArray): String {
        val me = auth.session.value?.userId ?: fail(AppError.SessionRequired)
        val token = auth.accessToken() ?: fail(AppError.SessionRequired)
        if (jpeg.isEmpty() || jpeg.size > ImageRules.MAX_BYTES) fail(AppError.ImageUploadFailed)
        // Перша тека — власник: видалення акаунта прибирає й скріншоти.
        val path = "$me/$eventId/${Uuid.random()}.jpg"
        storage.upload(path, jpeg, "image/jpeg", token, ImageStorage.PROOFS)
        return path
    }

    override suspend fun proof(path: String): ByteArray =
        storage.download(ImageStorage.PROOFS, path, auth.accessToken() ?: fail(AppError.SessionRequired))

    override suspend fun delete(messageId: String) {
        rpc.call("delete_message", buildJsonObject { put("p_message_id", messageId) })
    }

    /** Сервер без міграції `chat_unread` не має цієї функції: тоді бейджів просто нема. */
    override suspend fun unread(): List<ChatUnread> = try {
        rpc.json.decodeFromJsonElement(ListSerializer(ChatUnreadDto.serializer()), rpc.read("my_chat_unread")).map { it.domain() }
    } catch (e: CancellationException) {
        throw e
    } catch (e: AppFailure) {
        if (e.isMissingFunction()) emptyList() else throw e
    }

    override suspend fun markRead(eventId: String, thread: String?) {
        try {
            rpc.call("mark_chat_read", buildJsonObject { put("p_event_id", eventId); if (thread != null) put("p_thread", thread) })
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppFailure) {
            if (!e.isMissingFunction()) throw e
        }
    }

    override suspend fun questions(eventId: String): List<QuestionThread> = try {
        rpc.json.decodeFromJsonElement(ListSerializer(QuestionThreadDto.serializer()), rpc.read("event_questions", rpc.eventParams(eventId)))
            .map { it.domain() }
    } catch (e: CancellationException) {
        throw e
    } catch (e: AppFailure) {
        if (e.isMissingFunction()) emptyList() else throw e
    }
}
