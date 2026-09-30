package app.poruch.domain

/**
 * Назва події для показу. Джерела віддають її як зручно їм: КАПСОМ, з прямими лапками `"`, з `'` замість апострофа.
 * Дані не чіпаємо, лише вигляд ([Event.displayTitle]). Із засічками ці дрібниці помітні, тож правимо: капс — у «Кожне Слово З Великої»
 * (власні назви не губимо, як було б у реченні), лапки — «ялинки», апостроф усередині слова — ’.
 */
object TitleRules {
    /** Менше літер — це скоріше абревіатура («DJ», «ДІМ»), а не крик. */
    private const val SHOUT_MIN_LETTERS = 5

    /** Службові слова посеред фрази лишаються малими: «Вечір у Театрі», не «Вечір У Театрі». */
    private val SMALL_WORDS = setOf("і", "й", "та", "а", "але", "або", "чи", "в", "у", "на", "з", "зі", "із", "до", "від", "по", "за", "про", "при", "під", "над", "без", "для", "між", "через")

    fun display(title: String): String = apostrophes(quotes(if (isShouting(title)) capitalized(title) else title))

    /** Усі літери великі, і їх не менше за [SHOUT_MIN_LETTERS]. */
    private fun isShouting(title: String): Boolean {
        var letters = 0
        for (c in title) if (c.isLetter()) { if (c.isLowerCase()) return false; letters++ }
        return letters >= SHOUT_MIN_LETTERS
    }

    private fun isWordChar(c: Char) = c.isLetterOrDigit() || c == '\'' || c == '’' || c == 'ʼ' || c == '-'

    private fun capitalized(title: String): String {
        val out = StringBuilder(title.length)
        var i = 0
        while (i < title.length) {
            if (!isWordChar(title[i])) { out.append(title[i]); i++; continue }
            var j = i
            while (j < title.length && isWordChar(title[j])) j++
            out.append(caseWord(title.substring(i, j), midPhrase = isMidPhrase(title, i)))
            i = j
        }
        return out.toString()
    }

    /** Слово посеред фрази: перед ним пробіл, а до пробілу — літера чи цифра. Після «, :, — і на початку — ні. */
    private fun isMidPhrase(title: String, at: Int): Boolean {
        if (at == 0 || !title[at - 1].isWhitespace()) return false
        var k = at - 1
        while (k >= 0 && title[k].isWhitespace()) k--
        return k >= 0 && (title[k].isLetterOrDigit() || title[k] == '’' || title[k] == '\'')
    }

    private fun caseWord(word: String, midPhrase: Boolean): String {
        // «3D», «2026», «1-й»: цифри мають свій вигляд. «DJ», «VR»: латинська абревіатура до трьох літер.
        if (word.any { it.isDigit() } || (word.length <= 3 && word.all { it in 'A'..'Z' || it == '-' })) return word
        val lower = word.lowercase()
        return if (midPhrase && lower in SMALL_WORDS) lower else lower.replaceFirstChar { it.uppercase() }
    }

    /** Прямі й англійські лапки — «ялинки». Відкриває лапка на початку, після пробілу чи розділового знака. */
    private fun quotes(title: String): String {
        if (title.none { it == '"' || it == '“' || it == '”' || it == '„' }) return title
        val out = StringBuilder(title.length)
        for ((i, c) in title.withIndex()) {
            val before = if (i == 0) ' ' else title[i - 1]
            out.append(
                when (c) {
                    '“', '„' -> '«'
                    '”' -> '»'
                    // 5" — дюйм, а не лапка.
                    '"' -> if (before.isDigit()) c else if (before.isWhitespace() || before in "([—–-:«") '«' else '»'
                    else -> c
                }
            )
        }
        return out.toString()
    }

    /** Знаки, якими джерела пишуть апостроф: прямий, зворотний (`Прем`єра`), акут, лівий одинарний. */
    private const val APOSTROPHE_LIKE = "'`´‘"

    /** `п'ятниця`, `Прем`єра` → `п’ятниця`, `Прем’єра`: такий знак між двома літерами. Одинарні лапки навколо слова лишаються. */
    private fun apostrophes(title: String): String {
        if (title.none { it in APOSTROPHE_LIKE }) return title
        val out = StringBuilder(title.length)
        for ((i, c) in title.withIndex()) {
            val inWord = c in APOSTROPHE_LIKE && i > 0 && i < title.lastIndex && title[i - 1].isLetter() && title[i + 1].isLetter()
            out.append(if (inWord) '’' else c)
        }
        return out.toString()
    }
}
