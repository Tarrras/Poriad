package app.poruch.domain

import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Instant

/**
 * «Шукаю компанію» на афіші: мала спільнотна подія-супутник «Йдемо разом: …» (docs/companions.md).
 * Картка з `companions` — без імен: хто організатор, видно вже на сторінці супутника.
 */
data class CompanionCard(
    val id: String,
    /** Час зустрічі, ISO-8601. */
    val meetAt: String,
    val timeZone: String,
    /** Де зустрітись. Null — не сказали. */
    val meetNote: String?,
    val capacity: Int,
    /** Підтверджені, без організатора — як [Gathering.attendeeCount]. */
    val attendeeCount: Int,
    val membership: Membership,
    /** Мій пошук: замість «Долучитися» — перехід на нього. */
    val mine: Boolean
) {
    val isFull get() = attendeeCount >= capacity
}

/** Подія, на яку йдуть разом. Лише в супутника. */
data class CompanionParent(val id: String, val title: String)

/** Правила супутника. Сервер (`create_companion`) тримає ті самі: число рухається — рухається й тут. */
object CompanionRules {
    const val NOTE_MAX = 140
    const val MIN_CAPACITY = 2
    const val MAX_CAPACITY = 8
    val capacity = MIN_CAPACITY..MAX_CAPACITY
    const val DEFAULT_CAPACITY = 4
    /** Крок вибору часу зустрічі, хвилин. */
    const val STEP_MINUTES = 15

    /** Раніше за три години до початку — це вже не «разом на концерт», а окрема зустріч. */
    private val MEET_WINDOW = 3.hours
    private val DEFAULT_LEAD = 30.minutes
    private val STEP = STEP_MINUTES.minutes

    /** Шукати компанію можна на афішу, яка ще не почалась і яку не зняли. */
    fun canOffer(event: Event, now: Instant): Boolean {
        val listing = event.listing ?: return false
        return event.isPublished && !listing.isWithdrawn && event.startInstant?.let { it > now } == true
    }

    /** Час зустрічі на вибір: кроком 15 хв від трьох годин до початку до самого початку, лише майбутній. */
    fun meetTimes(startsAt: String, now: Instant): List<String> {
        val start = runCatching { Instant.parse(startsAt) }.getOrNull() ?: return emptyList()
        val steps = (MEET_WINDOW / STEP).toInt()
        return (steps downTo 0).map { start - STEP * it }.filter { it > now }.map { it.toString() }
    }

    /** За пів години до початку; коли вже пізно — найраніший, що лишився. */
    fun defaultMeetAt(startsAt: String, now: Instant): String? {
        val times = meetTimes(startsAt, now)
        val start = runCatching { Instant.parse(startsAt) }.getOrNull() ?: return null
        return times.firstOrNull { it == (start - DEFAULT_LEAD).toString() } ?: times.firstOrNull()
    }

    /** Що не так з формою. Порожньо — можна слати. */
    fun validate(startsAt: String, meetAt: String, note: String?, capacity: Int, now: Instant): List<DraftField> = buildList {
        val start = runCatching { Instant.parse(startsAt) }.getOrNull()
        val meet = runCatching { Instant.parse(meetAt) }.getOrNull()
        if (start == null || meet == null || meet <= now || meet > start || meet < start - MEET_WINDOW) add(DraftField.STARTS_AT)
        if ((note?.trim()?.length ?: 0) > NOTE_MAX) add(DraftField.DESCRIPTION)
        if (capacity !in CompanionRules.capacity) add(DraftField.CAPACITY)
    }
}
