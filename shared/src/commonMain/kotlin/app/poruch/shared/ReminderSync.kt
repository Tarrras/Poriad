package app.poruch.shared

import app.poruch.domain.DigestRules
import app.poruch.domain.PoruchLog
import app.poruch.domain.ReminderRules
import app.poruch.domain.ReminderScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.datetime.TimeZone
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
                    it.library.myEvents,
                    it.session.userId,
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
        // Дайджест — з видачі головної: вся область без фільтрів мапи. Індекс міняється рідко, а
        // стан — на кожен кадр, тож рахуємо лише на новий список, а не на кожну емісію.
        scope.launch {
            state.distinctUntilChanged { a, b -> a.home.index === b.home.index && a.digestEnabled == b.digestEnabled }
                .map {
                    DigestRules.plan(
                        it.home.index,
                        if (it.city.custom) null else it.city.name,
                        it.digestEnabled,
                        Clock.System.now(),
                        TimeZone.currentSystemDefault()
                    )
                }
                .distinctUntilChanged()
                .collect { digest ->
                    PoruchLog.i("digest") { digest?.let { "${it.count} events, fires ${it.fireAtEpochMillis}" } ?: "none" }
                    scheduler.replaceDigest(digest)
                }
        }
    }
}
