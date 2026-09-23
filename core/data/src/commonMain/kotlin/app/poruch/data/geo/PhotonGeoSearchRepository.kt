package app.poruch.data.geo

import app.poruch.data.api.string

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*
import kotlin.time.TimeSource

/**
 * Геокодер Photon. Адреса й User-Agent — з конфігу збірки (`AppConfig`): поки власного сервера
 * нема, це публічний komoot, і UA з контактом — умова його чесного використання.
 */
class PhotonGeoSearchRepository(
    private val client: HttpClient,
    private val endpoint: String,
    private val userAgent: String = "Poriad"
) : GeoSearchRepository, AddressSearch {
    override suspend fun search(query: String): List<CityResult> {
        if (query.trim().length < 2) return emptyList()
        // У лог іде лише довжина запиту, не сам текст.
        val started = TimeSource.Monotonic.markNow()
        try {
            val response = client.get(endpoint) {
                parameter("q", query.trim()); parameter(
                "limit",
                CITY_LIMIT * OVERFETCH
            ); header("User-Agent", userAgent)
            }
            if (response.status.value !in 200..299) fail(AppError.ServiceUnavailable)
            return Json.parseToJsonElement(response.bodyAsText()).jsonObject["features"]!!.jsonArray.mapNotNull { element ->
                val obj = element.jsonObject
                val props = obj["properties"]!!.jsonObject
                if (props.isExcluded()) return@mapNotNull null
                if (!props.isSettlement()) return@mapNotNull null
                val coords = obj["geometry"]!!.jsonObject["coordinates"]!!.jsonArray
                // Лише назва, без країни: поле йде в заголовки виду «Плани у місті Львів».
                val name = props.string("name")
                if (name.isBlank()) null else CityResult(
                    name,
                    coords[1].jsonPrimitive.double,
                    coords[0].jsonPrimitive.double
                )
            }.distinctBy { it.name }.take(CITY_LIMIT).also {
                PoruchLog.d("geo") { "geocode ${query.trim().length} chars → ${it.size} places in ${started.elapsedNow().inWholeMilliseconds}ms" }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PoruchLog.e(
                "geo",
                e
            ) { "geocode failed after ${started.elapsedNow().inWholeMilliseconds}ms" }
            fail(AppError.Network)
        }
    }

    /**
     * Пошук адреси з пріоритетом біля міста події. Порожній список — не помилка, і мережеві
     * збої теж тихі: крапку завжди можна поставити на мапі рукою.
     */
    override suspend fun places(
        query: String,
        latitude: Double,
        longitude: Double
    ): List<PlaceResult> {
        val text = query.trim()
        if (text.length < MIN_QUERY) return emptyList()
        val started = TimeSource.Monotonic.markNow()
        return try {
            val response = client.get(endpoint) {
                parameter("q", text)
                parameter("limit", LIMIT * OVERFETCH)
                // Пріоритет, а не фільтр: однакова вулиця є в десятку міст.
                parameter("lat", latitude); parameter("lon", longitude)
                header("User-Agent", userAgent)
            }
            if (response.status.value !in 200..299) return emptyList()
            Json.parseToJsonElement(response.bodyAsText()).jsonObject["features"]?.jsonArray
                ?.mapNotNull { it.jsonObject.toPlace() }
                ?.distinctBy { it.label + it.detail }
                ?.take(LIMIT)
                .orEmpty()
                .also {
                    PoruchLog.d("geo") { "address ${text.length} chars → ${it.size} places in ${started.elapsedNow().inWholeMilliseconds}ms" }
                }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PoruchLog.d("geo") { "address lookup failed after ${started.elapsedNow().inWholeMilliseconds}ms" }
            emptyList()
        }
    }

    /**
     * Адреса в точці. Просимо кілька відповідей, бо найближчим часто є парк: шукаємо спершу
     * будинок, потім вулицю, потім будь-яку назву.
     */
    override suspend fun placeAt(latitude: Double, longitude: Double): PlaceResult? {
        val started = TimeSource.Monotonic.markNow()
        return try {
            val response = client.get(reverseEndpoint) {
                parameter("lat", latitude); parameter("lon", longitude)
                parameter("limit", REVERSE_LIMIT)
                header("User-Agent", userAgent)
            }
            if (response.status.value !in 200..299) return null
            val features =
                Json.parseToJsonElement(response.bodyAsText()).jsonObject["features"]?.jsonArray
                    ?.map { it.jsonObject }
                    ?.filterNot { it["properties"]?.jsonObject?.isExcluded() == true }
                    .orEmpty()
            val house = features.firstOrNull {
                it.props("housenumber").isNotBlank() && it.props("street").isNotBlank()
            }
            val street = features.firstOrNull { it.props("street").isNotBlank() }
            (house ?: street ?: features.firstOrNull())?.toPlace().also {
                PoruchLog.d("geo") { "reverse → ${if (it == null) "nothing" else "address"} in ${started.elapsedNow().inWholeMilliseconds}ms" }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PoruchLog.d("geo") { "reverse failed after ${started.elapsedNow().inWholeMilliseconds}ms" }
            null
        }
    }

    private fun JsonObject.props(key: String) =
        this["properties"]?.jsonObject?.string(key).orEmpty()

    private fun JsonObject.toPlace(): PlaceResult? {
        val props = this["properties"]?.jsonObject ?: return null
        if (props.isExcluded()) return null
        val coords = this["geometry"]?.jsonObject?.get("coordinates")?.jsonArray ?: return null
        val street = props.string("street")
        val house = props.string("housenumber")
        // Вулиця з будинком, інакше власна назва: заклад теж адреса.
        val label = when {
            street.isNotBlank() && house.isNotBlank() -> "$street, $house"
            street.isNotBlank() -> street
            else -> props.string("name")
        }
        if (label.isBlank()) return null
        val city = props.string("city")
        val detail = listOf(props.string("district"), city, props.string("country"))
            .filter { it.isNotBlank() }
            .distinct()
            .joinToString(", ")
        return PlaceResult(
            label,
            detail,
            city,
            coords[1].jsonPrimitive.double,
            coords[0].jsonPrimitive.double
        )
    }

    /** Виключені країни — рішення продукту. Порівнюємо за кодом: назва залежить від мови запиту. */
    private fun JsonObject.isExcluded() = string("countrycode").uppercase() in EXCLUDED_COUNTRIES

    /** Лише населений пункт: на «Lviv» Photon віддає ще вокзал, область, університет і аеропорт. */
    private fun JsonObject.isSettlement() = string("type") in SETTLEMENT_TYPES

    /** `/reverse` виводимо з `/api`, щоб у налаштуваннях була одна адреса. */
    private val reverseEndpoint =
        endpoint.trimEnd('/').removeSuffix("/api") + "/reverse"

    private companion object {
        val EXCLUDED_COUNTRIES = setOf("RU")

        /** Значення `type` у Photon для населених пунктів. */
        val SETTLEMENT_TYPES = setOf("city", "town", "village")

        /** Скільки відповідей переглядаємо, шукаючи будинок. */
        const val REVERSE_LIMIT = 5

        /** Просимо із запасом: Photon рахує `limit` до нашого фільтра, і відкинуті рядки з'їдали б місця. */
        const val OVERFETCH = 2

        /** Коротший запит нічого не звужує, а мережі коштує. */
        const val MIN_QUERY = 3

        /** Скільки підказок показуємо. */
        const val LIMIT = 6

        /** Скільки міст показуємо. */
        const val CITY_LIMIT = 8
    }
}
