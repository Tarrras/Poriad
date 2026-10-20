package app.poruch.data.events

import app.poruch.domain.AppFailure
import app.poruch.domain.PushPlatform
import app.poruch.domain.PushTokens
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/** Токени через RPC. Сервер без міграції пушів — тиша: застосунок і так працює на локальних сповіщеннях. */
internal class SupabasePushTokens(private val rpc: EventRpc) : PushTokens {
    override suspend fun register(token: String, platform: PushPlatform) = quiet {
        rpc.call("register_push_token", buildJsonObject { put("p_token", token); put("p_platform", platform.key) })
    }

    override suspend fun unregister(token: String, accessToken: String?) = quiet {
        rpc.call("unregister_push_token", buildJsonObject { put("p_token", token) }, accessToken)
    }

    override suspend fun touchDevice(token: String, platform: PushPlatform, city: String?, interests: List<String>) = quiet {
        rpc.call("touch_device", buildJsonObject {
            put("p_token", token); put("p_platform", platform.key); put("p_city", city)
            putJsonArray("p_interests") { interests.forEach { add(it) } }
        })
    }

    override suspend fun forgetDevice(token: String) = quiet {
        rpc.call("forget_device", buildJsonObject { put("p_token", token) })
    }

    private suspend inline fun quiet(block: () -> Unit) {
        try { block() } catch (e: CancellationException) { throw e } catch (e: AppFailure) { if (!e.isMissingFunction()) throw e }
    }
}
