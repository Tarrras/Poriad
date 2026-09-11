package app.poruch.data.events

import app.poruch.data.api.ImageStorage
import app.poruch.domain.*
import kotlinx.serialization.json.*
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * Свої події: створити, змінити, скасувати, додати фото. Усе це сервер дозволяє лише організаторові
 * і лише для `origin = 'community'` — імпортовану афішу не редагує ніхто, включно з її джерелом.
 */
internal class SupabaseEventAuthoring(
    private val rpc: EventRpc,
    private val auth: AuthRepository,
    private val storage: ImageStorage
) : EventAuthoring {

    override suspend fun create(id: String, draft: EventDraft): String =
        rpc.call("create_event", draftParams(id, draft)).jsonPrimitive.content

    override suspend fun update(id: String, draft: EventDraft): String =
        rpc.call("update_event", draftParams(id, draft)).jsonPrimitive.content

    override suspend fun cancel(id: String) { rpc.call("cancel_event", rpc.eventParams(id)) }

    @OptIn(ExperimentalUuidApi::class)
    override suspend fun uploadImage(eventId: String, bytes: ByteArray, contentType: String): String {
        // Тип і розмір перевіряються тут, а не після завантаження: інакше за відмову платить
        // мережа користувача.
        val extension = ImageRules.extensions[contentType]
            ?: fail(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)))
        if (bytes.isEmpty() || bytes.size > ImageRules.MAX_BYTES) {
            fail(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)))
        }
        val uid = auth.session.value?.userId ?: fail(AppError.SessionRequired)
        val token = auth.accessToken() ?: fail(AppError.SessionRequired)
        // Шлях починається з власника: політика Storage читає його з першого сегмента.
        return storage.upload("$uid/$eventId/${Uuid.random()}.$extension", bytes, contentType, token)
    }

    private fun draftParams(id: String, d: EventDraft) = buildJsonObject {
        put("p_id", id); put("p_title", d.title.trim()); put("p_description", d.description.trim())
        put("p_category", d.category); put("p_city", d.city); put("p_address", d.address)
        put("p_latitude", d.latitude); put("p_longitude", d.longitude)
        put("p_starts_at", d.startsAt); put("p_ends_at", d.endsAt); put("p_time_zone", d.timeZone)
        put("p_capacity", d.capacity)
        put("p_min_age", d.minAge); d.maxAge?.let { put("p_max_age", it) } ?: put("p_max_age", JsonNull)
        put("p_approval_required", d.approvalRequired)
        put("p_image_url", d.imageUrl?.let(::JsonPrimitive) ?: JsonNull)
    }
}
