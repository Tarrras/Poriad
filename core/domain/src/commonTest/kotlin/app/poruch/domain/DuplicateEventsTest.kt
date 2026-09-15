package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlin.test.assertTrue

/** Усі пари — справжні рядки з бази (11.09.2026), включно з тими, які зливати не можна. */
class DuplicateEventsTest {

    private val venue = 50.4498664 to 30.5278357
    private val when1 = "2026-10-17T15:00:00Z"

    private fun entry(
        id: String, title: String, source: String? = "karabas",
        startsAt: String = when1, at: Pair<Double, Double> = venue,
        origin: String = EventOrigin.IMPORT
    ) = EventIndexEntry(
        id = id, latitude = at.first, longitude = at.second, category = "art",
        startsAt = startsAt, timeZone = "Europe/Kyiv", title = title,
        origin = origin, source = source,
        capacity = if (origin == EventOrigin.COMMUNITY) 10 else null
    )

    @Test
    fun `the same concert from two sellers becomes one card`() {
        val folded = DuplicateEvents.fold(
            listOf(
                entry("a", "Балет \"Баядерка\"", source = "ibilet"),
                entry("b", "Баядерка (ОНАТОБ)", source = "karabas")
            )
        )
        assertEquals(1, folded.size)
        // Представник — найменший id: стабільний ключ не смикає карусель між відповідями.
        assertEquals("a", folded.single().id)
        assertEquals(listOf("b"), folded.single().mergedWith)
        assertEquals(listOf("a", "b"), folded.single().representedIds)
    }

    @Test
    fun `titles reworded past recognition still merge`() {
        val pairs = listOf(
            "Star Wars. Symphony Orchestra" to "Star Wars. Симфонічний концерт",
            "Батя 2. Сольний стендап концерт Богдана Боярина" to "Богдан Боярин \"Батя 2\". Сольний стендап концерт",
            "Murder Mystery. Інтерактивне музичне шоу" to
                "Murder mystery. Загадкове вбивство. Інтерактивний детектив. Театралізоване музичне шоу для всієї родини. Dnipro Big Band",
            "Карміна Бурана (ДАТОБ)" to "Кантата «Карміна Бурана»",
            "Rico Sanchez та Брати Гадюкіни на фестивалі «Покоління»" to "Rico Sanchez на фестивалі Покоління у Львові"
        )
        for ((first, second) in pairs) {
            val folded = DuplicateEvents.fold(
                listOf(entry("a", first, source = "ibilet"), entry("b", second, source = "karabas"))
            )
            assertEquals(1, folded.size, "не склеїлось: «$first» / «$second»")
        }
    }

    @Test
    fun `two halls of one venue at one time are not a duplicate`() {
        // Одне джерело, дві події в один час — це два зали, а не дубль.
        val folded = DuplicateEvents.fold(
            listOf(
                entry("a", "Театр Квітки. Вистава \"Кодекс згоди\"", source = "ibilet"),
                entry("b", "Театр Ляльок. Вистава \"Імперія маст дай\". Прем'єра!", source = "ibilet")
            )
        )
        assertEquals(2, folded.size)
    }

    @Test
    fun `one source never merges with itself`() {
        // Навіть за однакових назв: одне джерело знає, що подій дві.
        val folded = DuplicateEvents.fold(
            listOf(entry("a", "ДахаБраха", source = "karabas"), entry("b", "ДахаБраха", source = "karabas"))
        )
        assertEquals(2, folded.size)
    }

    @Test
    fun `different plays at one venue and minute stay apart`() {
        val folded = DuplicateEvents.fold(
            listOf(
                entry("a", "Вистава \"Лісова пісня\"", source = "ibilet"),
                entry("b", "Дванадцята ніч, або Що захочете (ТЮГ Одеса)", source = "karabas")
            )
        )
        assertEquals(2, folded.size)
    }

    @Test
    fun `a community room is never merged away`() {
        // Кімнату спільноти не зливаємо ніколи.
        val folded = DuplicateEvents.fold(
            listOf(
                entry("a", "Баядерка", source = "ibilet"),
                entry("b", "Баядерка", source = null, origin = EventOrigin.COMMUNITY)
            )
        )
        assertEquals(2, folded.size)
    }

    @Test
    fun `venues three metres apart are two events`() {
        val folded = DuplicateEvents.fold(
            listOf(
                entry("a", "Баядерка", source = "ibilet"),
                entry("b", "Баядерка", source = "karabas", at = 50.4498665 to 30.5278047)
            )
        )
        assertEquals(2, folded.size)
    }

    @Test
    fun `twenty minutes apart is two events`() {
        val folded = DuplicateEvents.fold(
            listOf(
                entry("a", "Баядерка", source = "ibilet"),
                entry("b", "Баядерка", source = "karabas", startsAt = "2026-10-17T15:20:00Z")
            )
        )
        assertEquals(2, folded.size)
    }

    @Test
    fun `the same moment written two ways is one moment`() {
        val folded = DuplicateEvents.fold(
            listOf(
                entry("a", "Баядерка", source = "ibilet", startsAt = "2026-10-17T15:00:00Z"),
                entry("b", "Баядерка (ОНАТОБ)", source = "karabas", startsAt = "2026-10-17T18:00:00+03:00")
            )
        )
        assertEquals(1, folded.size)
    }

    @Test
    fun `an unreadable start time never merges`() {
        val folded = DuplicateEvents.fold(
            listOf(
                entry("a", "Баядерка", source = "ibilet", startsAt = "колись"),
                entry("b", "Баядерка", source = "karabas", startsAt = "колись")
            )
        )
        assertEquals(2, folded.size)
    }

    @Test
    fun `a list without duplicates comes back untouched`() {
        // Той самий об'єкт, а не рівний: платформи порівнюють списки за посиланням.
        val events = listOf(
            entry("a", "Баядерка", startsAt = "2026-10-17T15:00:00Z"),
            entry("b", "Дон Кіхот", startsAt = "2026-10-18T15:00:00Z")
        )
        assertSame(events, DuplicateEvents.fold(events))
        val alone = events.take(1)
        assertSame(alone, DuplicateEvents.fold(alone))
        assertTrue(DuplicateEvents.fold(emptyList()).isEmpty())
    }

    @Test
    fun `order survives the fold`() {
        val folded = DuplicateEvents.fold(
            listOf(
                entry("z", "Дон Кіхот", startsAt = "2026-10-16T15:00:00Z"),
                entry("a", "Балет \"Баядерка\"", source = "ibilet"),
                entry("b", "Баядерка (ОНАТОБ)", source = "karabas"),
                entry("y", "Мавка", startsAt = "2026-10-19T15:00:00Z")
            )
        )
        assertEquals(listOf("z", "a", "y"), folded.map { it.id })
    }
}
