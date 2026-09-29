package app.poruch.domain

import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime
import kotlin.time.Instant

/** Звідки подія в стрічці «У місті»: підпис над її назвою. */
enum class FeedSource { FOR_YOU, FOLLOWING, CITY }

data class FeedEntry(val event: Event, val source: FeedSource)

/** Що вибрано в ряду чипів над сіткою «У місті»: усе, час, ціна чи категорія. Одне на раз. */
enum class FeedFilterKind { ALL, TODAY, TOMORROW, WEEKEND, FREE, CATEGORY }

data class FeedFilter(val kind: FeedFilterKind = FeedFilterKind.ALL, val category: EventCategory? = null)

/** Головна: як з кількох списків скласти одну стрічку. Чисте правило, однакове на обох платформах. */
object HomeRules {
    /** Скільки своїх подій показує блок «Ваше»: решта — у «Моїх подіях». */
    const val PERSONAL_LIMIT = 3

    /** Скільки рядків «У місті» видно одразу; «Показати ще» додає стільки ж. */
    const val FEED_PAGE = 10

    /** Менша сітка не варта фільтрів: два постери фільтром не ділять. */
    const val MIN_FILTERABLE = 6

    /** Категорія з меншою кількістю подій у стрічці — не вибір, а порожній екран. */
    const val MIN_CATEGORY_CHIP = 4

    /** Більше категорій у ряду — це вже друга панель пошуку. */
    const val MAX_CATEGORY_CHIPS = 4

    /**
     * Одна стрічка з трьох списків: по одній події з кожного по колу, щоб жодне джерело не витіснило решту.
     * Подія стоїть раз, там, де її знайдено першою; підпис дає найсильніший сигнал: підписка, потім смак.
     * [skip] — те, що людина вже бачить вище («Ваше»).
     */
    fun feed(forYou: List<Event>, city: List<Event>, following: List<Event>, skip: Set<String> = emptySet()): List<FeedEntry> {
        val followed = following.mapTo(HashSet()) { it.id }
        val picked = forYou.mapTo(HashSet()) { it.id }
        val lanes = listOf(forYou, city, following).map { it.iterator() }
        val seen = skip.toHashSet()
        val feed = ArrayList<FeedEntry>()
        do {
            var added = false
            for (lane in lanes) {
                while (lane.hasNext()) {
                    val event = lane.next()
                    if (!seen.add(event.id)) continue
                    val source = when (event.id) {
                        in followed -> FeedSource.FOLLOWING
                        in picked -> FeedSource.FOR_YOU
                        else -> FeedSource.CITY
                    }
                    feed += FeedEntry(event, source)
                    added = true
                    break
                }
            }
        } while (added)
        return feed
    }

    /**
     * Найближчому плану велика картка з маршрутом до лиця, коли він скоро (сьогодні, завтра) або за ним хтось
     * чекає (чат, запит). Подія за три тижні — рядок: маршрут їй ні до чого. Минула й скасована — теж рядок.
     */
    fun isLead(event: Event, waiting: Boolean, now: Instant, zoneId: String): Boolean {
        if (event.isCancelled || event.hasEnded(now)) return false
        if (waiting) return true
        val start = event.startInstant ?: return false
        return start < range(FeedFilterKind.TOMORROW, now, TimeZone.of(zoneId)).second
    }

    /**
     * Чипи над сіткою: усе, потім те, що щось звужує й щось знаходить (час, безкоштовне, найбільші категорії).
     * Чип, що лишає все чи нічого, не показуємо. Порожній список — рядка нема.
     */
    fun chips(entries: List<FeedEntry>, now: Instant, zoneId: String): List<FeedFilter> {
        if (entries.size < MIN_FILTERABLE) return emptyList()
        val zone = TimeZone.of(zoneId)
        fun narrows(filter: FeedFilter) = entries.count { matches(filter, it.event, now, zone) } in 1 until entries.size
        val kinds = listOf(FeedFilterKind.TODAY, FeedFilterKind.TOMORROW, FeedFilterKind.WEEKEND, FeedFilterKind.FREE)
            .map { FeedFilter(it) }.filter(::narrows)
        val categories = entries.groupingBy { it.event.category }.eachCount().entries
            .filter { it.key != EventCategory.UNKNOWN && it.value >= MIN_CATEGORY_CHIP && it.value < entries.size }
            .sortedByDescending { it.value }.take(MAX_CATEGORY_CHIPS).map { FeedFilter(FeedFilterKind.CATEGORY, it.key) }
        return if (kinds.isEmpty() && categories.isEmpty()) emptyList() else listOf(FeedFilter()) + kinds + categories
    }

    fun apply(entries: List<FeedEntry>, filter: FeedFilter, now: Instant, zoneId: String): List<FeedEntry> {
        if (filter.kind == FeedFilterKind.ALL) return entries
        val zone = TimeZone.of(zoneId)
        return entries.filter { matches(filter, it.event, now, zone) }
    }

    private fun matches(filter: FeedFilter, event: Event, now: Instant, zone: TimeZone): Boolean = when (filter.kind) {
        FeedFilterKind.ALL -> true
        // Безкоштовна афіша — за словом джерела; кімната — якщо це не «Йдемо разом» на платний концерт.
        FeedFilterKind.FREE -> event.listing?.isFree == true || event.gathering.let { it != null && it.companionOf == null }
        FeedFilterKind.CATEGORY -> event.category == filter.category
        // Перетин з добою, а не лише початок: виставка, що йде, і «сьогодні», і «завтра».
        else -> {
            val (from, to) = range(filter.kind, now, zone)
            val start = event.startInstant
            start != null && start < to && (event.endInstant ?: start) > from
        }
    }

    /** Межі чипа в поясі пристрою. Вихідні — як `DateFilter.WEEKEND`: з найближчої суботи (сьогодні, якщо вже вихідні) до понеділка. */
    private fun range(kind: FeedFilterKind, now: Instant, zone: TimeZone): Pair<Instant, Instant> {
        val today = now.toLocalDateTime(zone).date
        fun day(offset: Int) = today.plus(offset, DateTimeUnit.DAY).atStartOfDayIn(zone)
        val isoDay = today.dayOfWeek.isoDayNumber
        return when (kind) {
            FeedFilterKind.TOMORROW -> day(1) to day(2)
            FeedFilterKind.WEEKEND -> day((6 - isoDay).coerceAtLeast(0)) to day(8 - isoDay)
            else -> day(0) to day(1)
        }
    }
}
