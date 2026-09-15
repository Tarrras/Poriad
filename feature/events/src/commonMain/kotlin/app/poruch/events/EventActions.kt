package app.poruch.events

import app.poruch.domain.*
import kotlin.time.Clock

/** Перевірка чернетки до мережі: сервер перевіряє те саме, але тут редактор отримує назви полів. */
class EventActions(
    private val authoring: EventAuthoring,
    private val participation: EventParticipation,
    private val auth: AuthRepository
) {
    private fun requireUser() { if (auth.session.value == null) fail(AppError.SessionRequired) }
    suspend fun create(id: String, draft: EventDraft): String { requireUser(); validate(draft); return authoring.create(id, draft) }
    suspend fun update(id: String, draft: EventDraft): String { requireUser(); validate(draft); return authoring.update(id, draft) }
    suspend fun join(id: String) { requireUser(); participation.join(id) }
    suspend fun leave(id: String) { requireUser(); participation.leave(id) }
    suspend fun cancel(id: String) { requireUser(); authoring.cancel(id) }

    private fun validate(draft: EventDraft) {
        val invalid = draft.validate(Clock.System.now().toString())
        if (invalid.isNotEmpty()) fail(AppError.InvalidDraft(invalid))
    }
}
