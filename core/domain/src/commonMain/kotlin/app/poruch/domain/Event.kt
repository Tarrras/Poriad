package app.poruch.domain

import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant
import kotlinx.datetime.TimeZone

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
    val id: String, val title: String, val description: String, override val category: String,
    val city: String, val address: String,
    override val startsAt: String, val endsAt: String, override val timeZone: String, val status: String,
    val latitude: Double, val longitude: Double, val imageUrl: String? = null,
    /** Кімната: заповнена лише для події, яку створила людина. */
    val gathering: Gathering? = null,
    /** Оголошення: заповнене лише для імпорту та партнерських подій. */
    val listing: Listing? = null,
    /**
     * Усі сеанси прокату, якщо картка стоїть за кількома. Сервер цього поля не знає: його
     * заповнює спільний шар з [EventSeries], щоб екрани не шукали рядок в індексі на кожну промальовку.
     */
    val sessions: List<EventSession> = emptyList()
) : Rankable {
    override val isCancelled get() = status == EventStatus.CANCELLED || status == EventStatus.HIDDEN

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

    /** Організатор або джерело. Null — зіпсований рядок. */
    val publisherName get() = gathering?.organizerName?.takeIf { it.isNotBlank() } ?: listing?.sourceName

    /** Є лише в кімнати: блокувати й скаржитись можна тільки на людину. */
    val organizerId get() = gathering?.organizerId

    /** Заклад з `public.places`. Лише в афіші: у спільнотних подій місця нема. */
    val placeId get() = listing?.placeId
    val placeName get() = listing?.placeName?.takeIf { it.isNotBlank() }

    /** Підпис місця в картці: назва закладу, коли вона є, інакше адреса або місто. */
    val placeLabel: String get() = placeName ?: address.ifBlank { city }

    /**
     * Опис, який дозволено показати. Для афіші — лише початок: чужа анотація захищена авторським
     * правом (docs/event-ingestion.md §8), решту читають на сайті джерела. Обмеження правове,
     * тому живе в домені, а не в екранах.
     */
    val displayDescription: String
        get() = if (listing == null || description.length <= LISTING_DESCRIPTION_PREVIEW) description
        else description.take(LISTING_DESCRIPTION_PREVIEW).trimEnd().trimEnd(',', ';', '—', '-', '.') + "…"

    /** Опис обрізано, тож посилання «читати повністю» має сенс. */
    val descriptionTruncated get() = displayDescription.length < description.length

    // ---- Час. Рахуємо тут, щоб Android та iOS відповідали однаково.

    val startInstant: Instant? get() = runCatching { Instant.parse(startsAt) }.getOrNull()
    val endInstant: Instant? get() = runCatching { Instant.parse(endsAt) }.getOrNull()

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

    /** Ще не завершилась — показуємо у стрічках і планах. */
    fun isCurrent(now: Instant): Boolean = !hasEnded(now)

    companion object {
        /** Скільки символів чужого опису показуємо, перш ніж відіслати до джерела. */
        const val LISTING_DESCRIPTION_PREVIEW = 200

        /** Довше за добу — це вже не сеанс, а прокат. */
        private val RUN_FROM = 24.hours
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
    val membership: String = Membership.NONE,
    /** Приєднання — запит організатору, а не відкриті двері. */
    val approvalRequired: Boolean = false,
    /** Вікові межі гостей. Сервер відмовляє тим, хто поза діапазоном. */
    val minAge: Int = SafetyRules.MIN_SIGNUP_AGE,
    val maxAge: Int? = null,
    /**
     * Чат учасників (Telegram, Instagram тощо). Сервер віддає його лише організатору й
     * підтвердженим учасникам, решті — null. Куди веде — не перевіряємо, див. [ContactRules].
     */
    val contactUrl: String? = null
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
    val status: String = ImportStatus.LIVE,
    /** Id у `public.places`: одна точка на мапі, той самий ключ, що в [MapPins]. */
    val placeId: String? = null,
    /** Назва закладу («Малевич»), коротша й певніша за початок адреси. */
    val placeName: String? = null
) {
    /** Джерело зняло подію. Збережений запис лишається як позначка, не як план. */
    val isWithdrawn get() = status == ImportStatus.WITHDRAWN

    /** Є посилання на джерело — можна показувати кнопку. */
    val hasSource get() = !canonicalUrl.isNullOrBlank()
}

/** Статус участі. Запит не тримає місце: поки організатор не відповів, це «нічого». */
object Membership {
    const val NONE = "none"
    const val REQUESTED = "requested"
    const val APPROVED = "approved"
}

/** Стан події, як його називає `events.status`. */
object EventStatus {
    const val PUBLISHED = "published"
    const val CANCELLED = "cancelled"
    /** Приховано модерацією (три скарги або рішення модератора): для клієнта — недоступна. */
    const val HIDDEN = "hidden"
}

/** Звідки взявся рядок, як його називає `events.origin`. */
object EventOrigin {
    const val COMMUNITY = "community"
    const val IMPORT = "import"
    const val PARTNER = "partner"
}

/** Чи ще жива імпортована подія, як її називає `events.import_status`. */
object ImportStatus {
    const val LIVE = "live"
    const val STALE = "stale"
    const val WITHDRAWN = "withdrawn"
}

data class Attendee(val userId: String, val name: String, val avatarUrl: String?)
data class CityResult(val name: String, val latitude: Double, val longitude: Double)

/** Останнє обране місто на пристрої: наступний запуск одразу показує його, а не Київ за замовчуванням. */
interface CityStore {
    fun read(): CityResult?
    /** [manual] — людина обрала місто сама: геолокація на старті його не перебиває. */
    fun write(city: CityResult, manual: Boolean)
    fun manual(): Boolean
}
data class EventDraft(
    val title: String, val description: String, val category: String, val city: String,
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
        if (!EventRules.isCategory(category)) add(DraftField.CATEGORY)
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
