package app.poruch.data
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import app.cash.sqldelight.db.SqlDriver
import app.poruch.data.cache.PoruchDatabase
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
actual fun platformHttpClient() = HttpClient(CIO) { install(io.ktor.client.plugins.HttpTimeout) { connectTimeoutMillis = 10_000; requestTimeoutMillis = 30_000; socketTimeoutMillis = 30_000 } }
actual fun platformDatabaseDriver(): SqlDriver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also { PoruchDatabase.Schema.create(it) }

internal actual fun secureRandomBytes(count: Int): ByteArray = ByteArray(count).also { java.security.SecureRandom().nextBytes(it) }
