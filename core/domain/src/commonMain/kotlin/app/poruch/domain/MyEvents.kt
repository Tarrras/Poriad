package app.poruch.domain

import kotlin.time.Instant
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/** Розрізи вкладки «Мої події» (docs/my-events.md). */
enum class MyEventsTab { GOING, ORGANIZING, SAVED }

/**
 * Секція розрізу. [UPCOMING] в «Іду» — «Далі», в «Організовую» — усе попереду: першу подію екран
 * показує панеллю «Найближча», решту — «Далі».
 */
enum class MyEventsGroup { TODAY, UPCOMING, THIS_WEEK, LATER, PAST }

data class MyEventsSection(val group: MyEventsGroup, val events: List<Event>)

/** Уся вкладка одним знімком: секції трьох розрізів і лічильники для підзаголовка й бейджів. */
data class MyEventsBoard(
    val going: List<MyEventsSection> = emptyList(),
    val organizing: List<MyEventsSection> = emptyList(),
    val saved: List<MyEventsSection> = emptyList(),
    /** Попереду в «Іду», з тими, що чекають підтвердження чи в черзі. */
    val goingAhead: Int = 0,
    /** Скільки з [goingAhead] ще чекає відповіді організатора. */
    val awaiting: Int = 0,
    val organizingAhead: Int = 0,
    /** Запити на участь до моїх подій, що ще не почались. */
    val requests: Int = 0,
    val savedAhead: Int = 0,
    val savedThisWeek: Int = 0,
    /** Бейдж чипа «Іду»: події з непрочитаним чатом, і минулі теж. */
    val goingBadge: Int = 0,
    /** Бейдж чипа «Організовую»: непрочитані чати плюс запити на участь. */
    val organizingBadge: Int = 0
) {
    fun sections(tab: MyEventsTab) = when (tab) {
        MyEventsTab.GOING -> going
        MyEventsTab.ORGANIZING -> organizing
        MyEventsTab.SAVED -> saved
    }

    fun isEmpty(tab: MyEventsTab) = sections(tab).isEmpty()
}

object MyEventsRules {
    /** Скільки минулих видно одразу; решта — за «Показати всі». */
    const val PAST_PREVIEW = 3

    /**
     * Розкладає «мої» події з `my_events` по розрізах і секціях. Порядок усередині — як прийшов
     * (за початком), минулі — свіжіші першими. «Сьогодні» і «цього тижня» — за поясом телефона [zone]:
     * це про день людини, а не події.
     */
    fun board(
        events: List<Event>,
        userId: String?,
        savedIds: Collection<String>,
        waitlistedIds: Collection<String>,
        requests: List<JoinRequest>,
        unreadEventIds: Collection<String>,
        now: Instant,
        zone: TimeZone
    ): MyEventsBoard {
        if (userId == null) return MyEventsBoard()
        val saved = savedIds.toSet(); val queued = waitlistedIds.toSet(); val unread = unreadEventIds.toSet()
        val today = now.toLocalDateTime(zone).date
        val weekEnd = today.plus(DatePeriod(days = DayOfWeek.SUNDAY.ordinal - today.dayOfWeek.ordinal))
        fun startDate(event: Event): LocalDate? = event.startInstant?.toLocalDateTime(zone)?.date
        fun past(event: Event) = event.hasEnded(now)

        val mine = events.filter { it.organizerId == userId }
        val going = events.filter { event ->
            val room = event.gathering ?: return@filter false
            room.organizerId != userId && (room.joined || room.awaitingApproval || event.id in queued)
        }

        val goingAhead = going.filterNot(::past)
        val (todays, next) = goingAhead.partition { event ->
            event.isUnderway(now) || startDate(event)?.let { it <= today } == true
        }
        // Минуле — лише де людина справді була: запит і черга після кінця нічого не значать.
        val goingPast = going.filter { past(it) && it.gathering?.joined == true && !it.isCancelled }.asReversed()

        val mineAhead = mine.filterNot(::past)
        val minePast = mine.filter { past(it) && !it.isCancelled }.asReversed()

        val savedAhead = events.filter { it.id in saved && !past(it) }
        val (thisWeek, afterWeek) = savedAhead.partition { event ->
            event.isUnderway(now) || startDate(event)?.let { it <= weekEnd } == true
        }

        val aheadIds = mineAhead.mapTo(HashSet()) { it.id }
        val openRequests = requests.count { it.eventId in aheadIds }

        return MyEventsBoard(
            going = sections(MyEventsGroup.TODAY to todays, MyEventsGroup.UPCOMING to next, MyEventsGroup.PAST to goingPast),
            organizing = sections(MyEventsGroup.UPCOMING to mineAhead, MyEventsGroup.PAST to minePast),
            saved = sections(MyEventsGroup.THIS_WEEK to thisWeek, MyEventsGroup.LATER to afterWeek),
            goingAhead = goingAhead.size,
            awaiting = goingAhead.count { it.gathering?.awaitingApproval == true },
            organizingAhead = mineAhead.size,
            requests = openRequests,
            savedAhead = savedAhead.size,
            savedThisWeek = thisWeek.size,
            // Непрочитане рахуємо й у минулих: бейдж вкладки знає про всі чати, і чип не має з ним розходитись.
            goingBadge = going.count { it.id in unread },
            organizingBadge = mine.count { it.id in unread } + openRequests
        )
    }

    private fun sections(vararg groups: Pair<MyEventsGroup, List<Event>>) =
        groups.filter { it.second.isNotEmpty() }.map { MyEventsSection(it.first, it.second) }
}
