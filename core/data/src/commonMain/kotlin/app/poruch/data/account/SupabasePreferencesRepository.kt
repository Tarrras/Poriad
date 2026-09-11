package app.poruch.data.account
import app.poruch.data.api.ApiClient
import app.poruch.domain.*
import io.ktor.http.HttpMethod
import kotlinx.serialization.json.*
class SupabasePreferencesRepository(private val api: ApiClient, private val auth: AuthRepository): PreferencesRepository {
    private fun uid()=auth.session.value?.userId ?: fail(AppError.SessionRequired)
    override suspend fun interests():List<String> {
        val response=api.request("/rest/v1/user_preferences",token=auth.accessToken(),query=mapOf("user_id" to "eq.${uid()}","select" to "categories"))
        return response.jsonArray.firstOrNull()?.jsonObject?.get("categories")?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList()
    }
    override suspend fun setInterests(categories:List<String>) {
        api.request("/rest/v1/user_preferences",HttpMethod.Patch,buildJsonObject { put("categories",JsonArray(categories.map(::JsonPrimitive))) },auth.accessToken(),mapOf("user_id" to "eq.${uid()}"))
    }
}
