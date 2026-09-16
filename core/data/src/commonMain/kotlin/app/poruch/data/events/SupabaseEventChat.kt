package app.poruch.data.events

import app.poruch.domain.AppFailure
import app.poruch.domain.ChatMessage
import app.poruch.domain.ChatRules
import app.poruch.domain.ChatUnread
import app.poruch.domain.EventChat
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Чат події через RPC. Хто читає й пише — вирішує сервер; тут лише транспорт. */
internal class SupabaseEventChat(private val rpc: EventRpc) : EventChat {

    override suspend fun messages(eventId: String, after: String?): List<ChatMessage> =
        rpc.json.decodeFromJsonElement(
            ListSerializer(ChatMessageDto.serializer()),
            rpc.read("event_messages", buildJsonObject {
                put("p_event_id", eventId)
                if (after != null) put("p_after", after) else put("p_after", JsonNull)
                put("p_limit", ChatRules.PAGE)
            })
        ).map { it.domain() }

    override suspend fun send(eventId: String, body: String): String =
        rpc.call("send_message", buildJsonObject { put("p_event_id", eventId); put("p_body", body) }).jsonPrimitive.content

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

    override suspend fun markRead(eventId: String) {
        try {
            rpc.call("mark_chat_read", rpc.eventParams(eventId))
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppFailure) {
            if (!e.isMissingFunction()) throw e
        }
    }
}
