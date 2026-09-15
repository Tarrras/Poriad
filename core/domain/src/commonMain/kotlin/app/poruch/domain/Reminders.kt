package app.poruch.domain

import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant

/**
 * Локальне нагадування про подію: що сказати і коли. Час в epoch-мілісекундах, бо його
 * читають AlarmManager і UNUserNotificationCenter, а не бізнес-логіка.
 */
data class EventReminder(val eventId: String, val title: String, val address: String, val fireAtEpochMillis: Long)

/**
 * Системний планувальник нагадувань. Реалізує платформа; отримує повний список і сама
 * вирішує, що скасувати, а що лишити. Порожній список означає «нічого не нагадувати».
 */
interface ReminderScheduler {
    fun replace(reminders: List<EventReminder>)
}

/** Прапорець «нагадувати» на пристрої. Переживає вихід з акаунта, як і відповіді онбордингу. */
interface ReminderPreferenceStore {
    fun enabled(): Boolean
    fun setEnabled(enabled: Boolean)
}

/** Кому і коли нагадувати. Чисте правило: без часу пристрою, без дозволів, без платформи. */
object ReminderRules {
    /** За скільки до початку нагадуємо. */
    val LEAD = 1.hours

    /** Стеля на кількість запланованих: iOS тримає лише 64 локальних сповіщення на застосунок. */
    const val MAX_SCHEDULED = 60

    /**
     * Нагадування для [events] людини [userId]. Беремо опубліковані події, де вона організатор
     * або схвалений учасник, і лише ті, до яких ще більше за [LEAD]. Гостю нічого не плануємо.
     */
    fun plan(events: List<Event>, userId: String?, enabled: Boolean, now: Instant): List<EventReminder> {
        if (!enabled || userId == null) return emptyList()
        return events.asSequence()
            .filter { it.isPublished && it.concerns(userId) }
            .mapNotNull { event ->
                val start = event.startInstant ?: return@mapNotNull null
                val fireAt = start - LEAD
                if (fireAt <= now) null
                else EventReminder(event.id, event.title, event.address, fireAt.toEpochMilliseconds())
            }
            .sortedBy { it.fireAtEpochMillis }
            .take(MAX_SCHEDULED)
            .toList()
    }

    private fun Event.concerns(userId: String): Boolean {
        val room = gathering ?: return false
        return room.joined || room.organizerId == userId
    }
}
