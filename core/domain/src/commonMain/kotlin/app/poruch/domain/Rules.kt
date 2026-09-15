package app.poruch.domain

import kotlinx.datetime.LocalDate

/** Ліміти подій. Сервер перевіряє ті самі: міграція рухає число — рухається й константа тут. */
object EventRules {
    /** Словник категорій. CHECK-обмеження на сервері тримає ті самі значення. */
    val categories = listOf(
        "music", "sport", "art", "food", "games", "outdoors", "social", "comedy", "kids",
        // Додані за звітом про прогалини: екскурсії тонули в «природі», конференції — у «зустрічах».
        "tours", "conference",
    )

    val titleLength = 3..120
    val descriptionLength = 10..5000
    val capacity = 1..10_000

    fun isCategory(value: String) = value in categories
}

/**
 * Правила безпеки. Копія клієнта дає зрозуміле повідомлення, копія в базі справді тримає
 * (патчений застосунок, повторений запит, сторонній клієнт).
 */
object SafetyRules {
    /** «Поруч» — платформа для дорослих. Знизити — рішення політики з модерацією на додачу. */
    const val MIN_SIGNUP_AGE = 18
    const val MAX_AGE_LIMIT = 120
    /** Дата народження далі — одруківка або жарт. */
    const val MAX_PLAUSIBLE_AGE = 120

    /** Організатор може звузити вік, але не нижче за мінімум платформи. */
    fun isAgeLimit(minAge: Int, maxAge: Int?) =
        minAge >= MIN_SIGNUP_AGE && minAge <= 100 && (maxAge == null || (maxAge in minAge..MAX_AGE_LIMIT))

    /** Повних років на [today]. Та сама арифметика, що `age()` у базі. */
    fun ageOn(birthDate: LocalDate, today: LocalDate): Int {
        val years = today.year - birthDate.year
        val hadBirthday = today.monthNumber > birthDate.monthNumber ||
            (today.monthNumber == birthDate.monthNumber && today.dayOfMonth >= birthDate.dayOfMonth)
        return if (hadBirthday) years else years - 1
    }

    fun isSignupAge(birthDate: LocalDate, today: LocalDate) =
        ageOn(birthDate, today).let { it >= MIN_SIGNUP_AGE && it <= MAX_PLAUSIBLE_AGE }
}

/** Причина скарги. Фіксований список, а не вільний текст, щоб чергу можна було сортувати. */
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

/** Ліміти полів акаунта, узгоджені з Supabase Auth. */
object AccountRules {
    val nameLength = 2..60
    const val MIN_PASSWORD = 8
    private val email = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

    fun isEmail(value: String) = email.matches(value.trim())
    fun isPassword(value: String) = value.length >= MIN_PASSWORD
    fun isName(value: String) = value.trim().length in nameLength
}

/** Що Storage приймає як обкладинку. Політика бакета перевіряє те саме. */
object ImageRules {
    const val MAX_BYTES = 5 * 1024 * 1024
    /** MIME → розширення. Типів поза списком не зберігаємо. */
    val extensions = mapOf("image/jpeg" to "jpg", "image/png" to "png", "image/webp" to "webp")
}

/** Темп і ліміти пошуку. Підібрані під руку на мапі, а не під сервер. */
object DiscoveryRules {
    /** Запобіжник на один запит, не стеля: на місті не спрацьовує, лише на «мапі до глобуса». */
    const val INDEX_CAP = 5000

    /** Скільки карток сервер кладе у відповідь одразу — перший екран каруселі без другого запиту. */
    const val FIRST_CARDS = 24

    /** Скільки карток домальовуємо наперед, коли стрічку прокрутили до кінця вікна. */
    const val CARD_WINDOW = 60

    /** Максимум карток за один запит до сервера. */
    const val CARD_BATCH = 100

    /** Скільки останніх відповідей тримає пристрій. Це не архів, а «мапі є що малювати, поки летить запит». */
    const val CACHE_ENTRIES = 12

    /** Вчорашня відповідь — ще план, тижнева — вже минуле. */
    const val CACHE_TTL_HOURS = 24

    /** Знаків після коми у межах області в ключі кеша: 3 ≈ 110 м. Сирі Double робили кожен рух мапи унікальним. */
    const val CACHE_KEY_PRECISION = 3

    const val SEARCH_TEXT_LIMIT = 120
    /** Довше за набір тексту, коротше за відчуття «мапа відстає». */
    const val SEARCH_DEBOUNCE_MS = 300L
    /** Геокодер сторонній, тож чекаємо довше, ніж на свій пошук. */
    const val CITY_DEBOUNCE_MS = 400L
    const val MIN_CITY_QUERY = 2
}

/** Де відкривається мапа, поки про людину нічого не відомо. Живе в [AppConfig], щоб інший регіон міняв значення, а не код. */
data class HomeLocation(
    val city: String,
    val latitude: Double,
    val longitude: Double,
    /** Пів висоти і пів ширини першого вікна мапи, у градусах. */
    val spanLatitude: Double = 0.15,
    val spanLongitude: Double = 0.25
) {
    val south get() = latitude - spanLatitude
    val north get() = latitude + spanLatitude
    val west get() = longitude - spanLongitude
    val east get() = longitude + spanLongitude

    companion object {
        val Kyiv = HomeLocation("Київ", 50.4501, 30.5234)

        /** Міста, де зараз є події. Шторка пропонує їх до першого набраного символу. Росте разом з покриттям імпорту. */
        val covered = listOf(
            Kyiv,
            HomeLocation("Харків", 49.9935, 36.2304),
            HomeLocation("Одеса", 46.4825, 30.7233),
            HomeLocation("Дніпро", 48.4647, 35.0462),
            HomeLocation("Львів", 49.8397, 24.0297)
        )
    }
}
