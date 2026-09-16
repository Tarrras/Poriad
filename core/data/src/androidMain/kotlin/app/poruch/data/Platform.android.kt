package app.poruch.data
import android.content.Context
import app.cash.sqldelight.driver.android.AndroidSqliteDriver
import app.cash.sqldelight.db.SqlDriver
import app.poruch.data.cache.PoruchDatabase
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
object AndroidStorage { lateinit var context: Context }
actual fun platformHttpClient() = HttpClient(OkHttp) { install(io.ktor.client.plugins.HttpTimeout) { connectTimeoutMillis = 10_000; requestTimeoutMillis = 30_000; socketTimeoutMillis = 30_000 } }
actual fun platformDatabaseDriver(): SqlDriver = AndroidSqliteDriver(PoruchDatabase.Schema, AndroidStorage.context, "poruch.db")

internal actual fun secureRandomBytes(count: Int): ByteArray = ByteArray(count).also { java.security.SecureRandom().nextBytes(it) }
