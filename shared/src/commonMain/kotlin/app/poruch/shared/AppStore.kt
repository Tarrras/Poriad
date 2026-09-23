package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Стан застосунку і єдиний вхід для його змін. Тримає правило «одна зміна за раз» і переклад
 * збою в [AppNotice], щоб сценарії ([EventUseCases], [SessionUseCases] тощо) писали лише суть.
 */
internal class AppStore(initial: AppState, val scope: CoroutineScope) {
    private val flow = MutableStateFlow(initial)
    val state: StateFlow<AppState> = flow.asStateFlow()
    val value: AppState get() = flow.value
    private var mutationJob: Job? = null

    fun update(change: (AppState) -> AppState) = flow.update(change)

    /**
     * Одна зміна за раз: другий тап під час першої — це подвійний тап, а не другий намір. [queued] —
     * не тап, а подія ззовні (посилання з листа): її не відкидаємо, а виконуємо після поточної.
     */
    fun mutate(queued: Boolean = false, block: suspend () -> Unit) {
        val running = mutationJob?.takeIf { it.isActive }
        if (running != null && !queued) { PoruchLog.w("action") { "ignored: a mutation is already running" }; return }
        mutationJob = scope.launch {
            running?.join()
            update { it.copy(mutating = true, notice = null) }
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("action") { "failed: $error" }
                failed(error, byPerson = true)
            } finally {
                update { it.copy(mutating = false) }
            }
        }
    }

    fun tell(message: AppMessage) = update { it.copy(notice = AppNotice.Told(message)) }
    /** [byPerson] — збій дії людини, а не фонового перечитування: лише такий рахується в аналітиці. */
    fun failed(error: AppError, byPerson: Boolean = false) {
        // Стіна входу: дія, яку гість хотів зробити, але мусив би спершу зареєструватись.
        if (byPerson && error == AppError.SessionRequired) PoruchAnalytics.track("auth_wall")
        update { it.copy(notice = AppNotice.Failed(error)) }
    }
}
