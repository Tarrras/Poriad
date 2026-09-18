package app.poruch.shared

import app.poruch.domain.PoruchLog
import app.poruch.domain.ReminderRules
import app.poruch.domain.ReminderScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlin.time.Clock

/**
 * Тримає системні нагадування рівними стану: кожна емісія перераховує план за [ReminderRules],
 * а планувальник чує лише зміни. Так вихід з акаунта, вимкнений перемикач чи скасована подія
 * знімають нагадування без окремого коду на платформах.
 */
internal class ReminderSync(
    private val state: StateFlow<AppState>,
    private val scheduler: ReminderScheduler,
    private val scope: CoroutineScope
) {
    fun start() {
        scope.launch {
            state.map {
                ReminderRules.plan(
                    it.myEvents,
                    it.userId,
                    it.remindersEnabled,
                    Clock.System.now()
                )
            }
                .distinctUntilChanged()
                .collect { plan ->
                    PoruchLog.i("reminders") { "${plan.size} scheduled" }
                    scheduler.replace(plan)
                }
        }
    }
}
