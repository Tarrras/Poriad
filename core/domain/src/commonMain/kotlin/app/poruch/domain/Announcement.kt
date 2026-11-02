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

    /**
     * Текст без того, чого людина не бачить, але прочитає модель чи покаже опис: керівних символів (крім переносу й
     * табуляції), форматних і ігнорованих (теги U+E0000 «ASCII smuggling», нульова ширина, bidi, BOM, селектори
     * варіанта, порожні літери; крім ZWJ і FE0F в емодзі), приватних, непарних сурогатів і порожнього Брайля. Те саме,
     * що `clean` у `supabase/functions/parse-announcement/announce.ts` (там — `\p{DI}`, тут — його діапазони): функція
     * чистить і сама, а тут — щоб і запасний опис був чистий.
     */
    fun clean(text: String): String = buildString {
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (c.isHighSurrogate() && i + 1 < text.length && text[i + 1].isLowSurrogate()) {
                val code = 0x10000 + ((c.code - 0xD800) shl 10) + (text[i + 1].code - 0xDC00)
                if (HIDDEN_ABOVE.none { code in it }) append(c).append(text[i + 1])
                i += 2
                continue
            }
            if (c == '\r') {
                if (text.getOrNull(i + 1) != '\n') append('\n')
            } else if (c == '\n' || c == '\t' || c == '\u200D' || c == '\uFE0F' || c.isVisible()) append(c)
            i++
        }
    }

    private fun Char.isVisible() = !isSurrogate() && category != CharCategory.CONTROL && category != CharCategory.FORMAT &&
        category != CharCategory.PRIVATE_USE && HIDDEN.none { code in it }

    /** Ігноровані й порожні в базовій площині, яких нема серед форматних: CGJ, порожні літери, монгольські селектори… */
    private val HIDDEN = listOf(
        0x034F..0x034F, 0x115F..0x1160, 0x17B4..0x17B5, 0x180B..0x180F, 0x2065..0x2065, 0x2800..0x2800,
        0x3164..0x3164, 0xFE00..0xFE0E, 0xFFA0..0xFFA0, 0xFFF0..0xFFF8
    )

    /** Поза базовою площиною: форматні (Кайтхі, ієрогліфи, стенографія, музичні), теги й селектори, приватні площини. */
    private val HIDDEN_ABOVE = listOf(
        0x110BD..0x110BD, 0x110CD..0x110CD, 0x13430..0x1343F, 0x1BCA0..0x1BCA3, 0x1D173..0x1D17A, 0xE0000..0xE0FFF,
        0xF0000..0x10FFFF
    )

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
