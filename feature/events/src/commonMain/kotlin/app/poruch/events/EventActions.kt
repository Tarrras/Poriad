package app.poruch.events
import app.poruch.domain.*
import kotlin.time.Clock

class EventActions(private val repository: EventRepository, private val auth: AuthRepository) {
    private fun requireUser() { if (auth.session.value == null) throw AppException(Failure.AUTH,"Увійдіть, щоб продовжити") }
    suspend fun create(id: String, draft: EventDraft): String { requireUser(); validate(draft); return repository.create(id,draft) }
    suspend fun update(id: String, draft: EventDraft): String { requireUser(); validate(draft); return repository.update(id,draft) }
    suspend fun join(id: String) { requireUser(); repository.join(id) }
    suspend fun leave(id: String) { requireUser(); repository.leave(id) }
    suspend fun cancel(id: String) { requireUser(); repository.cancel(id) }
    private fun validate(draft: EventDraft) {
        val errors = draft.validate(Clock.System.now().toString())
        if (errors.isNotEmpty()) throw AppException(Failure.VALIDATION, "Перевірте поля: " + errors.joinToString { field ->
            when(field) { "title" -> "назва (3–120 символів)"; "description" -> "опис (10–5000 символів)"; "startsAt" -> "майбутня дата початку"; "endsAt" -> "час закінчення"; "location" -> "точка на мапі"; "capacity" -> "кількість місць (1–10000)"; "timeZone" -> "часовий пояс"; "address" -> "місто та адреса"; else -> field }
        })
    }
}
