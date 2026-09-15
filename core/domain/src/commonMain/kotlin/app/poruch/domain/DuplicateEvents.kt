package app.poruch.domain

import kotlin.time.Instant

/**
 * Один концерт — одна картка, скільки б квиткових сервісів його не продавало.
 *
 * Це друга сітка після `drop_cross_source_duplicates` у `tools/ingest/pipeline.py`: тут ловимо
 * те, що просочилось. Склеюємо на клієнті, а не в даних, свідомо: дублікат у базі не раз
 * виявлявся звітом про ваду (див. міграцію `20260907140000`). Обидва рядки лишаються, їх
 * можна зберегти й поскаржитись, просто на мапі й у стрічці вони стоять однією карткою.
 */
object DuplicateEvents {

    /**
     * Мінімальна схожість назв для злиття. Поріг навмисно консервативний: пропущене злиття —
     * дві картки, хибне — схована реальна подія.
     */
    const val TITLE_SIMILARITY = 0.55

    /** Жанрові слова, які джерела ставлять по-різному: «Балет "Баядерка"» і «Баядерка (ОНАТОБ)». */
    private val GENRE = setOf(
        "вистава", "опера", "балет", "мюзикл", "концерт", "стендап", "шоу", "кантата",
        "сценічна", "музична", "музичне", "комедія", "комедійне", "гумористичне", "денна",
        "чарівна", "рок", "премєра", "премʼєра", "прем'єра", "трибют", "триб'ют", "трибʼют",
        "дитячий", "дитяча", "інтерактивний", "інтерактивна", "інтерактивне", "сольний",
        "неймовірне", "циркове", "фестиваль", "фестивалі"
    )

    /** Довжина основи слова: «Богдана Боярина» і «Богдан Боярин» — одна людина. */
    private const val STEM = 5

    /**
     * Згортає дублікати, зберігаючи порядок. Кандидати — лише події на тій самій точці в ту
     * саму хвилину. Решта проходить тим самим об'єктом, щоб платформи не перемальовували мапу дарма.
     */
    fun fold(events: List<EventIndexEntry>): List<EventIndexEntry> {
        if (events.size < 2) return events
        val groups = LinkedHashMap<Key, MutableList<EventIndexEntry>>()
        for (event in events) {
            val key = event.key() ?: continue
            groups.getOrPut(key) { mutableListOf() } += event
        }
        if (groups.values.none { it.size > 1 }) return events

        val merged = HashMap<String, EventIndexEntry>()
        val absorbed = HashSet<String>()
        for (bucket in groups.values) {
            if (bucket.size == 1) continue
            for (cluster in bucket.cluster()) {
                if (cluster.size == 1) continue
                val primary = cluster.minBy { it.id }
                merged[primary.id] = primary.copy(mergedWith = cluster.map { it.id }.filter { it != primary.id })
                cluster.forEach { if (it.id != primary.id) absorbed += it.id }
            }
        }
        if (merged.isEmpty() && absorbed.isEmpty()) return events
        return events.mapNotNull { event ->
            when {
                event.id in absorbed -> null
                else -> merged[event.id] ?: event
            }
        }
    }

    /**
     * Ключ кандидата: точка й хвилина початку. Порівнюємо момент, а не рядок, бо `+00:00` і `Z` —
     * один час. Нерозбірний час — без ключа, не зливається.
     */
    private fun EventIndexEntry.key(): Key? {
        // Кімнату спільноти не зливаємо: дублікати бувають лише між квитковими сервісами.
        if (isCommunity) return null
        val minute = runCatching { Instant.parse(startsAt) }.getOrNull()?.epochSeconds?.div(60) ?: return null
        val place = MapPins.placeOf(this)
        return Key(place.latitude, place.longitude, minute)
    }

    private data class Key(val latitude: Long, val longitude: Long, val minute: Long)

    /**
     * Розбиває кандидатів однієї точки й хвилини на групи за схожістю назв. Події одного
     * джерела не зливаємо: це різні зали одного закладу, а не дубль.
     */
    private fun List<EventIndexEntry>.cluster(): List<List<EventIndexEntry>> {
        val ordered = sortedBy { it.id }
        val tokens = ordered.map { it.title.tokens() }
        val clusters = mutableListOf<MutableList<Int>>()
        for (index in ordered.indices) {
            val joined = clusters.firstOrNull { cluster ->
                cluster.any { other ->
                    ordered[other].source != ordered[index].source &&
                        similarity(tokens[other], tokens[index]) >= TITLE_SIMILARITY
                }
            }
            if (joined == null) clusters += mutableListOf(index) else joined += index
        }
        return clusters.map { cluster -> cluster.map { ordered[it] } }
    }

    /** Токени назви: без дужок з абревіатурою театру, пунктуації, жанрових слів; основа до [STEM] символів. */
    internal fun String.tokens(): Set<String> = lowercase()
        .replace(PARENTHETICAL, " ")
        .map { if (it.isLetterOrDigit()) it else ' ' }
        .joinToString("")
        .split(' ')
        .filter { it.length > 2 && it !in GENRE }
        .map { it.take(STEM) }
        .toSet()

    private val PARENTHETICAL = Regex("\\([^)]*\\)")

    /**
     * Схожість назв: максимум із коефіцієнта Дайса і вкладеності. Вкладеність ловить пари, де
     * одне джерело пише коротко, а друге переказує півафіші.
     */
    internal fun similarity(a: Set<String>, b: Set<String>): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        val shared = a.count { it in b }
        if (shared == 0) return 0.0
        val dice = 2.0 * shared / (a.size + b.size)
        val containment = shared.toDouble() / minOf(a.size, b.size)
        return maxOf(dice, containment)
    }
}
