package app.poruch.data.geo

import app.poruch.data.api.string

import app.poruch.domain.*
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*
import kotlin.time.TimeSource

/** Public Photon endpoint is for development; inject a contracted endpoint for production. */
class PhotonGeoSearchRepository(
    private val client: HttpClient,
    private val endpoint: String = "https://photon.komoot.io/api/"
) : GeoSearchRepository, AddressSearch {
    override suspend fun search(query: String): List<CityResult> {
        if (query.trim().length < 2) return emptyList()
        // The query itself is a place someone is looking for; only its length is traced.
        val started = TimeSource.Monotonic.markNow()
        try {
            val response = client.get(endpoint) { parameter("q",query.trim()); parameter("limit",CITY_LIMIT * OVERFETCH); header("User-Agent","Poruch-development/1.0") }
            if (response.status.value !in 200..299) fail(AppError.ServiceUnavailable)
            return Json.parseToJsonElement(response.bodyAsText()).jsonObject["features"]!!.jsonArray.mapNotNull { element ->
                val obj = element.jsonObject
                val props = obj["properties"]!!.jsonObject
                if (props.isExcluded()) return@mapNotNull null
                if (!props.isSettlement()) return@mapNotNull null
                val coords = obj["geometry"]!!.jsonObject["coordinates"]!!.jsonArray
                // Саме назва, без країни. Це поле йде в стан і звідти — у заголовки: «Плани на
                // найближчі дні у місті Львів, Україна» читалось як помилка, бо нею й було.
                val name = props.string("name")
                if (name.isBlank()) null else CityResult(name,coords[1].jsonPrimitive.double,coords[0].jsonPrimitive.double)
            }.distinctBy { it.name }.take(CITY_LIMIT).also {
                PoruchLog.d("geo") { "geocode ${query.trim().length} chars → ${it.size} places in ${started.elapsedNow().inWholeMilliseconds}ms" }
            }
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            PoruchLog.e("geo", e) { "geocode failed after ${started.elapsedNow().inWholeMilliseconds}ms" }
            fail(AppError.Network)
        }
    }

    /**
     * Той самий Photon, але інший запит: зі зсувом до міста події та з підписом, у якому видно
     * вулицю з будинком.
     *
     * Порожній список — не помилка: адресу могли ще не дописати, і мовчазна відсутність підказок
     * тут краща за повідомлення про збій. Тому мережеві невдачі теж тихі — крапку завжди можна
     * поставити на мапі рукою.
     */
    override suspend fun places(query: String, latitude: Double, longitude: Double): List<PlaceResult> {
        val text = query.trim()
        if (text.length < MIN_QUERY) return emptyList()
        val started = TimeSource.Monotonic.markNow()
        return try {
            val response = client.get(endpoint) {
                parameter("q", text)
                parameter("limit", LIMIT * OVERFETCH)
                // Зсув, а не фільтр: та сама вулиця є в десятку міст, і першою має бути найближча.
                parameter("lat", latitude); parameter("lon", longitude)
                header("User-Agent", "Poruch-development/1.0")
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
     * Адреса в точці.
     *
     * Просимо кілька відповідей, а не одну: найближчою до крапки часто виявляється парк або
     * урочище, а в полі має стояти адреса — з номером будинку, якщо він є. Тому серед відповідей
     * шукаємо спершу будинок, потім вулицю, і лише тоді беремо будь-яку назву.
     */
    override suspend fun placeAt(latitude: Double, longitude: Double): PlaceResult? {
        val started = TimeSource.Monotonic.markNow()
        return try {
            val response = client.get(reverseEndpoint) {
                parameter("lat", latitude); parameter("lon", longitude)
                parameter("limit", REVERSE_LIMIT)
                header("User-Agent", "Poruch-development/1.0")
            }
            if (response.status.value !in 200..299) return null
            val features = Json.parseToJsonElement(response.bodyAsText()).jsonObject["features"]?.jsonArray
                ?.map { it.jsonObject }
                ?.filterNot { it["properties"]?.jsonObject?.isExcluded() == true }
                .orEmpty()
            val house = features.firstOrNull { it.props("housenumber").isNotBlank() && it.props("street").isNotBlank() }
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

    private fun JsonObject.props(key: String) = this["properties"]?.jsonObject?.string(key).orEmpty()

    private fun JsonObject.toPlace(): PlaceResult? {
        val props = this["properties"]?.jsonObject ?: return null
        if (props.isExcluded()) return null
        val coords = this["geometry"]?.jsonObject?.get("coordinates")?.jsonArray ?: return null
        val street = props.string("street")
        val house = props.string("housenumber")
        // Вулиця з будинком, якщо вони є; інакше власна назва — заклад теж адреса.
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
        return PlaceResult(label, detail, city, coords[1].jsonPrimitive.double, coords[0].jsonPrimitive.double)
    }

    /**
     * Країни, яких у пошуку немає.
     *
     * Це рішення продукту, а не технічне обмеження: Photon віддає росію так само, як усе інше, і
     * саме тому її треба прибирати свідомо. Фільтр стоїть тут, а не в кожному екрані, бо пошуків
     * два — міст і адрес, — а правило одне.
     *
     * Порівнюємо за кодом країни, а не за назвою: назва приходить мовою запиту й залежить від
     * `lang`, код — ні.
     */
    private fun JsonObject.isExcluded() = string("countrycode").uppercase() in EXCLUDED_COUNTRIES

    /**
     * Лише населений пункт. Photon на «Lviv» віддає вісім відповідей, з яких місто одне: далі йдуть
     * вокзал, область, район, університет і аеропорт. Поїхати за будь-якою з них означає опинитись
     * там, де подій немає, — і виглядає це так, ніби їх немає взагалі.
     */
    private fun JsonObject.isSettlement() = string("type") in SETTLEMENT_TYPES

    /**
     * Прямий і зворотний пошук у Photon — різні шляхи одного сервера: `/api` і `/reverse`.
     * Виводимо другий із першого, щоб у налаштуваннях лишалась одна адреса.
     */
    private val reverseEndpoint =
        endpoint.trimEnd('/').removeSuffix("/api") + "/reverse"

    private companion object {
        val EXCLUDED_COUNTRIES = setOf("RU")

        /** Як Photon називає населені пункти в полі `type`. */
        val SETTLEMENT_TYPES = setOf("city", "town", "village")

        /** Скільки відповідей переглядаємо, шукаючи серед них будинок. */
        const val REVERSE_LIMIT = 5

        /**
         * Наскільки більше просимо в Photon, ніж покажемо.
         *
         * Photon рахує свій `limit` до нашого фільтра, тож без запасу відкинуті рядки просто
         * з'їдали б місця у видачі: на «Frolivska» дві з шести відповідей — росія, і людина
         * бачила б менше підказок саме там, де їх і так небагато.
         */
        const val OVERFETCH = 2

        /** Коротше за це запит нічого не звужує, а запит уже коштує мережі. */
        const val MIN_QUERY = 3
        /** Скільки підказок читається одним поглядом. */
        const val LIMIT = 6
        /** Стільки міст уміщалось у списку й до фільтра. */
        const val CITY_LIMIT = 8
    }
}
