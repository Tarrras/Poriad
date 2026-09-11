package app.poruch.domain

import kotlinx.datetime.LocalDate

/**
 * The numbers business logic used to spell out inline. They live here because the server enforces
 * the same limits: when a migration moves one, exactly one constant moves with it.
 */
object EventRules {
    /** The category vocabulary. The server's CHECK constraint holds the same nine values. */
    val categories = listOf("music", "sport", "art", "food", "games", "outdoors", "social", "comedy", "kids")

    val titleLength = 3..120
    val descriptionLength = 10..5000
    val capacity = 1..10_000

    fun isCategory(value: String) = value in categories
}

/**
 * The safety floor, in one place on the client to match the one in the database.
 *
 * Both exist on purpose and neither is redundant: the client's copy is what turns a wrong answer
 * into a sentence a person can read, and the server's copy is what actually holds — for a patched
 * app, a replayed request, or a caller who never used our app at all.
 */
object SafetyRules {
    /** «Поруч» is an adults' platform. Lowering this is a policy decision with moderation attached. */
    const val MIN_SIGNUP_AGE = 18
    const val MAX_AGE_LIMIT = 120
    /** Nobody is 150; a date past this is a typo or a joke, and both are rejected the same way. */
    const val MAX_PLAUSIBLE_AGE = 120

    /** An organizer may narrow the room, never widen it below what the platform admits. */
    fun isAgeLimit(minAge: Int, maxAge: Int?) =
        minAge >= MIN_SIGNUP_AGE && minAge <= 100 && (maxAge == null || (maxAge in minAge..MAX_AGE_LIMIT))

    /** Completed years on [today]; the same arithmetic the database does with `age()`. */
    fun ageOn(birthDate: LocalDate, today: LocalDate): Int {
        val years = today.year - birthDate.year
        val hadBirthday = today.monthNumber > birthDate.monthNumber ||
            (today.monthNumber == birthDate.monthNumber && today.dayOfMonth >= birthDate.dayOfMonth)
        return if (hadBirthday) years else years - 1
    }

    fun isSignupAge(birthDate: LocalDate, today: LocalDate) =
        ageOn(birthDate, today).let { it >= MIN_SIGNUP_AGE && it <= MAX_PLAUSIBLE_AGE }
}

/**
 * Why somebody is reporting. A named list rather than free text: a queue that can be sorted by
 * «this is about a minor» is the difference between a fast answer and a slow one.
 */
object ReportReason {
    const val MINORS = "minors"
    const val SAFETY = "safety"
    const val HARASSMENT = "harassment"
    const val SCAM = "scam"
    const val SPAM = "spam"
    const val OTHER = "other"

    val all = listOf(MINORS, SAFETY, HARASSMENT, SCAM, SPAM, OTHER)
    fun isReason(value: String) = value in all
}

/** Account input limits, matched to what Supabase Auth itself accepts. */
object AccountRules {
    val nameLength = 2..60
    const val MIN_PASSWORD = 8
    private val email = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

    fun isEmail(value: String) = email.matches(value.trim())
    fun isPassword(value: String) = value.length >= MIN_PASSWORD
    fun isName(value: String) = value.trim().length in nameLength
}

/** What Storage accepts for an event cover. The bucket policy enforces the same pair. */
object ImageRules {
    const val MAX_BYTES = 5 * 1024 * 1024
    /** MIME type to file extension; a type absent here is not an image we store. */
    val extensions = mapOf("image/jpeg" to "jpg", "image/png" to "png", "image/webp" to "webp")
}

/** Pacing and limits of search. Tuned for a hand on a map, not for the server. */
object DiscoveryRules {
    /**
     * Запобіжник на один запит, а не стеля видачі.
     *
     * Досі тут стояло 300, і це була саме стеля: у Києві 432 події, тож 132 з них не існувало для
     * застосунку взагалі. Відколи мапа питає тонкий індекс окремо від карток, повне місто коштує
     * 66 КБ і 14 мс — обмежувати нема чого. Число лишилось як межа на випадок, коли мапу віддалили
     * до глобуса: на місті воно не спрацьовує ніколи.
     */
    const val INDEX_CAP = 5000

    /** Скільки карток сервер кладе у відповідь одразу — перший екран каруселі без другого запиту. */
    const val FIRST_CARDS = 24

    /** Скільки карток застосунок домальовує наперед, коли стрічку прокрутили до кінця вікна. */
    const val CARD_WINDOW = 60

    /** Сервер не приймає більше за раз: більше однаково не поміщається на жодному екрані. */
    const val CARD_BATCH = 100

    /**
     * Скільки останніх відповідей тримає пристрій. Кеш тут — це «мапі є що малювати, поки летить
     * запит», а не архів: пʼять міст на кількох масштабах — це вже більше, ніж хтось обійде за раз.
     */
    const val CACHE_ENTRIES = 12

    /** Вчорашня відповідь — ще план. Тижнева — список того, що вже минуло. */
    const val CACHE_TTL_HOURS = 24

    /**
     * До скількох знаків округлюються межі області у ключі кеша.
     *
     * Три знаки — це ≈110 м. Менше не має сенсу: ключ із сирими `Double` (а `toString` дає сімнадцять
     * значущих цифр) робив кожен рух мапи унікальним, тож кеш писався й ніколи не читався.
     */
    const val CACHE_KEY_PRECISION = 3

    const val SEARCH_TEXT_LIMIT = 120
    /** Long enough to outlast typing, short enough to feel like the map is keeping up. */
    const val SEARCH_DEBOUNCE_MS = 300L
    /** Geocoding is a third-party call, so it waits longer than our own search. */
    const val CITY_DEBOUNCE_MS = 400L
    const val MIN_CITY_QUERY = 2
}

/**
 * Where the map opens before anything is known about the user. A default, not a constant —
 * [AppConfig] carries it so a build for another region changes one value, not the code.
 */
data class HomeLocation(
    val city: String,
    val latitude: Double,
    val longitude: Double,
    /** Half-height and half-width of the first viewport, in degrees. */
    val spanLatitude: Double = 0.15,
    val spanLongitude: Double = 0.25
) {
    val south get() = latitude - spanLatitude
    val north get() = latitude + spanLatitude
    val west get() = longitude - spanLongitude
    val east get() = longitude + spanLongitude

    companion object {
        val Kyiv = HomeLocation("Київ", 50.4501, 30.5234)

        /**
         * Міста, у яких зараз є події. Не довідник України, а список того, що людині є сенс
         * відкрити: до першого набраного символу шторка пропонує саме їх, бо геокодер на порожній
         * запит не відповідає нічим, а на «Lviv» — вокзалом, областю й аеропортом.
         *
         * Росте разом із покриттям імпорту; поки джерела обходять пʼять міст, тут пʼять.
         */
        val covered = listOf(
            Kyiv,
            HomeLocation("Харків", 49.9935, 36.2304),
            HomeLocation("Одеса", 46.4825, 30.7233),
            HomeLocation("Дніпро", 48.4647, 35.0462),
            HomeLocation("Львів", 49.8397, 24.0297)
        )
    }
}
