package app.poruch.data
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import app.cash.sqldelight.db.SqlDriver
import app.poruch.data.cache.PoruchDatabase
import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
// Darwin за замовчуванням чекає хвилину: `mutating` тримав би екран стільки ж.
actual fun platformHttpClient() = HttpClient(Darwin) { install(io.ktor.client.plugins.HttpTimeout) { connectTimeoutMillis = 10_000; requestTimeoutMillis = 30_000; socketTimeoutMillis = 30_000 } }
actual fun platformDatabaseDriver(): SqlDriver = NativeSqliteDriver(PoruchDatabase.Schema, "poruch.db")

@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
internal actual fun secureRandomBytes(count: Int): ByteArray {
    val bytes = ByteArray(count)
    bytes.usePinned { pinned ->
        val status = platform.Security.SecRandomCopyBytes(platform.Security.kSecRandomDefault, count.toULong(), pinned.addressOf(0))
        check(status == platform.Security.errSecSuccess) { "SecRandomCopyBytes failed: $status" }
    }
    return bytes
}
