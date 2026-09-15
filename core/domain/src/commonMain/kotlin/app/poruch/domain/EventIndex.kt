package app.poruch.domain

import kotlin.time.Instant

/**
 * Подія так, як її бачить мапа: де, коли і що це.
 *
 * Окремий тип, а не [Event] з порожніми полями: напівзаповнений об'єкт бреше мовчки. Індекс
 * тонкий, щоб повне місто важило десятки КБ і не потребувало стелі; повні картки приходять
 * вікном під те, що на екрані. Тут рівно стільки, щоб поставити пін, дати бал і склеїти
 * дублікат. Кожне нове поле множиться на кількість подій у місті.
 */
data class EventIndexEntry(
    val id: String,
    val latitude: Double,
    val longitude: Double,
    override val category: String,
    override val startsAt: String,
    override val timeZone: String,
    val title: String,
    /** `community` або `import`, як в `events.origin`. */
    val origin: String,
    /** Слаг джерела (`event_sources.slug`). Порожній для події спільноти. */
    val source: String? = null,
    /** Місткість кімнати. Null — кімнати немає, а не «місць нуль». */
    val capacity: Int? = null,
    val attendeeCount: Int = 0,
    /**
     * Події, склеєні в цю картку [DuplicateEvents]: той самий концерт в іншого продавця.
     * У базі обидва рядки лишаються, показуємо їх разом.
     */
    val mergedWith: List<String> = emptyList(),
    /**
     * Усі сеанси прокату в порядку часу, включно з власним. Заповнює [EventSeries]: та сама
     * вистава на тому самому майданчику кілька разів. На відміну від [mergedWith], це не
     * дублікати — на кожен сеанс окремий квиток. Картка показує найближчий, деталі — вибір дати.
     */
    val sessions: List<EventSession> = emptyList()
) : Rankable {
    /** За карткою стоїть більше одного рядка бази. */
    val isMerged get() = mergedWith.isNotEmpty()

    /** Усі ідентифікатори, які ця картка представляє, включно з власним. */
    val representedIds get() = listOf(id) + mergedWith

    /** Кількість сеансів. Один — прокату немає. */
    val sessionCount get() = maxOf(sessions.size, 1)

    /** Скільки сеансів прокату не показано в цій картці. */
    val otherSessionCount get() = maxOf(sessions.size - 1, 0)

    /** Картка стоїть за кількома сеансами. */
    val isSeries get() = sessions.size > 1

    val isCommunity get() = origin == EventOrigin.COMMUNITY

    /** Скільки місць лишилось. Null — кімнати немає. */
    val seatsLeft get() = capacity?.let { (it - attendeeCount).coerceAtLeast(0) }
    val isFull get() = seatsLeft == 0

    /** Завжди false: сервер кладе в індекс лише `status='published'`. */
    override val isCancelled get() = false
    override val roomCapacity get() = capacity
    override val roomHasSeats get() = seatsLeft?.let { it > 0 } == true

    val startInstant: Instant? get() = runCatching { Instant.parse(startsAt) }.getOrNull()
}

/**
 * Картка як рядок індексу. Для подій не з видачі: міні-мапа на деталях, глибоке посилання,
 * старий сервер без індексу.
 */
fun Event.asIndexEntry() = EventIndexEntry(
    id = id, latitude = latitude, longitude = longitude, category = category,
    startsAt = startsAt, timeZone = timeZone, title = title,
    origin = if (isCommunity) EventOrigin.COMMUNITY else EventOrigin.IMPORT,
    source = listing?.sourceName,
    capacity = gathering?.capacity, attendeeCount = gathering?.attendeeCount ?: 0
)

/**
 * Відповідь на запит області: увесь індекс і перше вікно карток одним запитом, бо мапа і
 * карусель показуються одночасно. [truncated] — запобіжник на випадок «мапа віддалена до
 * глобуса», на місті не спрацьовує.
 */
data class DiscoveryPage(
    val index: List<EventIndexEntry>,
    val total: Int,
    val truncated: Boolean,
    /** Перші картки в порядку часу, як їх поклав сервер. */
    val cards: List<Event>
) {
    companion object {
        val Empty = DiscoveryPage(emptyList(), 0, false, emptyList())
    }
}

/**
 * Один сеанс прокату: дата і id, за яким його відкрити. Дата тут, бо після згортання поглинуті
 * сеанси зникають зі списку, а карусель дат має працювати без запиту.
 */
data class EventSession(
    val id: String,
    val startsAt: String,
    val timeZone: String,
    /**
     * Скасований сеанс. З індексу не приходить, буває лише для відкритої події, яку зняли.
     * Див. [EventSeries.sessionsOf].
     */
    val cancelled: Boolean = false
) {
    val startInstant: Instant? get() = runCatching { Instant.parse(startsAt) }.getOrNull()
}
