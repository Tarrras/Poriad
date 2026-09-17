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
    /** Для рушіїв, що пишуть стан напряму: [DiscoveryEngine], [UserLibrary], [ChatEngine]. */
    val flow = MutableStateFlow(initial)
    val state: StateFlow<AppState> = flow.asStateFlow()
    val value: AppState get() = flow.value
    private var mutationJob: Job? = null

    inline fun update(change: (AppState) -> AppState) = flow.update(change)

    /** Одна зміна за раз: другий тап під час першої — це подвійний тап, а не другий намір. */
    fun mutate(block: suspend () -> Unit) {
        if (mutationJob?.isActive == true) { PoruchLog.w("action") { "ignored: a mutation is already running" }; return }
        mutationJob = scope.launch {
            update { it.copy(mutating = true, notice = null) }
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("action") { "failed: $error" }
                failed(error)
            } finally {
                update { it.copy(mutating = false) }
            }
        }
    }

    fun tell(message: AppMessage) = update { it.copy(notice = AppNotice.Told(message)) }
    fun failed(error: AppError) = update { it.copy(notice = AppNotice.Failed(error)) }
}
