package app.poruch.domain

import kotlin.time.Instant

/**
 * «Хочу піти з компанією» (docs/return-hooks.md, хвиля 1): рівень 1 — тизер без імен. [shared] — спільні зі мною
 * інтереси; гостю порожньо. Віку нема свідомо: хто ця людина, видно в її картці.
 */
data class CompanyTeaser(
    val count: Int,
    val shared: List<EventCategory>,
    /** Я сам маю намір на цю афішу. */
    val mine: Boolean
) {
    companion object {
        val Empty = CompanyTeaser(0, emptyList(), false)
    }
}

/**
 * Рівень 2: людина з наміром на ту саму афішу. Бачить лише той, хто сам має намір. [avatarUrl] і [instagram] сервер
 * віддає за правилом «бачиш те, що показуєш сам».
 */
data class CompanyPerson(
    val userId: String,
    /** Перше слово імені. */
    val name: String,
    val avatarUrl: String?,
    val bio: String?,
    val instagram: String?,
    val shared: List<EventCategory>,
    /** Скільки завершених подій людина відвідала. */
    val attended: Int,
    /** Я вже сказав «Піти разом». */
    val saidYes: Boolean,
    /** Мені вже сказали «Піти разом». */
    val theySaidYes: Boolean,
    /** Людина вже в живому супутнику цієї афіші — туди можна попроситися. */
    val companionId: String?
) {
    val asAttendee get() = Attendee(userId, name, avatarUrl)
}

/** Відповідь на «Піти разом»: збіг — супутник, куди сервер уже записав обох. */
data class CompanyMatch(val matched: Boolean, val companionId: String?)

/** Правила наміру. Сервер (`set_company_intent`, `set_instagram`) тримає ті самі. */
object CompanyRules {
    const val INSTAGRAM_MAX = 30
    private val HANDLE = Regex("^[a-z0-9._]{1,$INSTAGRAM_MAX}$")
    private val PROFILE_LINK = Regex("^(?:https?://)?(?:www\\.)?instagram\\.com/", RegexOption.IGNORE_CASE)

    /** Намір — на ту саму афішу, де можна зібрати супутник: ще не почалась і не знята. */
    fun canIntend(event: Event, now: Instant): Boolean = CompanionRules.canOffer(event, now)

    /**
     * «@Name», «instagram.com/name/?igsh=…», « name » → «name». Порожнє — прибрати. Що вийшло, перевіряє
     * [isValidInstagram]: нормалізація нічого не вигадує.
     */
    fun normalizeInstagram(raw: String): String =
        raw.trim().replace(PROFILE_LINK, "").substringBefore('?').trimEnd('/').removePrefix("@").lowercase()

    /** Порожнє теж годиться: це «прибрати». */
    fun isValidInstagram(handle: String): Boolean = handle.isEmpty() || HANDLE.matches(handle)
}
