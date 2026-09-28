package app.poruch.data.events

import app.poruch.domain.Event
import app.poruch.domain.Follow
import app.poruch.domain.FollowKind
import app.poruch.domain.Follows
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.put

/** Підписки через RPC `follow` / `unfollow` / `my_follows` / `follow_events`. Усе лише з акаунтом. */
internal class SupabaseFollows(private val rpc: EventRpc) : Follows {
    override suspend fun mine(): List<Follow> =
        rpc.json.decodeFromJsonElement<List<FollowDto>>(rpc.read("my_follows")).mapNotNull { it.domain() }

    override suspend fun follow(kind: FollowKind, targetId: String) {
        rpc.call("follow", buildJsonObject { put("p_kind", kind.key); put("p_target", targetId) })
    }

    override suspend fun unfollow(kind: FollowKind, targetId: String) {
        rpc.call("unfollow", buildJsonObject { put("p_kind", kind.key); put("p_target", targetId) })
    }

    override suspend fun upcoming(): List<Event> = rpc.events("follow_events", buildJsonObject { put("p_limit", UPCOMING_LIMIT) })

    private companion object {
        /** Скільки карток підписок несе головна: секція — добірка, а не каталог. */
        const val UPCOMING_LIMIT = 20
    }
}
