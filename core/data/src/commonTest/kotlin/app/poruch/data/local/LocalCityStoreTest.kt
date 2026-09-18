package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.data.platformDatabaseDriver
import app.poruch.domain.CityResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class LocalCityStoreTest {
    private val database = PoruchDatabase(platformDatabaseDriver())

    @Test
    fun remembersTheLastCity() {
        val store = LocalCityStore(database)
        assertNull(store.read())
        store.write(CityResult("Київ", 50.4501, 30.5234))
        store.write(CityResult("Одеса", 46.4825, 30.7233))
        assertEquals(CityResult("Одеса", 46.4825, 30.7233), LocalCityStore(database).read())
    }

    @Test
    fun damagedRecordMeansNoCity() {
        database.cacheQueries.writeDevice("device:city", """{"name":"Одеса","latitude":146.0,"longitude":30.7}""")
        assertNull(LocalCityStore(database).read())
        database.cacheQueries.writeDevice("device:city", "not json")
        assertNull(LocalCityStore(database).read())
    }
}
