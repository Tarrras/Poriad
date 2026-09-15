package app.poruch.data.geo

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

/** Росії в пошуку немає. Перевіряємо обидва шляхи: міста й адреси. */
class PhotonExclusionTest {
    private fun repo(body: String) = PhotonGeoSearchRepository(
        HttpClient(MockEngine { respond(body, HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json")) }),
        "https://photon.test.invalid/api/"
    )

    private fun feature(name: String, country: String, code: String) = """
        {"geometry":{"coordinates":[30.5,50.4]},
         "properties":{"type":"city","name":"$name","street":"$name","housenumber":"1","city":"$name","country":"$country","countrycode":"$code"}}
    """.trimIndent()

    /** На «Lviv» Photon віддає ще вокзал, область, університет і аеропорт: лишаємо місто. */
    @Test fun citySearchKeepsOnlySettlements() = runTest {
        val body = """{"features":[
         {"geometry":{"coordinates":[24.03,49.84]},"properties":{"type":"city","name":"Львів","countrycode":"UA"}},
         {"geometry":{"coordinates":[24.03,49.84]},"properties":{"type":"district","name":"Львівський район","countrycode":"UA"}},
         {"geometry":{"coordinates":[24.03,49.84]},"properties":{"type":"state","name":"Львівська область","countrycode":"UA"}},
         {"geometry":{"coordinates":[23.95,49.81]},"properties":{"type":"house","name":"Міжнародний аеропорт «Львів»","countrycode":"UA"}}]}"""
        val found = repo(body).search("Львів")
        assertEquals(listOf("Львів"), found.map { it.name })
    }

    @Test fun citySearchDropsRussia() = runTest {
        val found = repo("""{"features":[${feature("Київ", "Україна", "UA")},${feature("Москва", "Росія", "RU")}]}""").search("мос")
        assertEquals(listOf("Київ"), found.map { it.name })
    }

    @Test fun addressSearchDropsRussia() = runTest {
        val found = repo("""{"features":[${feature("Фроловка", "Росія", "ru")},${feature("Фролівська", "Україна", "UA")}]}""")
            .places("фрол", 50.45, 30.52)
        assertEquals(listOf("Фролівська, 1"), found.map { it.label })
    }

    /** Без `countrycode` місце не ховаємо. */
    @Test fun placeWithoutCountryCodeSurvives() = runTest {
        val body = """{"features":[{"geometry":{"coordinates":[30.5,50.4]},"properties":{"name":"Безіменна","street":"Безіменна","housenumber":"2"}}]}"""
        assertEquals(listOf("Безіменна, 2"), repo(body).places("без", 50.45, 30.52).map { it.label })
    }
}
