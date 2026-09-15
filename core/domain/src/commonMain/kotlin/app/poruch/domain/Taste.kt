package app.poruch.domain

import kotlin.time.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.toLocalDateTime

/**
 * Три відповіді з онбордингу — все, що застосунок знає про смак людини. Рядки, а не enum,
 * бо обидві платформи їх зберігають і передають. [answered] відрізняє «без уподобань» від
 * «ще не питали», щоб не показувати питання двічі.
 */
data class Taste(
    val interests: List<String> = emptyList(),
    val times: List<String> = emptyList(),
    val crowd: String = Crowd.ANY,
    val answered: Boolean = false
) {
    /** Відповіли, але нема за чим ранжувати: свідоме «покажи все». */
    val isBlank get() = interests.isEmpty() && times.isEmpty() && crowd == Crowd.ANY
}

/** Коли людина вільна, у локальному часі події. Чотири слоти, а не розклад: відповідь одним тапом. */
object TimeSlot {
    const val WEEKDAY_DAY = "weekday_day"
    const val WEEKDAY_EVENING = "weekday_evening"
    const val WEEKEND_DAY = "weekend_day"
    const val WEEKEND_EVENING = "weekend_evening"

    val all = listOf(WEEKDAY_DAY, WEEKDAY_EVENING, WEEKEND_DAY, WEEKEND_EVENING)

    /** Після роботи. */
    const val EVENING_FROM_HOUR = 17

    fun isSlot(value: String) = value in all
}

/** Бажаний розмір компанії. Пороги — місткість події, а не кількість учасників. */
object Crowd {
    const val INTIMATE = "intimate"
    const val MEDIUM = "medium"
    const val ANY = "any"

    val all = listOf(INTIMATE, MEDIUM, ANY)

    /** Стіл, кімната, будь-що. */
    const val INTIMATE_UP_TO = 12
    const val MEDIUM_UP_TO = 40

    fun isCrowd(value: String) = value in all
}

/** Відповіді на пристрої: потрібні ще до акаунта і переживають його. */
interface TasteStore {
    fun read(): Taste
    fun write(taste: Taste)
}

/**
 * Мінімум, за яким можна дати події бал. Спільний для [Event] і [EventIndexEntry], щоб
 * ранжувати повний індекс міста, а не лише завантажене вікно карток. Кімната описана двома
 * питаннями — розмір і чи є місце; в афіші кімнати нема, і обидва відповідають «ні».
 */
interface Rankable {
    val category: String
    val startsAt: String
    val timeZone: String
    val isCancelled: Boolean
    /** Розмір кімнати. Null — кімнати немає. */
    val roomCapacity: Int?
    /** Кімната є і в ній лишилось місце. */
    val roomHasSeats: Boolean
}

/**
 * Перетворює відповіді на порядок. Це бал, а не фільтр: усе, що мапа знайшла в області,
 * лишається, змінюється лише порядок. Виняток — скасована подія, вона йде в кінець.
 * Ваги — прості числа, щоб з порядку списку було видно, чому він такий.
 */
object TasteRanking {
    /** Інтерес важить найбільше. */
    const val INTEREST = 40
    /** Вільний час — різниця між планом і гарною ідеєю. */
    const val TIME = 25
    const val CROWD = 15
    /**
     * Повна подія варта показу (черга справжня), але не попереду відкритої. Афіша цих балів
     * не отримує: кімнати нема. Так імпорт лишається тлом (docs/event-discovery.md §4.2).
     */
    const val SEATS = 10
    /** Згасає за три дні: «цього тижня» — план, «наступного місяця» — може бути. */
    const val SOON = 10
    const val SOON_HOURS = 72
    private const val CANCELLED = -1000

    fun score(event: Rankable, taste: Taste, now: Instant): Int = score(event, taste, now, Zones())

    private fun score(event: Rankable, taste: Taste, now: Instant, zones: Zones): Int {
        if (event.isCancelled) return CANCELLED
        var total = 0
        if (event.category in taste.interests) total += INTEREST
        if (slotOf(event, zones) in taste.times) total += TIME
        if (fitsCrowd(event, taste.crowd)) total += CROWD
        if (event.roomHasSeats) total += SEATS
        total += soonness(event, now)
        return total
    }

    /**
     * Ключ часу: початок для майбутньої події, «зараз» для тієї, що вже йде, інакше довга
     * виставка висіла б угорі весь прокат. Збігається з `greatest(starts_at, now())` на сервері.
     * Null — нерозбірна дата, такі їдуть у кінець.
     */
    private fun interestingAt(event: Rankable, now: Instant): Instant? =
        runCatching { Instant.parse(event.startsAt) }.getOrNull()?.let { if (it < now) now else it }

    /** Порядок для всіх списків застосунку. Нічиї розбиває [interestingAt]. */
    fun <T : Rankable> rank(events: List<T>, taste: Taste, now: Instant): List<T> {
        // Бал і ключ рахуємо раз на подію, а не в компараторі: той викликається n·log n разів,
        // і розбір дати в ньому коштував ~34 мс на складання головної.
        val zones = Zones()
        val keyed = events.map { Triple(it, if (taste.isBlank) 0 else score(it, taste, now, zones), interestingAt(it, now)) }
        // Без відповідей бали однакові, тож скасоване опускає окремий ключ; з відповідями це робить CANCELLED.
        val first = if (taste.isBlank) compareBy<Triple<T, Int, Instant?>> { it.first.isCancelled }
                    else compareByDescending { it.second }
        // Не додавати thenBy { startsAt }: серед того, що вже йде, найдовший прокат знову стане першим.
        // sortedWith стабільне, рівні лишаються в порядку сервера.
        return keyed.sortedWith(first.then(compareBy(nullsLast()) { it.third })).map { it.first }
    }

    /** Кеш поясів: TimeZone.of — найдорожча операція тут. */
    private class Zones {
        private val known = mutableMapOf<String, TimeZone>()
        fun of(id: String): TimeZone = known.getOrPut(id) {
            runCatching { TimeZone.of(id) }.getOrElse { TimeZone.currentSystemDefault() }
        }
    }

    /** Події, що відповідають хоч чомусь із відповідей. Приймає список, щоб кешувати пояси. */
    fun <T : Rankable> matching(events: List<T>, taste: Taste): List<T> {
        val zones = Zones()
        return events.filter { !it.isCancelled && (it.category in taste.interests || slotOf(it, zones) in taste.times) }
    }

    /** Подія відповідає хоч чомусь із відповідей. Лише такі потрапляють у «Для вас». */
    fun matches(event: Rankable, taste: Taste): Boolean =
        !event.isCancelled && (event.category in taste.interests || slotOf(event) in taste.times)

    /** Слот події в її часовому поясі. */
    fun slotOf(event: Rankable): String? = slotOf(event, Zones())

    private fun slotOf(event: Rankable, zones: Zones): String? {
        val zone = zones.of(event.timeZone)
        val local = runCatching { Instant.parse(event.startsAt).toLocalDateTime(zone) }.getOrNull() ?: return null
        val weekend = local.dayOfWeek.isoDayNumber >= 6
        val evening = local.hour >= TimeSlot.EVENING_FROM_HOUR
        return when {
            weekend && evening -> TimeSlot.WEEKEND_EVENING
            weekend -> TimeSlot.WEEKEND_DAY
            evening -> TimeSlot.WEEKDAY_EVENING
            else -> TimeSlot.WEEKDAY_DAY
        }
    }

    /** `ANY` балів не дає: це відсутність відповіді. Афіша теж не дає — кімнати нема. */
    private fun fitsCrowd(event: Rankable, crowd: String): Boolean {
        val capacity = event.roomCapacity ?: return false
        return when (crowd) {
            Crowd.INTIMATE -> capacity <= Crowd.INTIMATE_UP_TO
            Crowd.MEDIUM -> capacity in (Crowd.INTIMATE_UP_TO + 1)..Crowd.MEDIUM_UP_TO
            else -> false
        }
    }

    private fun soonness(event: Rankable, now: Instant): Int {
        val start = runCatching { Instant.parse(event.startsAt) }.getOrNull() ?: return 0
        val hours = (start - now).inWholeHours
        if (hours < 0 || hours > SOON_HOURS) return 0
        return (SOON * (SOON_HOURS - hours) / SOON_HOURS).toInt()
    }
}
