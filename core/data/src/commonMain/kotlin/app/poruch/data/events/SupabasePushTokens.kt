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
    /**
     * З позначками того, що цей застосунок уміє: `companion_decision` — питання про час збору (R7а), тож сервер питає
     * організатора, а не зсуває збір одразу; `companion` — пуш «Хтось шукає компанію на вашу збережену подію»
     * (docs/companions.md), якого Android 1.3.1 не показав би; `company` — пуші «Хочу піти з компанією» (1.4,
     * docs/return-hooks.md). Сервер без R7а третього параметра не знає — тоді
     * реєструємо без нього.
     */
    override suspend fun register(token: String, platform: PushPlatform) = quiet {
        try {
            rpc.call("register_push_token", buildJsonObject {
                put("p_token", token); put("p_platform", platform.key)
                putJsonArray("p_features") { add(COMPANION_DECISION); add(COMPANION); add(COMPANY) }
            })
        } catch (e: AppFailure) {
            if (!e.isMissingFunction()) throw e
            rpc.call("register_push_token", buildJsonObject { put("p_token", token); put("p_platform", platform.key) })
        }
    }

    override suspend fun unregister(token: String, accessToken: String?) = quiet {
        rpc.call("unregister_push_token", buildJsonObject { put("p_token", token) }, accessToken)
    }

    override suspend fun release(token: String, userId: String) = quiet {
        rpc.anonymous("release_push_token", buildJsonObject { put("p_token", token); put("p_user_id", userId) })
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

    override suspend fun setRadar(token: String, platform: PushPlatform, city: String?, artists: List<String>) = quiet {
        rpc.call("set_radar", buildJsonObject {
            put("p_token", token); put("p_platform", platform.key); put("p_city", city)
            putJsonArray("p_artists") { artists.forEach { add(it) } }
        })
    }

    override suspend fun forgetRadar(token: String) = quiet {
        rpc.call("forget_radar", buildJsonObject { put("p_token", token) })
    }

    private companion object {
        const val COMPANION_DECISION = "companion_decision"
        const val COMPANION = "companion"
        const val COMPANY = "company"
    }

    private suspend inline fun quiet(block: () -> Unit) {
        try { block() } catch (e: CancellationException) { throw e } catch (e: AppFailure) { if (!e.isMissingFunction()) throw e }
    }
}
