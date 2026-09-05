package app.poruch.data
import android.content.Context
import app.cash.sqldelight.driver.android.AndroidSqliteDriver
import app.cash.sqldelight.db.SqlDriver
import app.poruch.data.cache.PoruchDatabase
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
object AndroidStorage { lateinit var context: Context }
actual fun platformHttpClient() = HttpClient(OkHttp)
actual fun platformDatabaseDriver(): SqlDriver = AndroidSqliteDriver(PoruchDatabase.Schema, AndroidStorage.context, "poruch.db")
