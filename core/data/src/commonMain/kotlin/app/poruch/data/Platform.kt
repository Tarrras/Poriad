package app.poruch.data
import app.cash.sqldelight.db.SqlDriver
import io.ktor.client.HttpClient
expect fun platformHttpClient(): HttpClient
expect fun platformDatabaseDriver(): SqlDriver
