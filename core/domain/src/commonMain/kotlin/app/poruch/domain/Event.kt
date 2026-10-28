package app.poruch.domain

import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.TimeZone
import kotlinx.datetime.minus
import kotlinx.datetime.toLocalDateTime

/** [line] — речення «що це», [excerpt] — уривок опису. Обидва null — сказати нічого. */
data class EventAbout(val line: String?, val excerpt: String?)

/**
 * Модель події, незалежна від UI. Час — ISO-8601 в UTC.
 *
 * Подія буває двох видів, і рівно одна грань заповнена (вирішує `events.origin` на сервері):
 * - [Gathering] — кімната, яку створила людина: місткість, черга, підтвердження, організатор;
 * - [Listing] — афіша з відкритого джерела: назва джерела, ціна, посилання на квиток.
 *
 * Поля участі живуть у [gathering], а не тут, щоб картка не могла показати «Лишилось 1 місце»
 * під чужим концертом. Обидві грані порожні — зіпсований рядок; екрани показують його як подію
 * без дій, а не падають.
 */
data class Event(
    val id: String, val title: String, val description: String, override val category: EventCategory,
    val city: String, val address: String,
    override val startsAt: String, val endsAt: String, override val timeZone: String, val status: EventStatus,
    val latitude: Double, val longitude: Double, val imageUrl: String? = null,
    /** Кімната: заповнена лише для події, яку створила людина. */
    val gathering: Gathering? = null,
    /** Оголошення: заповнене лише для імпорту та партнерських подій. */
    val listing: Listing? = null,
    /**
     * Усі сеанси прокату, якщо картка стоїть за кількома. Сервер цього поля не знає: його
     * заповнює спільний шар з [EventSeries], щоб екрани не шукали рядок в індексі на кожну промальовку.
     */
    val sessions: List<EventSession> = emptyList(),
    /** Хто виступає, у серверному порядку. Порожньо, коли сервер артистів не знає (старий сервер, prod без даних). */
    val artists: List<Artist> = emptyList(),
    /** Одне речення «що це» від агента імпорту (`events.blurb`). Null — ще не написано чи подія від людей. */
    val blurb: String? = null,
    /** Опис, що чіпляє, від того самого агента (`events.pitch`, docs/return-hooks.md): наш текст, тож показуємо повністю. */
    val pitch: String? = null
) : Rankable {
    override val isCancelled get() = status == EventStatus.CANCELLED || status == EventStatus.HIDDEN ||
        listing?.state == ListingState.CANCELLED

    /** Не відбудеться на цей час: скасовано чи відкладено без нової дати. Корінець гасне сірим (`ticketStub`). */
    val isCalledOff get() = isCancelled || listing?.state == ListingState.POSTPONED

    // ---- Прокат

    /** Чи ця картка стоїть за кількома сеансами. */
    val isSeries get() = sessions.size > 1

    /** Скільки сеансів прокату ще не показано в цій картці. */
    val otherSessionCount get() = maxOf(sessions.size - 1, 0)

    /**
     * Скільки інших днів у прокаті, крім дня цієї картки. Окремо від [otherSessionCount]:
     * два сеанси одного вечора — це «ще 1 сеанс», а не «ще 1 дата».
     */
    val otherSessionDays: Int by lazy { EventSeries.otherDays(sessions) }

    // ---- Для ранжування. Обидва поля стосуються кімнати, тож без неї відповідають «ні».
    override val roomCapacity get() = gathering?.capacity
    override val roomHasSeats get() = gathering?.isFull == false
    val isPublished get() = status == EventStatus.PUBLISHED

    /** Подія, до якої можна прийти, а не лише подивитись. */
    val isCommunity get() = gathering != null

    /** Зустріч від людини з вільним місцем, не скасована: те, заради чого застосунок, і що головна ставить першим. */
    val isOpenRoom get() = gathering?.isFull == false && !isCancelled

    /** Організатор або джерело. Null — зіпсований рядок. */
    val publisherName get() = gathering?.organizerName?.takeIf { it.isNotBlank() } ?: listing?.sourceName

    /** Є лише в кімнати: блокувати й скаржитись можна тільки на людину. */
    val organizerId get() = gathering?.organizerId

    /** Склад для картки: до [DiscoveryRules.CARD_ARTISTS] імен у серверному порядку, решту каже [moreArtists]. Повний — [artists]. */
    val cardArtists: List<Artist> get() = artists.take(DiscoveryRules.CARD_ARTISTS)
    val moreArtists: Int get() = (artists.size - DiscoveryRules.CARD_ARTISTS).coerceAtLeast(0)

    /** Заклад з `public.places`. Лише в афіші: у спільнотних подій місця нема. */
    val placeId get() = listing?.placeId
    val placeName get() = listing?.placeName?.takeIf { it.isNotBlank() }

    /** Підпис місця в картці: назва закладу, коли вона є, інакше адреса або місто. */
    val placeLabel: String get() = placeName ?: address.ifBlank { city }

    /** Назва для показу: без капсу, з лапками-ялинками й апострофом ([TitleRules]). Сама [title] лишається як прийшла. */
    val displayTitle: String by lazy { TitleRules.display(title) }

    /**
     * Назва на квитку-картці: у супутника афіші без «Йдемо разом: » — рейка «З ким піти» і «Збирає …» на картці це вже
     * кажуть, а префікс з'їдав два з чотирьох рядків назви. Деталі, пуші й календар лишають повну назву.
     */
    val cardTitle: String by lazy {
        // Префікс ставить лише сервер супутнику; у даних стрічки `companionOf` може не приїхати, тож досить зустрічі.
        if (gathering != null) displayTitle.removePrefix("Йдемо разом: ").ifBlank { displayTitle } else displayTitle
    }

    /**
     * Опис, який дозволено показати. Для афіші — лише початок: чужа анотація захищена авторським
     * правом (docs/event-ingestion.md §8), решту читають на сайті джерела. Обмеження правове,
     * тому живе в домені, а не в екранах.
     */
    val displayDescription: String
        get() = if (listing == null || description.length <= LISTING_DESCRIPTION_PREVIEW) description
        else description.take(LISTING_DESCRIPTION_PREVIEW).trimEnd().trimEnd(',', ';', '—', '-', '.') + "…"

    /**
     * Що це за подія — тому, хто бачить її вперше (стос «Ваш тиждень», docs/return-hooks.md): речення «що це» і під ним
     * опис агента ([pitch]), а поки його нема — уривок дозволеного опису продавця. Одне речення часто загадкове
     * («Шість жінок і досвід…»), а опис продавця починається з SEO-вступу.
     */
    val about: EventAbout
        // Абзаци опису — в один рядок: у кількох рядках стосу «…» інакше стояло окремим рядком. Гачок продавця на
        // початку («Чому варто відвідати…?», «Яскраве шоу!») відрізаємо: першим під квитком стояв саме він.
        get() = EventAbout(
            blurb?.trim()?.takeIf { it.isNotEmpty() },
            pitch?.trim()?.takeIf { it.isNotEmpty() }
                ?: displayDescription.replace(WHITESPACE, " ").trim().let { var s = it; while (SELLER_HOOK.containsMatchIn(s)) s = SELLER_HOOK.replaceFirst(s, ""); s }
                    .takeIf { it.isNotEmpty() && it != "…" }
        )

    /** Опис обрізано, тож посилання «читати повністю» має сенс. */
    val descriptionTruncated get() = displayDescription.length < description.length

    // ---- Час. Рахуємо тут, щоб Android та iOS відповідали однаково.

    // Парсимо раз на екземпляр: `isListed`/`isUnderway`/`hasEnded` кличуть це по кілька разів на подію,
    // а фолди екранів — на кожну емісію стану. Поза конструктором, тож `equals`/`copy` не зачіпає.
    val startInstant: Instant? by lazy { runCatching { Instant.parse(startsAt) }.getOrNull() }
    val endInstant: Instant? by lazy { runCatching { Instant.parse(endsAt) }.getOrNull() }

    /** Почалася і ще триває. */
    fun isUnderway(now: Instant): Boolean {
        val start = startInstant ?: return false
        val end = endInstant ?: return false
        return start <= now && end > now
    }

    /**
     * Прокат, а не сеанс: виставка, ярмарок, фестиваль. Сеансу на картці досить години початку,
     * прокату — «до коли». Міряємо тривалістю, а не календарем: концерт з 23:00 до 02:00 — один вечір.
     */
    val isMultiDay: Boolean get() {
        val start = startInstant ?: return false
        val end = endInstant ?: return false
        return end - start > RUN_FROM
    }

    /**
     * Уже почалася. Для сеансу прокату це межа продажу: показати можна, купити квиток — ні.
     * Для тижневої виставки не має значення, туди купують і посеред прокату.
     */
    fun hasStarted(now: Instant): Boolean = startInstant?.let { it <= now } ?: false

    /** Завершилася. Таку подію не пропонуємо. */
    fun hasEnded(now: Instant): Boolean = endInstant?.let { it <= now } ?: false

    /** Ще не завершилась — показуємо у планах. */
    fun isCurrent(now: Instant): Boolean = !hasEnded(now)

    /** Ще можна піти, тож пропонуємо у стрічках: див. [isListed] нижче. */
    fun isListed(now: Instant): Boolean {
        val start = startInstant ?: return false
        val end = endInstant ?: return false
        return isListed(start, end, title, now)
    }

    companion object {
        /** Скільки символів чужого опису показуємо, перш ніж відіслати до джерела. */
        const val LISTING_DESCRIPTION_PREVIEW = 200
        private val WHITESPACE = Regex("\\s+")
        /** Перше речення-питання чи оклик. «?» усередині назви («Що Нового?») не рахується: за ним не пробіл, а «»». */
        private val SELLER_HOOK = Regex("^[^.?!…]*[?!]+(?=\\s|$)\\s*")

        /** Довше за добу — це вже не сеанс, а прокат. */
        private val RUN_FROM = 24.hours

        /** Одноденний ярмарок чи фестиваль: довший за вечір, з назвою, що це каже. Коротша подія з «фест» — концерт фестивалю. */
        private val DROP_IN_FROM = 4.hours

        /**
         * Корені назв, куди приходять будь-коли. Лише разом із [DROP_IN_FROM]: «Сорочинський ярмарок» на дві години —
         * вистава. Серед 4–24-годинних без цих слів — вистави з вигаданим кінцем. Той самий список у `private.is_listed`.
         */
        private val DROP_IN = Regex("фест|fest|ярмар|маркет|market|базар|експо|expo|fair|виставк|форум|forum|саміт|summit|конференц|пікнік|picnic|толок|свято|день міста|ринок")

        /**
         * Чи пропонувати подію людині, що шукає, куди піти. Сеанс (стендап, концерт) — до початку: на той,
         * що вже йде, не встигнуть. Прокат і одноденний ярмарок чи фестиваль — до кінця: туди йдуть і посеред.
         * Свої плани, деталі й чат цим не обмежені. Дзеркало серверної `private.is_listed`.
         */
        fun isListed(start: Instant, end: Instant, title: String, now: Instant): Boolean =
            end > now && (start > now || end - start > RUN_FROM ||
                (end - start > DROP_IN_FROM && DROP_IN.containsMatchIn(title.lowercase())))
    }
}

/**
 * Кімната: усе, що робить подію такою, до якої приходять. Місткість живе тут, бо поза кімнатою
 * її нема: `events.capacity` обов'язковий лише при `origin = 'community'`.
 */
data class Gathering(
    val organizerId: String,
    /** Порожній, поки в організатора нема публічного профілю. Заміну підбирає UI. */
    val organizerName: String,
    val capacity: Int,
    val attendeeCount: Int,
    val joined: Boolean,
    /** Статус цього акаунта в події, див. [Membership]. */
    val membership: Membership = Membership.NONE,
    /** Приєднання — запит організатору, а не відкриті двері. */
    val approvalRequired: Boolean = false,
    /** Вікові межі гостей. Сервер відмовляє тим, хто поза діапазоном. */
    val minAge: Int = SafetyRules.MIN_SIGNUP_AGE,
    val maxAge: Int? = null,
    /**
     * Чат учасників (Telegram, Instagram тощо). Сервер віддає його лише організатору й
     * підтвердженим учасникам, решті — null. Куди веде — не перевіряємо, див. [ContactRules].
     */
    val contactUrl: String? = null,
    /** Супутник «Йдемо разом»: на яку афішу йдуть. Null — звичайна подія. */
    val companionOf: CompanionParent? = null,
    /** Афішу перенесли, збір чекає рішення організатора (R7а). */
    val pendingMeet: PendingMeet? = null
) {
    val seatsLeft get() = (capacity - attendeeCount).coerceAtLeast(0)

    /** Є куди написати: посилання показують лише тим, кому сервер його віддав. */
    val hasContact get() = !contactUrl.isNullOrBlank()
    val isFull get() = seatsLeft == 0
    val awaitingApproval get() = membership == Membership.REQUESTED

    /** Організатор звузив вік порівняно з «будь-хто на платформі». */
    val hasAgeLimit get() = minAge > SafetyRules.MIN_SIGNUP_AGE || maxAge != null

    /** Місць лишилось мало — варте окремого рядка. Поріг спільний для обох платформ. */
    val isScarce get() = seatsLeft in 1..(capacity / SCARCITY_FRACTION).coerceAtLeast(MIN_SCARCE_SEATS)

    companion object {
        /** П'ята частина кімнати або менше — «поспішайте»; менше трьох місць — завжди. */
        private const val SCARCITY_FRACTION = 5
        private const val MIN_SCARCE_SEATS = 3
    }
}

/**
 * Оголошення: подія, яку ми лише показуємо, а не проводимо. [sourceName] обов'язкове —
 * атрибуція є умовою права показувати ці рядки (docs/event-ingestion.md §8).
 */
data class Listing(
    val sourceName: String,
    /** Сторінка джерела: там купують квиток і читають повний опис. */
    val canonicalUrl: String? = null,
    /** Найдешевший квиток у гривнях. Null — джерело не сказало, а не «безкоштовно». */
    val priceMin: Double? = null,
    val isFree: Boolean? = null,
    val status: ImportStatus = ImportStatus.LIVE,
    /** Id у `public.places`: одна точка на мапі, той самий ключ, що в [MapPins]. */
    val placeId: String? = null,
    /** Назва закладу («Малевич»), коротша й певніша за початок адреси. */
    val placeName: String? = null,
    /** Стан з усіх продавців (docs/event-offers.md R4, R8). Сервер без фази 4 його не знає — тоді каже [status]. */
    val state: ListingState = ListingState.of(status),
    /** Стара дата перенесеної події: «~~пт 21.11~~ → нд 23.11». Лише при [ListingState.SCHEDULED]. */
    val previousStartsAt: String? = null,
    /** Коли адресна перевірка востаннє читала сторінки продавців: «Перевірено сьогодні о 09:00». */
    val checkedAt: String? = null,
    /** Продавці, основний першим. Порожньо — сервер без фази 4, тоді [sellers] бере основного з полів вище. */
    val offers: List<Offer> = emptyList()
) {
    /**
     * Не відбудеться на цей час або ніде не продають: скасовано, відкладено, не знайшли в продажу. Кнопки квитків нема,
     * збережений запис лишається як позначка, не як план.
     */
    val isWithdrawn get() = state != ListingState.SCHEDULED

    /** Перенесена: стан «в силі», а стара дата відома. */
    val isMoved get() = state == ListingState.SCHEDULED && previousStartsAt != null

    /** Є посилання на джерело — можна показувати кнопку. */
    val hasSource get() = !canonicalUrl.isNullOrBlank()

    /** Хто продає, основний першим. Без даних фази 4 — лише основний. Лише ті, куди є посилання. */
    val sellers: List<Offer>
        get() = offers.ifEmpty { listOf(Offer(sourceName, canonicalUrl, priceMin, isFree, live = !isWithdrawn)) }
            .filter { !it.url.isNullOrBlank() }

    /**
     * Один продавець пише «скасовано» чи «відкладено», а подія в силі, бо інший її продає (рішення 24.10): показуємо, хто
     * що повідомив, а не ховаємо подію.
     */
    val sellerReport: Offer? get() = if (isWithdrawn) null else offers.firstOrNull { it.reported != null }

    /** З подією щось сталось чи продавці кажуть різне: квитки на деталях першим блоком. */
    val needsAttention get() = isWithdrawn || isMoved || sellerReport != null

    /** Підпис афіші: «Concert.ua, Karabas» — усі живі продавці (питання 5, рішення 20.10), інакше основний. */
    val sellerNames: String
        get() = offers.filter { it.live }.map { it.sourceName }.distinct().ifEmpty { listOf(sourceName) }.joinToString(", ")
}

/**
 * Пропозиція одного продавця (`public.event_offers`). [live] — продає зараз; знятою повертають квиток. [reported] —
 * сторінка продавця прямо каже «скасовано» чи «відкладено» (лише ці два стани).
 */
data class Offer(
    val sourceName: String,
    val url: String?,
    val priceMin: Double? = null,
    val isFree: Boolean? = null,
    val live: Boolean = true,
    val reported: ListingState? = null
)

/** Стан афіші з усіх продавців, як його називає `event_result.state`. Розпродаж — не стан (рішення 20.10). */
enum class ListingState(val key: String) {
    SCHEDULED("scheduled"), CANCELLED("cancelled"), POSTPONED("postponed"),
    /** Жоден продавець не продає, а сильних свідчень нема: «Не знайшли в продажу», без тривоги. */
    UNKNOWN("unknown");

    companion object {
        /** Невідоме значення (сервер новіший) — null: тоді вирішує `import_status`. */
        fun fromKey(key: String?): ListingState? = entries.firstOrNull { it.key == key }

        /** Сервер без стану: знята — «не знайшли», інакше «в силі». */
        fun of(status: ImportStatus) = if (status == ImportStatus.WITHDRAWN) UNKNOWN else SCHEDULED
    }
}

/** «Перевірено сьогодні о 09:00» / «вчора о 21:00» / «18.10». [time] — «09:00», [date] — «18.10», у поясі телефона. */
data class CheckedLabel(val day: CheckedDay, val time: String, val date: String) {
    companion object {
        fun of(checkedAt: String?, now: Instant, zone: TimeZone): CheckedLabel? {
            val at = checkedAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return null
            val local = at.toLocalDateTime(zone)
            val today = now.toLocalDateTime(zone).date
            val day = when (local.date) {
                today -> CheckedDay.TODAY
                today.minus(DatePeriod(days = 1)) -> CheckedDay.YESTERDAY
                else -> CheckedDay.EARLIER
            }
            fun two(n: Int) = n.toString().padStart(2, '0')
            return CheckedLabel(day, "${two(local.hour)}:${two(local.minute)}", "${two(local.dayOfMonth)}.${two(local.monthNumber)}")
        }
    }
}

enum class CheckedDay { TODAY, YESTERDAY, EARLIER }

/**
 * Статус участі. Запит не тримає місце: поки організатор не відповів, це «нічого».
 * [key] — як його називає сервер; невідоме значення читається як [NONE].
 */
enum class Membership(val key: String) {
    NONE("none"), REQUESTED("requested"), APPROVED("approved");

    companion object {
        fun fromKey(key: String?): Membership = entries.firstOrNull { it.key == key } ?: NONE
    }
}

/** Стан події, як його називає `events.status`. */
enum class EventStatus(val key: String) {
    PUBLISHED("published"), CANCELLED("cancelled"),
    /** Приховано модерацією (три скарги або рішення модератора): для клієнта — недоступна. */
    HIDDEN("hidden"),
    /** Сервер новіший за застосунок: ні опублікована, ні скасована — подія без дій. */
    UNKNOWN("");

    companion object {
        fun fromKey(key: String?): EventStatus = entries.firstOrNull { it != UNKNOWN && it.key == key } ?: UNKNOWN
    }
}

/** Звідки взявся рядок, як його називає `events.origin`. */
enum class EventOrigin(val key: String) {
    COMMUNITY("community"), IMPORT("import"), PARTNER("partner"),
    /** Сервер новіший за застосунок. Не спільнота — тож показуємо як афішу. */
    UNKNOWN("");

    companion object {
        fun fromKey(key: String?): EventOrigin = entries.firstOrNull { it != UNKNOWN && it.key == key } ?: UNKNOWN
    }
}

/** Чи ще жива імпортована подія, як її називає `events.import_status`. Невідоме — [LIVE]. */
enum class ImportStatus(val key: String) {
    LIVE("live"), STALE("stale"), WITHDRAWN("withdrawn");

    companion object {
        fun fromKey(key: String?): ImportStatus = entries.firstOrNull { it.key == key } ?: LIVE
    }
}

data class Attendee(val userId: String, val name: String, val avatarUrl: String?)

/** Хто кличе на подію за посиланням-запрошенням (docs/invites.md): перше слово імені й фото, без id людини. */
data class Inviter(val name: String, val avatarUrl: String?)
data class CityResult(val name: String, val latitude: Double, val longitude: Double)

/** Останнє обране місто на пристрої: наступний запуск одразу показує його, а не Київ за замовчуванням. */
interface CityStore {
    fun read(): CityResult?
    /** [manual] — людина обрала місто сама: геолокація на старті його не перебиває. */
    fun write(city: CityResult, manual: Boolean)
    fun manual(): Boolean
}
data class EventDraft(
    /** Null — ще не обрали. */
    val title: String, val description: String, val category: EventCategory?, val city: String,
    val address: String, val latitude: Double, val longitude: Double, val startsAt: String,
    val endsAt: String, val timeZone: String, val capacity: Int, val imageUrl: String? = null,
    val minAge: Int = SafetyRules.MIN_SIGNUP_AGE, val maxAge: Int? = null,
    /** Приєднання — запит організатору, а не відкриті двері. */
    val approvalRequired: Boolean = false,
    /** Чат учасників. Null — без чату. Формат перевіряє [ContactRules], вміст — ніхто. */
    val contactUrl: String? = null
) {
    fun validate(now: String): List<DraftField> = buildList {
        if (title.trim().length !in EventRules.titleLength) add(DraftField.TITLE)
        if (description.trim().length !in EventRules.descriptionLength) add(DraftField.DESCRIPTION)
        if (category == null || category == EventCategory.UNKNOWN) add(DraftField.CATEGORY)
        if (city.isBlank() || address.isBlank()) add(DraftField.ADDRESS)
        if (!latitude.isFinite() || !longitude.isFinite() || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) add(DraftField.LOCATION)
        if (capacity !in EventRules.capacity) add(DraftField.CAPACITY)
        val start = runCatching { Instant.parse(startsAt) }.getOrNull()
        val end = runCatching { Instant.parse(endsAt) }.getOrNull()
        val current = runCatching { Instant.parse(now) }.getOrNull()
        if (start == null || current == null || start <= current) add(DraftField.STARTS_AT)
        if (end == null || start == null || end <= start) add(DraftField.ENDS_AT)
        if (runCatching { TimeZone.of(timeZone) }.isFailure) add(DraftField.TIME_ZONE)
        if (imageUrl != null && !imageUrl.startsWith("https://")) add(DraftField.IMAGE_URL)
        if (!SafetyRules.isAgeLimit(minAge, maxAge)) add(DraftField.AGE_LIMITS)
        if (!ContactRules.isContactUrl(contactUrl)) add(DraftField.CONTACT_URL)
    }
}
