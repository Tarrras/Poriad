package app.poruch.data.events

import app.poruch.domain.EventParticipation
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive

/** Участь і черга. Перевірок тут нема навмисно: усі на сервері в `assert_can_join`. */
internal class SupabaseEventParticipation(private val rpc: EventRpc) : EventParticipation {
    override suspend fun join(id: String) { rpc.call("join_event", rpc.eventParams(id)) }
    override suspend fun leave(id: String) { rpc.call("leave_event", rpc.eventParams(id)) }

    override suspend fun waitlistIds(): List<String> =
        rpc.read("my_waitlist").jsonArray.map { it.jsonPrimitive.content }

    override suspend fun joinWaitlist(id: String) { rpc.call("join_waitlist", rpc.eventParams(id)) }
    override suspend fun leaveWaitlist(id: String) { rpc.call("leave_waitlist", rpc.eventParams(id)) }
}
