package app.poruch.domain

/** Що «Вставити анонс» заповнило: рядок «Заповнили з анонсу: …» і `announce_fill {filled}`. [key] — для аналітики. */
enum class AnnounceField(val key: String) {
    TITLE("title"), DESCRIPTION("description"), CATEGORY("category"), DATE("date"), PLACE("place"),
    CAPACITY("capacity"), AGE("min_age"), CONTACT("contact_url")
}

/** Чому анонс не розібрали: [LIMIT] — понад 20 на годину з адреси (429), [NETWORK] — нема звʼязку, [ERROR] — збій функції чи моделі. */
enum class AnnounceFailure(val key: String) { LIMIT("limit"), NETWORK("network"), ERROR("error") }

/**
 * Поля чернетки з тексту анонсу (`parse-announcement`, docs/organizers-1.5.md, 1.4). Null — у тексті нема, поле лишається
 * як було. Час — ISO-8601 в UTC, як у [EventDraft]. [address] — рядок для поля «Адреса»: крапку на мапі ставить людина,
 * з підказок адрес. [failure] — не розібрали: тоді є лише [title] (перший рядок) і [description] (увесь текст).
 */
data class AnnouncementFill(
    val title: String?,
    val description: String?,
    val category: EventCategory? = null,
    val startsAt: String? = null,
    val endsAt: String? = null,
    val address: String? = null,
    val capacity: Int? = null,
    val minAge: Int? = null,
    val contactUrl: String? = null,
    val failure: AnnounceFailure? = null
) {
    val filled: List<AnnounceField>
        get() = listOfNotNull(
            AnnounceField.TITLE.takeIf { title != null }, AnnounceField.DESCRIPTION.takeIf { description != null },
            AnnounceField.CATEGORY.takeIf { category != null }, AnnounceField.DATE.takeIf { startsAt != null },
            AnnounceField.PLACE.takeIf { address != null }, AnnounceField.CAPACITY.takeIf { capacity != null },
            AnnounceField.AGE.takeIf { minAge != null }, AnnounceField.CONTACT.takeIf { contactUrl != null }
        )
}

object AnnouncementRules {
    /** Стільки приймає функція; поле на платформі тримає ту саму межу. */
    const val TEXT_MAX = 3000

    /**
     * Анонс не розібрали: «Текст уже в описі — допишіть назву». Назва — перший рядок без емодзі, опис — текст без
     * хештегів наприкінці, як і в самій функції (`announce.ts`).
     */
    fun fallback(text: String, failure: AnnounceFailure): AnnouncementFill {
        val title = text.lineSequence().map(::plain).firstOrNull { it.isNotEmpty() }?.let(::clip)
        val description = text.trim().replace(TRAILING_TAGS, "").trim().takeIf { it.isNotEmpty() }
        return AnnouncementFill(title, description, failure = failure)
    }

    private val TRAILING_TAGS = Regex("""(\s*#[\p{L}\p{N}_]+)+$""")
    private val SPACES = Regex("""\s+""")

    /**
     * Без емодзі: поза базовою площиною (сурогатні пари), символи й дінгбати U+2600–27BF, стрілки й зірки U+2B00–2BFF,
     * селектори варіанта, ZWJ і рамка клавіші. ponytail: не повний `Extended_Pictographic`, решта лишиться в назві до правки.
     */
    private fun plain(line: String): String = buildString {
        line.forEach { c -> if (!c.isSurrogate() && c.code !in 0x2600..0x27BF && c.code !in 0x2B00..0x2BFF && c.code !in 0xFE00..0xFE0F && c.code != 0x200D && c.code != 0x20E3) append(c) }
    }.replace(SPACES, " ").trim()

    private fun clip(title: String): String {
        val max = EventRules.titleLength.last
        return if (title.length <= max) title else title.take(max - 1).trimEnd() + "…"
    }
}
