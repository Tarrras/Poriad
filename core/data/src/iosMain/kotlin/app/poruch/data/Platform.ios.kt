package app.poruch.data
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import app.cash.sqldelight.db.SqlDriver
import app.poruch.data.cache.PoruchDatabase
import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
actual fun platformHttpClient() = HttpClient(Darwin)
actual fun platformDatabaseDriver(): SqlDriver = NativeSqliteDriver(PoruchDatabase.Schema, "poruch.db")
