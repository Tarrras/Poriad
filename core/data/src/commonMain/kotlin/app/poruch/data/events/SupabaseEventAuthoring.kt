package app.poruch.data.events

import app.poruch.data.api.ImageStorage
import app.poruch.domain.*
import kotlinx.serialization.json.*
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** Свої події: створити, змінити, скасувати, додати фото. Лише організатор і лише `origin = 'community'`. */
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
        // Тип і розмір перевіряємо до завантаження, щоб не ганяти трафік дарма.
        val extension = ImageRules.extensions[contentType]
            ?: fail(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)))
        if (bytes.isEmpty() || bytes.size > ImageRules.MAX_BYTES) {
            fail(AppError.InvalidDraft(listOf(DraftField.IMAGE_URL)))
        }
        val uid = auth.session.value?.userId ?: fail(AppError.SessionRequired)
        val token = auth.accessToken() ?: fail(AppError.SessionRequired)
        // Перший сегмент шляху — власник: його читає політика Storage.
        return storage.upload("$uid/$eventId/${Uuid.random()}.$extension", bytes, contentType, token)
    }

    override suspend fun deleteImage(url: String) {
        storage.delete(url, auth.accessToken() ?: fail(AppError.SessionRequired))
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
        // Лише коли є: сервер без міграції чату не знає цього параметра, а відсутній означає «без чату».
        ContactRules.normalize(d.contactUrl)?.let { put("p_contact_url", it) }
    }
}
