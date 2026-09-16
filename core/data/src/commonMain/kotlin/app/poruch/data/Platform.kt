package app.poruch.data
import app.cash.sqldelight.db.SqlDriver
import io.ktor.client.HttpClient
expect fun platformHttpClient(): HttpClient
expect fun platformDatabaseDriver(): SqlDriver
/** Випадкові байти криптографічної якості для PKCE. */
internal expect fun secureRandomBytes(count: Int): ByteArray
