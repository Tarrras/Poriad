package app.poruch.data.events

import app.poruch.domain.EventParticipation
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive

/**
 * Участь: двері й черга під ними.
 *
 * Жодної перевірки тут немає навмисно — усі вони на сервері, в одній функції `assert_can_join`:
 * вік, блокування, обмеження акаунта, місткість і рід події. Клієнт, який вирішував би це сам,
 * тримався б до першого пропатченого застосунку.
 */
internal class SupabaseEventParticipation(private val rpc: EventRpc) : EventParticipation {
    override suspend fun join(id: String) { rpc.call("join_event", rpc.eventParams(id)) }
    override suspend fun leave(id: String) { rpc.call("leave_event", rpc.eventParams(id)) }

    override suspend fun waitlistIds(): List<String> =
        rpc.call("my_waitlist").jsonArray.map { it.jsonPrimitive.content }

    override suspend fun joinWaitlist(id: String) { rpc.call("join_waitlist", rpc.eventParams(id)) }
    override suspend fun leaveWaitlist(id: String) { rpc.call("leave_waitlist", rpc.eventParams(id)) }
}
