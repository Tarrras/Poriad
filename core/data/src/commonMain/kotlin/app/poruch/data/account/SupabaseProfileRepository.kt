package app.poruch.data.account

import app.poruch.data.api.ApiClient
import app.poruch.data.api.ImageStorage
import app.poruch.data.api.string
import app.poruch.domain.*
import io.ktor.http.HttpMethod
import kotlinx.serialization.json.*
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** Профіль: картка через `profile_card`, свої поля — PATCH `profiles` (перевіряє тригер), фото — Storage. */
class SupabaseProfileRepository(
    private val api: ApiClient,
    private val auth: AuthRepository,
    private val storage: ImageStorage
) : ProfileRepository {
    private fun uid() = auth.session.value?.userId ?: fail(AppError.SessionRequired)

    override suspend fun profile(userId: String): Profile? {
        val row = api.request(
            "/rest/v1/rpc/profile_card", HttpMethod.Post, buildJsonObject { put("p_user_id", userId) }, auth.accessToken()
        ).jsonArray.firstOrNull()?.jsonObject ?: return null
        return Profile(
            userId = row.string("user_id"),
            name = row.string("display_name"),
            avatarUrl = row.optional("avatar_url"),
            bio = row.optional("bio"),
            memberSince = row.optional("member_since"),
            organized = row["organized"]?.jsonPrimitive?.intOrNull ?: 0,
            attended = row["attended"]?.jsonPrimitive?.intOrNull ?: 0,
            email = row.optional("email")
        )
    }

    override suspend fun update(name: String, bio: String?) {
        if (!AccountRules.isName(name)) fail(AppError.InvalidName)
        patch(buildJsonObject {
            put("display_name", name.trim())
            put("bio", ProfileRules.normalizeBio(bio)?.let(::JsonPrimitive) ?: JsonNull)
        })
    }

    @OptIn(ExperimentalUuidApi::class)
    override suspend fun setAvatar(bytes: ByteArray, contentType: String): String {
        val extension = ImageRules.extensions[contentType] ?: fail(AppError.ImageUploadFailed)
        if (bytes.isEmpty() || bytes.size > ImageRules.MAX_BYTES) fail(AppError.ImageUploadFailed)
        val token = auth.accessToken() ?: fail(AppError.SessionRequired)
        // Тека `avatar` — єдина, яку тригер профілю приймає як фото.
        val url = storage.upload("${uid()}/avatar/${Uuid.random()}.$extension", bytes, contentType, token)
        patch(buildJsonObject { put("avatar_url", url) })
        return url
    }

    override suspend fun removeAvatar() = patch(buildJsonObject { put("avatar_url", JsonNull) })

    override suspend fun deleteImage(url: String) {
        storage.delete(url, auth.accessToken() ?: fail(AppError.SessionRequired))
    }

    private suspend fun patch(fields: JsonObject) {
        api.request("/rest/v1/profiles", HttpMethod.Patch, fields, auth.accessToken(), mapOf("id" to "eq.${uid()}"))
    }

    private fun JsonObject.optional(key: String) = this[key]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
}
