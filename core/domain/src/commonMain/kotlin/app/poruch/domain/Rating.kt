package app.poruch.domain

import app.poruch.domain.RatingTag.*
import kotlin.time.Duration.Companion.days
import kotlin.time.Instant

/** Оцінка завершеної кімнати. Організатор бачить усі без імен, учасник — лише свою ([mine]). */
data class EventRating(
    val score: Int, val comment: String?, val createdAt: String, val mine: Boolean,
    val tags: List<RatingTag> = emptyList()
)

/**
 * «Що сподобалось» у шторці оцінки. [key] — те, що лежить у `event_ratings.tags`; словник закритий на сервері.
 * Один ключ — одне значення в усіх категоріях, щоб лічильники організатора не розпадались.
 */
enum class RatingTag(val key: String) {
    // Загальні: підходять будь-якій події.
    ATMOSPHERE("atmosphere"), ORGANIZATION("organization"), PLACE("place"), PEOPLE("people"), ON_TIME(
        "on_time"
    ),

    // Про суть події: показуються лише в своїх категоріях (див. [RatingRules.tagsFor]).
    MUSIC("music"), SOUND("sound"), HUMOR("humor"), HOST("host"), PROGRAM("program"),
    COACH("coach"), WORKOUT("workout"), ROUTE("route"), VIEWS("views"), PACE("pace"),
    GUIDE("guide"), STORIES("stories"), FOOD("food"), DRINKS("drinks"),
    GAME_CHOICE("game_choice"), RULES("rules"), CONVERSATION("conversation"),
    KIDS_LIKED("kids_liked"), SAFETY("safety"), SPEAKERS("speakers"), USEFUL("useful"), NETWORKING("networking");

    companion object {
        /** Невідомий ключ (новіший сервер) — пропускаємо, а не падаємо. */
        fun fromKey(key: String): RatingTag? = entries.firstOrNull { it.key == key }
    }
}

data class TagCount(val tag: RatingTag, val count: Int)

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

    /**
     * Шість тегів шторки для категорії: спершу про суть події, далі загальні. Невідома категорія — лише загальні.
     * Нова категорія в [EventRules.categories] без рядка тут отримає загальний набір.
     */
    fun tagsFor(category: String): List<RatingTag> = when (category) {
        "music" -> listOf(ATMOSPHERE, MUSIC, SOUND, ORGANIZATION, PLACE, ON_TIME)
        "comedy" -> listOf(HUMOR, HOST, ATMOSPHERE, PLACE, ORGANIZATION, ON_TIME)
        "sport" -> listOf(COACH, WORKOUT, PEOPLE, PLACE, ORGANIZATION, ON_TIME)
        "outdoors" -> listOf(ROUTE, VIEWS, PACE, PEOPLE, ORGANIZATION, ON_TIME)
        "tours" -> listOf(GUIDE, STORIES, ROUTE, PACE, ORGANIZATION, ON_TIME)
        "food" -> listOf(FOOD, DRINKS, ATMOSPHERE, PEOPLE, PLACE, ORGANIZATION)
        "games" -> listOf(GAME_CHOICE, RULES, PEOPLE, ATMOSPHERE, PLACE, ORGANIZATION)
        "art" -> listOf(HOST, PROGRAM, ATMOSPHERE, PEOPLE, PLACE, ORGANIZATION)
        "social" -> listOf(PEOPLE, CONVERSATION, ATMOSPHERE, PLACE, ORGANIZATION, ON_TIME)
        "kids" -> listOf(KIDS_LIKED, HOST, SAFETY, PLACE, ORGANIZATION, ON_TIME)
        "conference" -> listOf(SPEAKERS, USEFUL, NETWORKING, PLACE, ORGANIZATION, ON_TIME)
        else -> listOf(ATMOSPHERE, ORGANIZATION, PLACE, PEOPLE, ON_TIME)
    }

    /** Що відзначили найчастіше: для організатора, від більшого до меншого, рівні — в порядку шторки. */
    fun tagCounts(ratings: List<EventRating>): List<TagCount> =
        ratings.flatMap { it.tags }.groupingBy { it }.eachCount()
            .map { (tag, count) -> TagCount(tag, count) }
            .sortedWith(compareByDescending<TagCount> { it.count }.thenBy { it.tag.ordinal })
}
