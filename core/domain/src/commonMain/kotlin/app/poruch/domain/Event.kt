package app.poruch.domain

import kotlin.time.Instant
import kotlinx.datetime.TimeZone

/**
 * Immutable UI-independent event model. Timestamps are ISO-8601 UTC instants.
 *
 * Подія має дві природи, і плутати їх коштувало дорого.
 *
 * **Кімната** ([Gathering]) — це те, що створила людина: місткість, черга, підтвердження,
 * організатор, який за неї відповідає. **Оголошення** ([Listing]) — це афіша з відкритого джерела:
 * назва джерела, ціна, посилання на квиток. Спільного в них рівно стільки, скільки потрібно, щоб
 * стояти на одній мапі: що, коли й де.
 *
 * Тому поля участі живуть не тут, а в [gathering]. Це не косметика: поки `capacity` було полем
 * події, кожна картка мала право показати «Лишилось 1 місце» під чужим концертом, і показувала.
 * Тепер до місць не дістатися, не спитавши спершу, чи є взагалі кімната, — і компілятор питає це
 * замість рев'ю.
 *
 * Рівно одна з двох граней заповнена; яка саме — вирішує `events.origin` на сервері, а не клієнт.
 * Обидві порожні — це зіпсований рядок, і екрани мають пережити його як подію без дій, а не впасти.
 */
data class Event(
    val id: String, val title: String, val description: String, override val category: String,
    val city: String, val address: String,
    override val startsAt: String, val endsAt: String, override val timeZone: String, val status: String,
    val latitude: Double, val longitude: Double, val imageUrl: String? = null,
    /** Кімната: заповнена лише для події, яку створила людина. */
    val gathering: Gathering? = null,
    /** Оголошення: заповнене лише для імпорту та партнерських подій. */
    val listing: Listing? = null
) : Rankable {
    override val isCancelled get() = status == EventStatus.CANCELLED

    // ---- те, за чим ранжують --------------------------------------------------------------
    // Обидва питання адресовані кімнаті, тож обидва відповідають «ні» там, де її немає.
    override val roomCapacity get() = gathering?.capacity
    override val roomHasSeats get() = gathering?.isFull == false
    val isPublished get() = status == EventStatus.PUBLISHED

    /** Подія, до якої можна прийти, а не лише подивитись. */
    val isCommunity get() = gathering != null

    /** Хто це опублікував — жива людина чи джерело. Null означає зіпсований рядок. */
    val publisherName get() = gathering?.organizerName?.takeIf { it.isNotBlank() } ?: listing?.sourceName

    /** Є кого блокувати й на кого скаржитись лише там, де є людина. */
    val organizerId get() = gathering?.organizerId

    /**
     * Опис, який дозволено показати. Для афіші — тільки початок: факти про подію не охороняються
     * авторським правом, а текст чужої анотації охороняється (docs/event-ingestion.md §8), тож
     * решту читають за посиланням на джерелі. Обмеження правове, а не верстальне, і саме тому
     * стоїть у домені — інакше наступний екран покаже повний текст і матиме рацію.
     */
    val displayDescription: String
        get() = if (listing == null || description.length <= LISTING_DESCRIPTION_PREVIEW) description
        else description.take(LISTING_DESCRIPTION_PREVIEW).trimEnd().trimEnd(',', ';', '—', '-', '.') + "…"

    /** True коли опис обрізано і посилання «читати повністю» справді щось додає. */
    val descriptionTruncated get() = displayDescription.length < description.length

    // ---- коли подія відбувається -------------------------------------------------------------
    // Розбір тут, а не в кожному клієнті: «актуальність» — це доменне питання, і відповідь на нього
    // має бути одна на Android та iOS.

    val startInstant: Instant? get() = runCatching { Instant.parse(startsAt) }.getOrNull()
    val endInstant: Instant? get() = runCatching { Instant.parse(endsAt) }.getOrNull()

    /** Ще не почалася. Нерозбірний час вважаємо майбутнім: краще показати зайве, ніж сховати живе. */
    fun isUpcoming(now: Instant): Boolean = startInstant?.let { it > now } ?: true

    /** Почалася, але ще триває. Така подія найактуальніша з усіх, і ховати її було б дивно. */
    fun isUnderway(now: Instant): Boolean {
        val start = startInstant ?: return false
        val end = endInstant ?: return false
        return start <= now && end > now
    }

    /** Завершилася. Єдиний стан, у якому подію не варто пропонувати. */
    fun hasEnded(now: Instant): Boolean = endInstant?.let { it <= now } ?: false

    /** Показуємо у стрічках і планах: усе, що ще не завершилось. */
    fun isCurrent(now: Instant): Boolean = !hasEnded(now)

    companion object {
        /** Скільки чужого опису показуємо своїм шрифтом, перш ніж відіслати до джерела. */
        const val LISTING_DESCRIPTION_PREVIEW = 200
    }
}

/**
 * Кімната: усе, що робить подію такою, до якої приходять.
 *
 * Місткість тут не для краси структури — вона тут тому, що поза кімнатою її не існує. Сервер каже
 * те саме: `events.capacity` обов'язковий лише при `origin = 'community'`.
 */
data class Gathering(
    val organizerId: String,
    /** Blank when the organizer has no public profile yet; naming the fallback is the UI's job. */
    val organizerName: String,
    val capacity: Int,
    val attendeeCount: Int,
    val joined: Boolean,
    /** This account's standing at this event: none, asked to come, or in. */
    val membership: String = Membership.NONE,
    /** When set, joining is a request the organizer answers rather than an open door. */
    val approvalRequired: Boolean = false,
    /** Who the organizer is willing to host. The server refuses anyone outside the range. */
    val minAge: Int = SafetyRules.MIN_SIGNUP_AGE,
    val maxAge: Int? = null
) {
    val seatsLeft get() = (capacity - attendeeCount).coerceAtLeast(0)
    val isFull get() = seatsLeft == 0
    val awaitingApproval get() = membership == Membership.REQUESTED

    /** True when the organizer set anything narrower than «anyone on the platform». */
    val hasAgeLimit get() = minAge > SafetyRules.MIN_SIGNUP_AGE || maxAge != null

    /**
     * Місць лишилось так мало, що це варте окремого рядка. Поріг живе тут, а не в кожному
     * клієнті: до цієї правки Android і iOS рахували «мало» двома копіями однієї формули.
     */
    val isScarce get() = seatsLeft in 1..(capacity / SCARCITY_FRACTION).coerceAtLeast(MIN_SCARCE_SEATS)

    companion object {
        /** A fifth of the room left reads as "hurry"; below three seats it always does. */
        private const val SCARCITY_FRACTION = 5
        private const val MIN_SCARCE_SEATS = 3
    }
}

/**
 * Оголошення: подія, яку ми не проводимо, а лише показуємо.
 *
 * [sourceName] обов'язкове, бо атрибуція обов'язкова (docs/event-ingestion.md §8) — це умова, на
 * якій ми взагалі маємо право показувати ці рядки, а не оздоблення картки.
 */
data class Listing(
    val sourceName: String,
    /** Сторінка джерела: єдине місце, де подію можна купити й дочитати. */
    val canonicalUrl: String? = null,
    /** Найдешевший квиток у гривнях; null означає «джерело не сказало», а не «безкоштовно». */
    val priceMin: Double? = null,
    val isFree: Boolean? = null,
    val status: String = ImportStatus.LIVE
) {
    /** Джерело більше не показує цю подію. Збережений запис лишається — але як позначка, не як план. */
    val isWithdrawn get() = status == ImportStatus.WITHDRAWN

    /** Є куди вести. Кнопка без адреси гірша за відсутність кнопки. */
    val hasSource get() = !canonicalUrl.isNullOrBlank()
}

/**
 * A membership row has a state, because an event may be joined by request. A request holds no
 * seat: it is a question put to the organizer, and until they answer it counts as nothing.
 */
object Membership {
    const val NONE = "none"
    const val REQUESTED = "requested"
    const val APPROVED = "approved"
}

/** Event lifecycle, as the `events.status` column spells it. */
object EventStatus {
    const val PUBLISHED = "published"
    const val CANCELLED = "cancelled"
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
data class EventDraft(
    val title: String, val description: String, val category: String, val city: String,
    val address: String, val latitude: Double, val longitude: Double, val startsAt: String,
    val endsAt: String, val timeZone: String, val capacity: Int, val imageUrl: String? = null,
    val minAge: Int = SafetyRules.MIN_SIGNUP_AGE, val maxAge: Int? = null,
    /** When set, joining is a request the organizer answers rather than an open door. */
    val approvalRequired: Boolean = false
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
    }
}
