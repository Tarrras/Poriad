package app.poruch.data.geo

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

/** Адреса для крапки на мапі: найближчим часто є парк, тому перевіряється порядок вибору. */
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

    /** Без вулиці й будинку — назва місця, а не порожнє поле. */
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
