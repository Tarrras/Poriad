package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals

class TitleRulesTest {
    private fun display(title: String) = TitleRules.display(title)

    @Test fun shoutingBecomesTitleCase() {
        assertEquals("Стендап Перевірка", display("СТЕНДАП ПЕРЕВІРКА"))
        assertEquals("Іван Франко", display("ІВАН ФРАНКО"))
    }

    @Test fun smallWordsStayLowerInTheMiddleOnly() {
        assertEquals("Вечір у Театрі", display("ВЕЧІР У ТЕАТРІ"))
        // На початку й після знака — з великої.
        assertEquals("У Театрі", display("У ТЕАТРІ"))
        assertEquals("Концерт: У Пошуках Ритму", display("КОНЦЕРТ: У ПОШУКАХ РИТМУ"))
    }

    @Test fun latinAcronymsAndDigitsSurvive() {
        assertEquals("DJ SET", display("DJ SET"))
        assertEquals("Гурт Crazy Train", display("ГУРТ CRAZY TRAIN"))
        assertEquals("Концерт 2026", display("КОНЦЕРТ 2026"))
        assertEquals("Кіно 3D для Дітей", display("КІНО 3D ДЛЯ ДІТЕЙ"))
    }

    @Test fun shortAllCapsIsLeftAlone() {
        assertEquals("ДІМ", display("ДІМ"))
    }

    @Test fun mixedCaseIsNeverTouched() {
        assertEquals("Йдемо разом: Гурт Crazy Train (acoustic duet)", display("Йдемо разом: Гурт Crazy Train (acoustic duet)"))
        assertEquals("Вечір Імпровізації Паші Пінчука", display("Вечір Імпровізації Паші Пінчука"))
        assertEquals("СТЕНДАП (acoustic)", display("СТЕНДАП (acoustic)"))
    }

    @Test fun straightAndEnglishQuotesBecomeGuillemets() {
        assertEquals("Шоу «Не проблема»", display("Шоу \"Не проблема\""))
        assertEquals("Клуб «Бувальщина» у Modi", display("Клуб “Бувальщина” у Modi"))
        assertEquals("«Кринжові історії»", display("\"Кринжові історії\""))
        assertEquals("Шоу «Кринжові історії», Київ", display("Шоу \"Кринжові історії\", Київ"))
    }

    @Test fun inchMarkIsNotAQuote() {
        assertEquals("Екран 5\" у кіно", display("Екран 5\" у кіно"))
    }

    @Test fun apostropheInsideAWordIsTypographic() {
        assertEquals("П’ятниця, м’ясо, В’ячеслав", display("П'ятниця, м'ясо, В'ячеслав"))
        // Одинарні лапки навколо слова — не апостроф.
        assertEquals("Клуб 'Модi'", display("Клуб 'Модi'"))
    }

    @Test fun shoutingWithQuotesAndApostropheGetsAllThree() {
        assertEquals("Шоу «Не Проблема» П’ятниця", display("ШОУ \"НЕ ПРОБЛЕМА\" П'ЯТНИЦЯ"))
    }

    @Test fun eventExposesTheDisplayTitleAndKeepsTheOriginal() {
        val event = Event(
            id = "1", title = "СТЕНДАП \"ПЕРЕВІРКА\"", description = "", category = EventCategory.COMEDY, city = "Київ", address = "",
            startsAt = "2026-10-01T16:00:00Z", endsAt = "2026-10-01T18:00:00Z", timeZone = "Europe/Kyiv",
            status = EventStatus.PUBLISHED, latitude = 0.0, longitude = 0.0
        )
        assertEquals("Стендап «Перевірка»", event.displayTitle)
        assertEquals("СТЕНДАП \"ПЕРЕВІРКА\"", event.title)
    }
}
