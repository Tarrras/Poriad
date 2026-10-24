package app.poruch.domain

/**
 * Район міста з `public.districts`: межі адміністративного району з OpenStreetMap. Пошук «Київський» в Одесі звужує
 * мапу, список і лічильники до району точкою в полігоні над індексом видачі, як категорія: без запиту до сервера.
 * Назви повторюються між містами (Київський є і в Одесі, і в Харкові), тож район завжди шукають у своєму місті.
 *
 * Рівність — за [id], id відношення в OSM: межі не порівнюємо.
 */
class District(
    val id: Long,
    val city: String,
    /** «Київський район». */
    val name: String,
    /** Назва до нещодавнього перейменування: рядок пошуку нагадує «раніше Малиновський». Null — не перейменовували. */
    val formerName: String? = null,
    /** Лише для пошуку, не показуємо: назви до 2016 року і звичні («Оболонь»). */
    val aliases: List<String> = emptyList(),
    /**
     * Кільця межі, кожне — `lon, lat, lon, lat…`, перша точка повторена в кінці. Зовнішні кільця й дірки разом:
     * [contains] рахує парність перетинів, тож ні порядок, ні напрям не важать.
     */
    val rings: List<DoubleArray>
) {
    val south: Double
    val west: Double
    val north: Double
    val east: Double

    init {
        var s = 90.0; var w = 180.0; var n = -90.0; var e = -180.0
        for (ring in rings) for (i in ring.indices step 2) {
            w = minOf(w, ring[i]); e = maxOf(e, ring[i])
            s = minOf(s, ring[i + 1]); n = maxOf(n, ring[i + 1])
        }
        south = s; west = w; north = n; east = e
    }

    /** Слова кожної назви — назви, колишньої й псевдонімів — кирилицею й латиницею. */
    private val terms: List<List<String>> by lazy {
        (listOf(name) + listOfNotNull(formerName) + aliases).map { words(it).let { cyrillic -> cyrillic + cyrillic.map(::latin) } }
    }

    /** Точка всередині меж. Промінь на схід: непарна кількість перетинів — всередині. Межа на ~10 м спрощена. */
    fun contains(latitude: Double, longitude: Double): Boolean {
        if (latitude !in south..north || longitude !in west..east) return false
        var inside = false
        for (ring in rings) {
            var j = ring.size - 2
            for (i in ring.indices step 2) {
                val x1 = ring[i]; val y1 = ring[i + 1]
                val x2 = ring[j]; val y2 = ring[j + 1]
                if ((y1 > latitude) != (y2 > latitude) && longitude < (x2 - x1) * (latitude - y1) / (y2 - y1) + x1) inside = !inside
                j = i
            }
        }
        return inside
    }

    /**
     * Чи цей район людина шукає [query]: кожне слово запиту — початок якогось слова однієї з назв («київ», «київський р-н»,
     * «нижньодніпр»), кирилицею чи латиницею («kyivsk»). Початок слова, а не підрядок: «ський» інакше знайшов би всі.
     */
    fun matches(query: String): Boolean {
        val asked = words(query)
        if (asked.sumOf { it.length } < MIN_QUERY) return false
        return terms.any { term -> asked.all { word -> term.any { it.startsWith(word) } } }
    }

    override fun equals(other: Any?) = other is District && other.id == id
    override fun hashCode() = id.hashCode()
    override fun toString() = "District($id, $city, $name)"

    companion object {
        /** Менше літер не шукаємо: одна літера дала б пів міста. */
        const val MIN_QUERY = 2

        private const val APOSTROPHES = "'’ʼ`‘"

        /** Слова в нижньому регістрі. Апострофи всіх видів — один, і лише всередині слова; «р-н» — «район». */
        private fun words(text: String): List<String> = buildList {
            val word = StringBuilder()
            for (c in text.lowercase() + ' ') when {
                // Спершу апостроф: «ʼ» (U+02BC) для isLetterOrDigit — літера.
                c in APOSTROPHES -> if (word.isNotEmpty()) word.append('\'')
                c.isLetterOrDigit() -> word.append(c)
                word.isNotEmpty() -> {
                    // Словами, а не в рядку: заміна в рядку з'їла б «Амур-Нижньодніпровський».
                    if (word.toString() == "н" && lastOrNull() == "р") set(lastIndex, "район") else add(word.toString())
                    word.clear()
                }
            }
        }

        /**
         * Кирилиця → латиниця тією самою таблицею, що `private.search_translit` на сервері: «Київський» знаходиться
         * як «kyivskyi». Лише в цей бік: латиниця → кирилиця втрачає («kyiv» → «кийв»), а назви районів — кирилицею.
         */
        internal fun latin(text: String): String = buildString { for (c in text) append(LATIN[c] ?: c) }

        private val LATIN: Map<Char, String> = buildMap {
            "абвгґдезиіїйклмнопрстуфыэё".zip("abvhgdezyiiiklmnoprstufyee").forEach { (from, to) -> put(from, to.toString()) }
            putAll(mapOf('щ' to "shch", 'ж' to "zh", 'х' to "kh", 'ц' to "ts", 'ч' to "ch", 'ш' to "sh", 'є' to "ie", 'ю' to "iu", 'я' to "ia"))
            "ьъ$APOSTROPHES".forEach { put(it, "") }
        }
    }
}
