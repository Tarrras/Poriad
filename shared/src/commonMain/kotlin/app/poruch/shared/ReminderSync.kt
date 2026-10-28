package app.poruch.shared

import app.poruch.domain.DigestRules
import app.poruch.domain.FollowRules
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
                val now = Clock.System.now()
                (ReminderRules.plan(
                    it.library.myEvents,
                    it.library.savedIds,
                    it.session.userId,
                    it.remindersEnabled,
                    now,
                    TimeZone.currentSystemDefault()
                ) + ReminderRules.tickets(it.tickets, it.remindersEnabled, now))
                    .sortedBy { reminder -> reminder.fireAtEpochMillis }.take(ReminderRules.MAX_SCHEDULED)
            }
                .distinctUntilChanged()
                .collect { plan ->
                    PoruchLog.i("reminders") { "${plan.size} scheduled" }
                    scheduler.replace(plan)
                }
        }
        // Дайджест — з видачі головної: вся область без фільтрів мапи. Індекс міняється рідко, а
        // стан — на кожен кадр, тож рахуємо лише на новий список, смак чи підписки, а не на кожну емісію. Новий індекс
        // приходить з кожним відкриттям (`refreshIfStale`), тож драбина на 4 тижні щоразу стартує заново.
        scope.launch {
            state.distinctUntilChanged { a, b ->
                a.home.index === b.home.index && a.digestEnabled == b.digestEnabled && a.taste === b.taste &&
                    a.library.followEvents === b.library.followEvents
            }
                .map {
                    // За ким стежу, по подіях: «Від Атласу» в дайджесті (docs/return-hooks.md).
                    val followed = it.library.followEvents.mapNotNull { event ->
                        FollowRules.via(event, it.library.follows)?.let { follow -> event.id to follow.name }
                    }.toMap()
                    DigestRules.plan(
                        it.home.index,
                        if (it.city.custom) null else it.city.name,
                        it.digestEnabled,
                        Clock.System.now(),
                        TimeZone.currentSystemDefault(),
                        it.taste,
                        followed
                    )
                }
                .distinctUntilChanged()
                .collect { digests ->
                    PoruchLog.i("digest") { digests.joinToString { "week ${it.week}: ${it.count} events, fires ${it.fireAtEpochMillis}" }.ifEmpty { "none" } }
                    scheduler.replaceDigests(digests)
                }
        }
    }
}
