package app.poruch.domain

import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant

/** Тип укриття з `event_safety`. Новий серверний тип читається як звичайне укриття, а не помилка. */
enum class ShelterKind(val key: String) {
    METRO("metro"), UNDERPASS("underpass"), PARKING("parking"), BASEMENT("basement");

    companion object {
        fun fromKey(key: String?) = entries.firstOrNull { it.key == key } ?: BASEMENT
    }
}

/** Укриття поруч із місцем події. [hours] — лише якщо не цілодобово. */
data class Shelter(
    val kind: ShelterKind,
    val address: String,
    val distanceMeters: Int,
    val accessible: Boolean,
    val hours: String?,
    val latitude: Double,
    val longitude: Double
)

/** Комендантська година міста, місцевий час «HH:MM». */
data class Curfew(val starts: String, val ends: String)

/**
 * Безпека відкритої події: до трьох найближчих укриттів у радіусі кілометра й комендантська міста.
 * Порожньо — для цього міста даних нема, а не «укриттів нема»: екран тоді секцію не показує.
 */
data class EventSafety(val shelters: List<Shelter>, val curfew: Curfew?)

/** Кінець події щодо комендантської: [minutesLeft] = 0 — подія закінчується вже під час неї. */
data class CurfewNote(val endsAt: String, val curfew: Curfew, val minutesLeft: Int)

object CurfewRules {
    /** Нагадуємо лише про події, що закінчуються не раніше ніж за 4 год до комендантської: вдень це шум. */
    const val WINDOW_MINUTES = 4 * 60

    /** Прокат і виставки тривають днями: їхній «кінець» — це закриття сезону, а не вечора. */
    private val LONGEST_EVENING = 12.hours

    fun note(event: Event, curfew: Curfew?, now: Instant): CurfewNote? {
        curfew ?: return null
        val start = runCatching { Instant.parse(event.startsAt) }.getOrNull() ?: return null
        val end = runCatching { Instant.parse(event.endsAt) }.getOrNull() ?: return null
        if (end <= now || end - start > LONGEST_EVENING) return null
        val zone = runCatching { TimeZone.of(event.timeZone) }.getOrNull() ?: return null
        val local = end.toLocalDateTime(zone).time
        val endMinute = local.hour * 60 + local.minute
        val from = minuteOf(curfew.starts) ?: return null
        val until = minuteOf(curfew.ends) ?: return null
        val endsAt = "${local.hour.toString().padStart(2, '0')}:${local.minute.toString().padStart(2, '0')}"
        val during = if (from < until) endMinute in from until until else endMinute >= from || endMinute < until
        if (during) return CurfewNote(endsAt, curfew, 0)
        val left = (from - endMinute).mod(MINUTES_IN_DAY)
        return if (left <= WINDOW_MINUTES) CurfewNote(endsAt, curfew, left) else null
    }

    private fun minuteOf(time: String): Int? {
        val (hour, minute) = time.split(":").takeIf { it.size == 2 }?.map { it.toIntOrNull() } ?: return null
        return if (hour != null && minute != null) hour * 60 + minute else null
    }

    private const val MINUTES_IN_DAY = 24 * 60
}
