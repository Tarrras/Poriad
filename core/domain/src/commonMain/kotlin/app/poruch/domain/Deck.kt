package app.poruch.domain

import kotlin.time.Duration.Companion.days
import kotlin.time.Instant
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.TimeZone
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.minus
import kotlinx.datetime.toLocalDateTime

/**
 * Стос «Ваш тиждень» (docs/return-hooks.md, хвиля 2): після онбордингу «так/ні» по найближчих подіях «Для вас», «так» —
 * закладка. Людина йде з першої сесії з чимось своїм, а застосунок має про що їй нагадати.
 */
object DeckRules {
    const val MAX = 10

    /** Менше — стосу нема: три картки не «тиждень», а випадковість. */
    const val MIN = 4

    private val HORIZON = 7.days

    /** Не більше стількох одного жанру поспіль: десять стендапів підряд — не підбір. */
    const val SAME_IN_ROW = 3

    /**
     * До [MAX] подій з [events] (уже ранжовані за смаком, по одній на серію) на найближчі 7 днів, без скасованих і тих,
     * що вже почались. Коли три поспіль одного жанру — наступна іншого підтягується вперед. Менше [MIN] — порожньо.
     */
    fun pick(events: List<Event>, now: Instant): List<Event> {
        val until = now + HORIZON
        val rest = events.distinctBy { it.id }.filter { event ->
            event.isPublished && !event.isCalledOff && event.isListed(now) && event.startInstant?.let { it in now..until } == true
        }.toMutableList()
        val deck = ArrayList<Event>()
        while (deck.size < MAX && rest.isNotEmpty()) {
            val tail = deck.takeLast(SAME_IN_ROW)
            val streak = tail.size == SAME_IN_ROW && tail.all { it.category == tail.first().category }
            val next = if (streak) rest.firstOrNull { it.category != tail.first().category } ?: break else rest.first()
            deck += next
            rest -= next
        }
        return if (deck.size < MIN) emptyList() else deck
    }

    /** Тиждень, у який стос відкривали: дата його понеділка. Повтор з головної — раз на тиждень. */
    fun week(now: Instant, zone: TimeZone): String {
        val today = now.toLocalDateTime(zone).date
        return today.minus(today.dayOfWeek.isoDayNumber - 1, DateTimeUnit.DAY).toString()
    }
}
