package app.poruch.data.local

import app.poruch.data.cache.PoruchDatabase
import app.poruch.domain.TicketStore
import app.poruch.domain.WalletTicket
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/** Квитки з телефона під `device:`: вихід з акаунта (`clearPrivateDevice`) їх не стирає (docs/ticket-wallet.md). */
class LocalTicketStore(private val database: PoruchDatabase) : TicketStore {
    private val json = Json { ignoreUnknownKeys = true }

    override fun all(): List<WalletTicket> {
        val stored = database.cacheQueries.readDevice(KEY).executeAsOneOrNull() ?: return emptyList()
        return runCatching { json.decodeFromString(ListSerializer(WalletTicket.serializer()), stored) }.getOrDefault(emptyList())
    }

    override fun write(tickets: List<WalletTicket>) {
        database.cacheQueries.writeDevice(KEY, json.encodeToString(ListSerializer(WalletTicket.serializer()), tickets))
    }

    private companion object {
        const val KEY = "device:tickets"
    }
}
