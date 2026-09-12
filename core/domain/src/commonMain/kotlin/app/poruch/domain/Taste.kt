package app.poruch.domain

import kotlin.time.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.toLocalDateTime

/**
 * The three things the app asks on the way in, and the only things it claims to know about a
 * person's taste. Everything is a string, the way categories and filters already are, because both
 * platforms store and pass these around and neither should carry a Kotlin enum to do it.
 *
 * [answered] is what separates «has no preferences» from «has not been asked», and it is the only
 * reason the questions are not shown twice.
 */
data class Taste(
    val interests: List<String> = emptyList(),
    val times: List<String> = emptyList(),
    val crowd: String = Crowd.ANY,
    val answered: Boolean = false
) {
    /** Answered, but with nothing to rank on — a deliberate «show me everything». */
    val isBlank get() = interests.isEmpty() && times.isEmpty() && crowd == Crowd.ANY
}

/**
 * When a person is free, in the event's own local time. Four slots and not a schedule: the answer
 * has to be truthful after one tap, and nobody fills in a week grid to see what is on tonight.
 */
object TimeSlot {
    const val WEEKDAY_DAY = "weekday_day"
    const val WEEKDAY_EVENING = "weekday_evening"
    const val WEEKEND_DAY = "weekend_day"
    const val WEEKEND_EVENING = "weekend_evening"

    val all = listOf(WEEKDAY_DAY, WEEKDAY_EVENING, WEEKEND_DAY, WEEKEND_EVENING)

    /** After work, in the ordinary sense of it. */
    const val EVENING_FROM_HOUR = 17

    fun isSlot(value: String) = value in all
}

/** How many people someone wants around them. The thresholds are event capacity, not attendance. */
object Crowd {
    const val INTIMATE = "intimate"
    const val MEDIUM = "medium"
    const val ANY = "any"

    val all = listOf(INTIMATE, MEDIUM, ANY)

    /** A dinner table, then a room, then whatever. */
    const val INTIMATE_UP_TO = 12
    const val MEDIUM_UP_TO = 40

    fun isCrowd(value: String) = value in all
}

/** Answers kept on the device: they are useful before there is an account, and they outlive one. */
interface TasteStore {
    fun read(): Taste
    fun write(taste: Taste)
}

/**
 * Те мінімальне, за чим взагалі можна дати події бал.
 *
 * Існує, щоб ранжування працювало і над [Event], і над [EventIndexEntry], не знаючи різниці. Це не
 * узагальнення заради узагальнення: порядок має рахуватися над **повним** індексом міста, а не над
 * тим вікном карток, що встигло завантажитись, — інакше найкраща відповідь на смак людини не
 * підніметься нагору тільки тому, що вона 340-та за датою.
 *
 * Кімната описана двома питаннями, а не полем `capacity`, бо саме так її й питають: «якого розміру
 * компанія» і «чи лишилось місце». У афіші кімнати немає, і обидва відповідають «ні».
 */
interface Rankable {
    val category: String
    val startsAt: String
    val timeZone: String
    val isCancelled: Boolean
    /** Розмір кімнати; `null` там, де кімнати немає. */
    val roomCapacity: Int?
    /** Кімната є і в ній лишилось місце. */
    val roomHasSeats: Boolean
}

/**
 * Turns the answers into an order.
 *
 * A score, never a filter. The map found these events inside the area the reader is looking at, and
 * quietly dropping the ones that missed a checkbox would make the app lie about what is nearby —
 * so everything stays and only the order changes. A cancelled event is the single exception; it
 * sinks below everything else because it is not a plan any more.
 *
 * The weights are ordinary integers rather than a learned model: the reasons are the three answers
 * we asked for, and a person should be able to look at the list and see why it is in that order.
 */
object TasteRanking {
    /** What the person came for. Nothing else outranks the subject. */
    const val INTEREST = 40
    /** Being free when it happens is the difference between a plan and a nice idea. */
    const val TIME = 25
    const val CROWD = 15
    /**
     * A full event is still worth showing — the waitlist is real — but not ahead of an open one.
     *
     * Афіша не отримує цих балів ніколи: у неї немає кімнати, тож і вільних місць немає. Так
     * виконується правило з docs/event-discovery.md §4.2 — імпорт заповнює тло, а не змагається
     * за увагу з подіями спільноти — без окремого штрафу «бо це імпорт».
     */
    const val SEATS = 10
    /** Fades to nothing across three days: «this week» is a plan, «next month» is a maybe. */
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
     * Коли подія цікава зараз.
     *
     * Для майбутньої це її початок. Для тієї, що вже йде, — «зараз»: виставка з прокатом до
     * 30 вересня почалась місяць тому, і сортування за датою початку пришпилило б її до верху
     * списку на весь прокат. Те саме робить `greatest(starts_at, now())` на сервері — порядок
     * має бути один, інакше вікно карток приїжджає не під ту стрічку, яку людина бачить.
     *
     * `null` означає нерозбірну дату; такі рядки їдуть у кінець, а не падають.
     */
    private fun interestingAt(event: Rankable, now: Instant): Instant? =
        runCatching { Instant.parse(event.startsAt) }.getOrNull()?.let { if (it < now) now else it }

    /**
     * The order every list in the app uses. Ties break on [interestingAt], so two events a person
     * has said nothing about still come in the order they will actually happen — and one that is
     * already under way counts as «now» rather than as the date it began.
     */
    fun <T : Rankable> rank(events: List<T>, taste: Taste, now: Instant): List<T> {
        // Оцінка й ключ порядку рахуються один раз на подію, а не всередині порівняння.
        //
        // Компаратор кличуть n·log n разів, і кожен виклик піднімав часовий пояс та розбирав дату.
        // На півтори сотні подій це виходило понад тисячу таких розборів замість ста п'ятдесяти —
        // виміряно 34 мс на одне складання головної.
        val zones = Zones()
        val keyed = events.map { Triple(it, if (taste.isBlank) 0 else score(it, taste, now, zones), interestingAt(it, now)) }
        // Без відповідей бали однакові, тож скасоване опускає окремий ключ; з відповідями його
        // вже опускає сам бал (`CANCELLED`).
        val first = if (taste.isBlank) compareBy<Triple<T, Int, Instant?>> { it.first.isCancelled }
                    else compareByDescending { it.second }
        // Без `thenBy { startsAt }`: він повернув би саме той порядок, який ми щойно прибрали —
        // серед того, що вже йде, першим став би найдавніше початий, тобто найдовший прокат.
        // `sortedWith` стабільне, тож рівні лишаються в порядку сервера.
        return keyed.sortedWith(first.then(compareBy(nullsLast()) { it.third })).map { it.first }
    }

    /** Ті самі кілька подій ділять один пояс; піднімати його щоразу — найдорожче тут. */
    private class Zones {
        private val known = mutableMapOf<String, TimeZone>()
        fun of(id: String): TimeZone = known.getOrPut(id) {
            runCatching { TimeZone.of(id) }.getOrElse { TimeZone.currentSystemDefault() }
        }
    }

    /**
     * Ті з [events], що відповідають чомусь сказаному. Приймає список, а не подію: пояси й тут
     * варто піднімати один раз на всіх.
     */
    fun <T : Rankable> matching(events: List<T>, taste: Taste): List<T> {
        val zones = Zones()
        return events.filter { !it.isCancelled && (it.category in taste.interests || slotOf(it, zones) in taste.times) }
    }

    /**
     * True when an event answers something the person actually said. «Для вас» may only show these:
     * a suggestion that matched nothing is not a suggestion, it is the same list with a new title.
     */
    fun matches(event: Rankable, taste: Taste): Boolean =
        !event.isCancelled && (event.category in taste.interests || slotOf(event) in taste.times)

    /** The slot an event falls into, in the time zone where it happens. */
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

    /**
     * `ANY` earns nothing: it is the absence of an answer, not an answer every event satisfies.
     * Афіша теж не заробляє нічого — питання «яка компанія» їй не ставиться, бо розміру кімнати
     * в неї немає.
     */
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
