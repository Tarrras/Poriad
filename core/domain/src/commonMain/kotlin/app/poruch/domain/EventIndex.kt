package app.poruch.domain

import kotlin.time.Instant

/**
 * Подія так, як її бачить мапа: де вона, коли й що це.
 *
 * Окремий тип від [Event], а не той самий із порожніми полями. Причина та сама, з якої [Event]
 * колись розділився на [Gathering] і [Listing]: напівзаповнений об'єкт бреше мовчки. Картка без
 * адреси й обкладинки — це не картка з порожньою адресою, це **не картка**, і компілятор має
 * сказати це замість рев'ю.
 *
 * Навіщо взагалі два рівні. Доти, доки одна відповідь несла і координати для піна, і обкладинку
 * для картки, вона важила 306 КБ на 300 подій — і тому їх було 300, а не всі 432: сервер мусив
 * ставити стелю. Розділені, обидва питання дешевшають настільки, що стеля стає непотрібною:
 * повний індекс міста — 66 КБ і 14 мс, а картки приходять вікном під те, що справді на екрані.
 *
 * Тут рівно те, що потрібно, щоб **поставити пін**, **дати події бал** і **склеїти дублікат**.
 * Нічого більше сюди додавати не варто: кожне поле множиться на кількість подій у місті.
 */
data class EventIndexEntry(
    val id: String,
    val latitude: Double,
    val longitude: Double,
    override val category: String,
    override val startsAt: String,
    override val timeZone: String,
    val title: String,
    /** `community` чи `import` — як його називає `events.origin`. */
    val origin: String,
    /** Коротке імʼя джерела (`event_sources.slug`); порожнє для події спільноти. */
    val source: String? = null,
    /** Місткість кімнати. `null` означає «кімнати немає», а не «місць нуль». */
    val capacity: Int? = null,
    val attendeeCount: Int = 0,
    /**
     * Ідентифікатори подій, склеєних у цю картку — той самий концерт в іншого продавця.
     *
     * Порожньо майже завжди. Непорожньо означає, що [DuplicateEvents] знайшла дублікат: у базі
     * обидва рядки лишаються, просто показують їх разом.
     */
    val mergedWith: List<String> = emptyList()
) : Rankable {
    /** Скільки рядків бази стоїть за цією карткою. */
    val isMerged get() = mergedWith.isNotEmpty()

    /** Усі ідентифікатори, які ця картка представляє, включно з власним. */
    val representedIds get() = listOf(id) + mergedWith

    val isCommunity get() = origin == EventOrigin.COMMUNITY

    /** Скільки місць лишилось. `null` там, де кімнати немає й питання не стоїть. */
    val seatsLeft get() = capacity?.let { (it - attendeeCount).coerceAtLeast(0) }
    val isFull get() = seatsLeft == 0

    /**
     * Скасована подія в індекс не потрапляє: сервер відбирає лише `status='published'`. Тому не
     * «ми не знаємо», а «такої тут не буває».
     */
    override val isCancelled get() = false
    override val roomCapacity get() = capacity
    override val roomHasSeats get() = seatsLeft?.let { it > 0 } == true

    val startInstant: Instant? get() = runCatching { Instant.parse(startsAt) }.getOrNull()
}

/**
 * Картка, показана як рядок індексу.
 *
 * Потрібно там, де подія прийшла не з видачі: міні-мапа на деталях, подія з глибокого посилання,
 * старий сервер без індексу. Втрачається при цьому лише те, чого в індексі й не буває.
 */
fun Event.asIndexEntry() = EventIndexEntry(
    id = id, latitude = latitude, longitude = longitude, category = category,
    startsAt = startsAt, timeZone = timeZone, title = title,
    origin = if (isCommunity) EventOrigin.COMMUNITY else EventOrigin.IMPORT,
    source = listing?.sourceName,
    capacity = gathering?.capacity, attendeeCount = gathering?.attendeeCount ?: 0
)

/**
 * Відповідь на один запит області: увесь індекс і перше вікно карток разом.
 *
 * Разом, а не двома запитами, бо перший екран не повинен чекати двох подорожей: індекс потрібен
 * мапі, картки — каруселі, і показують їх одночасно.
 *
 * [truncated] — це не стеля, а запобіжник. На місті він не спрацьовує ніколи; він існує, щоб
 * один запит не вивіз усю країну, якщо мапу віддалити до глобуса.
 */
data class DiscoveryPage(
    val index: List<EventIndexEntry>,
    val total: Int,
    val truncated: Boolean,
    /** Перші картки в порядку часу — рівно ті, що сервер поклав у відповідь. */
    val cards: List<Event>
) {
    companion object {
        val Empty = DiscoveryPage(emptyList(), 0, false, emptyList())
    }
}
