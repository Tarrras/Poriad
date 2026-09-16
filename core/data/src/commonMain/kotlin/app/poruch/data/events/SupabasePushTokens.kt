package app.poruch.data.events

import app.poruch.domain.AppFailure
import app.poruch.domain.PushTokens
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Токени через RPC. Сервер без міграції пушів — тиша: застосунок і так працює на локальних сповіщеннях. */
internal class SupabasePushTokens(private val rpc: EventRpc) : PushTokens {
    override suspend fun register(token: String, platform: String) = quiet {
        rpc.call("register_push_token", buildJsonObject { put("p_token", token); put("p_platform", platform) })
    }

    override suspend fun unregister(token: String) = quiet {
        rpc.call("unregister_push_token", buildJsonObject { put("p_token", token) })
    }

    private suspend inline fun quiet(block: () -> Unit) {
        try { block() } catch (e: CancellationException) { throw e } catch (e: AppFailure) { if (!e.isMissingFunction()) throw e }
    }
}
