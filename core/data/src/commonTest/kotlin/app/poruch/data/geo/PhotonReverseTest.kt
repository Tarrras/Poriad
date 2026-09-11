package app.poruch.data.geo

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

/**
 * Що показати в полі, коли крапку поставили на мапі.
 *
 * Найближче до крапки — не завжди адреса: Photon першим часто віддає парк або урочище. Порядок
 * вибору тут і є відповіддю, тож він і перевіряється.
 */
class PhotonReverseTest {
    private fun repo(body: String) = PhotonGeoSearchRepository(
        HttpClient(MockEngine { respond(body, HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json")) }),
        "https://photon.test.invalid/api/"
    )

    private fun feature(props: String) =
        """{"geometry":{"coordinates":[30.5,50.4]},"properties":{$props}}"""

    private val park = feature(""""name":"Терапевтичний сад","city":"Київ","countrycode":"UA"""")
    private val street = feature(""""street":"Притисько-Микільська вулиця","city":"Київ","countrycode":"UA"""")
    private val house = feature(""""street":"Притисько-Микільська вулиця","housenumber":"5","city":"Київ","countrycode":"UA"""")

    @Test fun houseWinsOverNearerPark() = runTest {
        val place = repo("""{"features":[$park,$street,$house]}""").placeAt(50.4, 30.5)
        assertEquals("Притисько-Микільська вулиця, 5", place?.label)
        assertEquals("Київ", place?.city)
    }

    @Test fun streetWinsWhenNoHouseNumber() = runTest {
        assertEquals("Притисько-Микільська вулиця", repo("""{"features":[$park,$street]}""").placeAt(50.4, 30.5)?.label)
    }

    /** Ані вулиці, ані будинку — краще назва місця, ніж порожнє поле. */
    @Test fun fallsBackToName() = runTest {
        assertEquals("Терапевтичний сад", repo("""{"features":[$park]}""").placeAt(50.4, 30.5)?.label)
    }

    @Test fun nothingFoundIsNull() = runTest {
        assertNull(repo("""{"features":[]}""").placeAt(50.4, 30.5))
    }

    @Test fun russiaIsExcludedHereToo() = runTest {
        val ru = feature(""""street":"Тверская","housenumber":"1","city":"Москва","countrycode":"RU"""")
        assertNull(repo("""{"features":[$ru]}""").placeAt(55.7, 37.6))
    }
}
