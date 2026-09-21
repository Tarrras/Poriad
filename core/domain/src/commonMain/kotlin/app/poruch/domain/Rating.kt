package app.poruch.domain

import kotlin.time.Duration.Companion.days
import kotlin.time.Instant

/** Оцінка завершеної кімнати. Організатор бачить усі без імен, учасник — лише свою ([mine]). */
data class EventRating(val score: Int, val comment: String?, val createdAt: String, val mine: Boolean)

/** Ті самі межі, що в `private.rate_event`: сервер усе одно перевірить, тут — щоб не показувати зайвого. */
object RatingRules {
    const val COMMENT_MAX = 500
    private val WINDOW = 14.days

    /** Учасник кімнати може оцінити її від кінця і ще [WINDOW]. */
    fun canRate(event: Event, now: Instant): Boolean {
        if (event.gathering?.joined != true || !event.isPublished) return false
        val end = event.endInstant ?: return false
        return end <= now && now < end + WINDOW
    }

    /** Середнє з одним знаком після коми, як на екрані: «4,3». Null — оцінок нема. */
    fun average(ratings: List<EventRating>): Double? =
        if (ratings.isEmpty()) null else kotlin.math.round(ratings.sumOf { it.score } * 10.0 / ratings.size) / 10
}
