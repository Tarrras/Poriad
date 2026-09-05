package app.poruch.data
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import app.cash.sqldelight.db.SqlDriver
import app.poruch.data.cache.PoruchDatabase
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
actual fun platformHttpClient() = HttpClient(CIO)
actual fun platformDatabaseDriver(): SqlDriver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also { PoruchDatabase.Schema.create(it) }
