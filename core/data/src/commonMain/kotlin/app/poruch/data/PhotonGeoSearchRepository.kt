package app.poruch.data

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*
import kotlin.time.TimeSource

/** Public Photon endpoint is for development; inject a contracted endpoint for production. */
class PhotonGeoSearchRepository(private val client: HttpClient, private val endpoint: String = "https://photon.komoot.io/api/"): GeoSearchRepository {
    override suspend fun search(query: String): List<CityResult> {
        if (query.trim().length < 2) return emptyList()
        // The query itself is a place someone is looking for; only its length is traced.
        val started = TimeSource.Monotonic.markNow()
        try {
            val response = client.get(endpoint) { parameter("q",query.trim()); parameter("limit",8); header("User-Agent","Poruch-development/1.0") }
            if (response.status.value !in 200..299) fail(AppError.ServiceUnavailable)
            return Json.parseToJsonElement(response.bodyAsText()).jsonObject["features"]!!.jsonArray.mapNotNull { element ->
                val obj = element.jsonObject
                val props = obj["properties"]!!.jsonObject
                val coords = obj["geometry"]!!.jsonObject["coordinates"]!!.jsonArray
                val name = listOf(props.string("name"), props.string("country")).filter { it.isNotBlank() }.joinToString(", ")
                if (name.isBlank()) null else CityResult(name,coords[1].jsonPrimitive.double,coords[0].jsonPrimitive.double)
            }.distinctBy { it.name }.also {
                PoruchLog.d("geo") { "geocode ${query.trim().length} chars → ${it.size} places in ${started.elapsedNow().inWholeMilliseconds}ms" }
            }
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            PoruchLog.e("geo", e) { "geocode failed after ${started.elapsedNow().inWholeMilliseconds}ms" }
            fail(AppError.Network)
        }
    }
}
