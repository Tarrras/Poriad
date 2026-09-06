package app.poruch.events

import app.poruch.domain.*
import kotlin.time.Clock

/**
 * The rules an event mutation must satisfy before it reaches the network. The server enforces the
 * same ones; checking here means a bad draft costs no round trip and the offending fields come
 * back named, so the editor can point at them.
 */
class EventActions(private val repository: EventRepository, private val auth: AuthRepository) {
    private fun requireUser() { if (auth.session.value == null) fail(AppError.SessionRequired) }
    suspend fun create(id: String, draft: EventDraft): String { requireUser(); validate(draft); return repository.create(id, draft) }
    suspend fun update(id: String, draft: EventDraft): String { requireUser(); validate(draft); return repository.update(id, draft) }
    suspend fun join(id: String) { requireUser(); repository.join(id) }
    suspend fun leave(id: String) { requireUser(); repository.leave(id) }
    suspend fun cancel(id: String) { requireUser(); repository.cancel(id) }

    private fun validate(draft: EventDraft) {
        val invalid = draft.validate(Clock.System.now().toString())
        if (invalid.isNotEmpty()) fail(AppError.InvalidDraft(invalid))
    }
}
