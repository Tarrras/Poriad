package app.poruch.domain

import kotlin.time.Instant

/**
 * Один концерт — одна картка, скільки б квиткових сервісів його не продавало.
 *
 * 150 подій із 1295 — це 75 пар, де той самий концерт стоїть у базі двічі: Internet-Bilet і
 * Concert.ua описують його різними словами. Це **друга сітка, а не перша**: звірку між джерелами
 * робить `drop_cross_source_duplicates` у конвеєрі (`tools/ingest/pipeline.py`), і корінь вади — у
 * тому, що її `same_event` цих пар не впізнав. Тут ми лише не даємо тому, що просочилось, дійти
 * до екрана: у стрічці дубль читається як помилка застосунку, бо нею і є.
 *
 * **Склеювання тут, а не в інжесті й не в SQL, — свідоме.** Міграція `20260907140000` показала,
 * чому: розбіжність між karabas і concert.ua дорівнювала UTC-зсуву, тобто дублікат **був звітом
 * про ваду**. Автозлиття на рівні даних сховало б її. Тут склеювання оборотне й видиме: у базі
 * лишаються обидва рядки, обидва можна зберегти, на обидва можна поскаржитись — просто на мапі
 * й у стрічці вони стоять однією карткою.
 */
object DuplicateEvents {

    /**
     * Наскільки схожими мають бути назви, щоб вважати їх однією подією.
     *
     * Поріг консервативний навмисно. Пропущене злиття лишає статус-кво — дві картки, як сьогодні.
     * Хибне злиття **ховає реальну подію**, і людина про неї не дізнається. Тому там, де сумнівно,
     * лишаємо дві.
     */
    const val TITLE_SIMILARITY = 0.55

    /**
     * Слова, які кажуть про жанр, а не про подію. Джерела ставлять їх по-різному: «Балет
     * "Баядерка"» проти «Баядерка (ОНАТОБ)» — це один спектакль і нуль спільних слів, доки
     * «балет» лишається в порівнянні.
     */
    private val GENRE = setOf(
        "вистава", "опера", "балет", "мюзикл", "концерт", "стендап", "шоу", "кантата",
        "сценічна", "музична", "музичне", "комедія", "комедійне", "гумористичне", "денна",
        "чарівна", "рок", "премєра", "премʼєра", "прем'єра", "трибют", "триб'ют", "трибʼют",
        "дитячий", "дитяча", "інтерактивний", "інтерактивна", "інтерактивне", "сольний",
        "неймовірне", "циркове", "фестиваль", "фестивалі"
    )

    /** Українська словозміна: «Богдана Боярина» і «Богдан Боярин» — одна людина. */
    private const val STEM = 5

    /**
     * Згортає дублікати у видачі. Порядок збережених подій не змінюється.
     *
     * Групуються лише кандидати, що стоять **на тій самій точці в ту саму хвилину**. Усе інше
     * проходить наскрізь тим самим об'єктом — це важливо для платформ, які порівнюють списки за
     * посиланням, щоб не перемальовувати мапу дарма.
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
     * Ключ кандидата: точка й хвилина початку.
     *
     * Порівнюється **момент**, а не рядок: `…T18:00:00+00:00` і `…T18:00:00Z` — це один час і два
     * різні рядки. Подія з нерозбірним часом ключа не має й не зливається ніколи.
     */
    private fun EventIndexEntry.key(): Key? {
        // Кімнату спільноти не зливаємо ніколи. Склеїти її означало б сховати подію, до якої можна
        // прийти, під чужим концертом — а дублікати бувають лише між квитковими сервісами.
        if (isCommunity) return null
        val minute = runCatching { Instant.parse(startsAt) }.getOrNull()?.epochSeconds?.div(60) ?: return null
        val place = MapPins.placeOf(this)
        return Key(place.latitude, place.longitude, minute)
    }

    private data class Key(val latitude: Long, val longitude: Long, val minute: Long)

    /**
     * Розбиває кандидатів однієї точки й хвилини на справжні групи.
     *
     * Два запобіжники, і обидва обов'язкові. Голого ключа «майданчик плюс хвилина» замало: з 75
     * таких груп **дев'ять одноджерельні** — це різні зали одного закладу в один час («Клуб
     * настільних ігор» і «Кіно-галерея», «Театр Квітки» і «Театр Ляльок»). Одне джерело, що
     * показує дві події в одному місці й часі, каже про два зали, а не про дубль.
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

    /**
     * Назва, зведена до того, що в ній є про саму подію.
     *
     * Знімаємо кінцеві дужки («(ОНАТОБ)», «(ДАТОБ)») — джерела ставлять туди абревіатуру театру, —
     * пунктуацію й лапки, жанрові слова, і обрізаємо кожен токен до [STEM] символів.
     */
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
     * Схожість двох назв: більше з Дайса й вкладеності.
     *
     * Сама вкладеність потрібна для пар, де одне джерело пише коротко, а друге переказує півафіші:
     * «Murder Mystery. Інтерактивне музичне шоу» проти «Murder mystery. Загадкове вбивство…
     * Dnipro Big Band». Дайс на такій парі дає 0.35 і пропустив би її, вкладеність — 0.75.
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
