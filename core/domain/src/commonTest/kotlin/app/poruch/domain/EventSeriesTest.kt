package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Прокат збирається в одну картку, жоден сеанс не зникає. Найдорожча помилка — зліпити дві
 * різні вистави одного театру, тому половина перевірок про те, що НЕ збирається.
 */
class EventSeriesTest {

    private fun entry(
        id: String,
        title: String,
        startsAt: String,
        lat: Double = 50.45,
        lon: Double = 30.53,
        origin: String = EventOrigin.IMPORT,
        source: String? = "karabas",
    ) = EventIndexEntry(
        id = id, latitude = lat, longitude = lon, category = "art",
        startsAt = startsAt, timeZone = "Europe/Kyiv", title = title,
        origin = origin, source = source,
    )

    @Test
    fun `sessions of one run collapse into the nearest date`() {
        val folded = EventSeries.fold(
            listOf(
                entry("b", "Лускунчик", "2026-12-23T18:00:00Z"),
                entry("a", "Лускунчик", "2026-12-22T18:00:00Z"),
                entry("c", "Лускунчик", "2026-12-30T18:00:00Z"),
            )
        )
        assertEquals(1, folded.size, "прокат — одна картка")
        assertEquals("a", folded[0].id, "показуємо найближчий сеанс, а не перший у списку")
        assertEquals(listOf("a", "b", "c"), folded[0].sessions.map { it.id }, "сеанси в порядку часу")
        assertEquals(3, folded[0].sessionCount)
        assertTrue(folded[0].isSeries)
    }

    @Test
    fun `two showings on one day are a run too`() {
        val folded = EventSeries.fold(
            listOf(
                entry("m", "Дизель Шоу", "2026-10-27T13:30:00Z"),
                entry("e", "Дизель Шоу", "2026-10-27T16:30:00Z"),
            )
        )
        assertEquals(1, folded.size)
        assertEquals(listOf("m", "e"), folded[0].sessions.map { it.id })
    }

    @Test
    fun `different plays at the same venue stay apart`() {
        val events = listOf(
            entry("a", "Лускунчик", "2026-12-22T18:00:00Z"),
            entry("b", "Лебедине озеро", "2026-12-23T18:00:00Z"),
        )
        assertEquals(2, EventSeries.fold(events).size)
    }

    @Test
    fun `different programmes sharing a series name stay apart`() {
        // Вкладеність назв дала б цій парі одиницю, а це різні концерти. Тому порога схожості нема.
        val events = listOf(
            entry("a", "The ROCK SYMPHONY Orchestra. 8 солістів", "2026-10-09T18:00:00Z"),
            entry("b", "The ROCK SYMPHONY Orchestra. Нова Програма", "2026-10-11T18:00:00Z"),
        )
        assertEquals(2, EventSeries.fold(events).size)
    }

    @Test
    fun `acts of one festival stay apart`() {
        // Спільні слова — назва майданчика, а не події: на «Feels Garden Beer #9» різні гурти.
        val events = listOf(
            entry("a", "O.Torvald на Feels Garden Beer #9", "2026-09-20T17:00:00Z"),
            entry("b", "Epolets на Feels Garden Beer #9", "2026-09-21T17:00:00Z"),
            entry("c", "Feels Garden Beer #9", "2026-09-22T17:00:00Z"),
        )
        assertEquals(3, EventSeries.fold(events).size)
    }

    @Test
    fun `genre words and theatre abbreviations do not break a run`() {
        // Зведення назви спільне з DuplicateEvents: жанр і дужки знімаються.
        val folded = EventSeries.fold(
            listOf(
                entry("a", "Балет \"Баядерка\"", "2026-10-01T18:00:00Z"),
                entry("b", "Баядерка (ОНАТОБ)", "2026-10-08T18:00:00Z"),
            )
        )
        assertEquals(1, folded.size)
        assertEquals(2, folded[0].sessionCount)
    }

    @Test
    fun `same play at different venues stays apart`() {
        val events = listOf(
            entry("a", "Лускунчик", "2026-12-22T18:00:00Z"),
            entry("b", "Лускунчик", "2026-12-23T18:00:00Z", lat = 49.84, lon = 24.03),
        )
        assertEquals(2, EventSeries.fold(events).size, "два міста — два прокати")
    }

    @Test
    fun `community rooms are never collapsed`() {
        // Дві зустрічі спільноти на різні дні — не прокат.
        val events = listOf(
            entry("a", "Йога в парку", "2026-10-01T07:00:00Z", origin = EventOrigin.COMMUNITY, source = null),
            entry("b", "Йога в парку", "2026-10-08T07:00:00Z", origin = EventOrigin.COMMUNITY, source = null),
        )
        assertEquals(2, EventSeries.fold(events).size)
    }

    @Test
    fun `an unparsable time is never folded`() {
        val events = listOf(
            entry("a", "Лускунчик", "колись"),
            entry("b", "Лускунчик", "2026-12-23T18:00:00Z"),
        )
        assertEquals(2, EventSeries.fold(events).size)
    }

    @Test
    fun `a title that survives normalisation empty is never folded`() {
        // Від «Концерт» і «Шоу» після зведення нічого не лишається; порожні набори не збираються.
        val events = listOf(
            entry("a", "Концерт", "2026-10-01T18:00:00Z"),
            entry("b", "Шоу", "2026-10-02T18:00:00Z"),
        )
        assertEquals(2, EventSeries.fold(events).size)
    }

    @Test
    fun `events outside any run pass through unchanged`() {
        val alone = entry("solo", "Одинична подія", "2026-10-01T18:00:00Z")
        val folded = EventSeries.fold(listOf(alone, entry("x", "Інша", "2026-10-02T18:00:00Z")))
        assertTrue(folded.any { it === alone }, "не перемальовуємо те, що не змінилось")
    }

    @Test
    fun `a single event is returned as is`() {
        val one = listOf(entry("a", "Лускунчик", "2026-12-22T18:00:00Z"))
        assertTrue(EventSeries.fold(one) === one)
    }

    @Test
    fun `folding runs after duplicate folding so one session is not counted twice`() {
        // Спершу DuplicateEvents, потім прокат, інакше карусель показала б 22 грудня двічі.
        val raw = listOf(
            entry("a", "Лускунчик", "2026-12-22T18:00:00Z", source = "karabas"),
            entry("b", "Лускунчик", "2026-12-22T18:00:00Z", source = "concert_ua"),
            entry("c", "Лускунчик", "2026-12-23T18:00:00Z", source = "karabas"),
        )
        val folded = EventSeries.fold(DuplicateEvents.fold(raw))
        assertEquals(1, folded.size)
        assertEquals(2, folded[0].sessionCount, "два вечори, а не три рядки")
    }

    // ---- Карусель на екрані деталей

    /** Картка афіші, як її віддає `event_details`. */
    private fun card(id: String, title: String, startsAt: String, status: String = EventStatus.PUBLISHED) = Event(
        id, title, "", "art", "Київ", "Хрещатик", startsAt, startsAt, "Europe/Kyiv", status, 50.45, 30.53
    )

    @Test
    fun `a cancelled session stays in the carousel and is marked`() {
        // Скасований вечір в індексі відсутній, але відкритий зі «Збережених» має показати інші дати.
        val index = EventSeries.fold(
            listOf(
                entry("a", "Лускунчик", "2026-12-22T18:00:00Z"),
                entry("c", "Лускунчик", "2026-12-30T18:00:00Z"),
            )
        )
        val opened = card("b", "Лускунчик", "2026-12-23T18:00:00Z", EventStatus.CANCELLED)

        val sessions = EventSeries.sessionsOf(opened, index)

        assertEquals(listOf("a", "b", "c"), sessions.map { it.id }, "на своєму місці в часі")
        assertEquals(listOf("b"), sessions.filter { it.cancelled }.map { it.id }, "позначений лише він")
    }

    @Test
    fun `a session cancelled after the index arrived is marked from its own card`() {
        val index = EventSeries.fold(
            listOf(
                entry("a", "Лускунчик", "2026-12-22T18:00:00Z"),
                entry("b", "Лускунчик", "2026-12-23T18:00:00Z"),
            )
        )
        val sessions = EventSeries.sessionsOf(card("b", "Лускунчик", "2026-12-23T18:00:00Z", EventStatus.CANCELLED), index)
        assertEquals(listOf(false, true), sessions.map { it.cancelled })
    }

    @Test
    fun `an event without a run has no carousel`() {
        val index = listOf(entry("x", "Лебедине озеро", "2026-12-22T18:00:00Z"))
        assertEquals(emptyList(), EventSeries.sessionsOf(card("a", "Лускунчик", "2026-12-23T18:00:00Z"), index))
        // Карусель з одного елемента обіцяє вибір, якого немає.
        val alone = listOf(entry("a", "Лускунчик", "2026-12-23T18:00:00Z"))
        assertEquals(emptyList(), EventSeries.sessionsOf(card("a", "Лускунчик", "2026-12-23T18:00:00Z"), alone))
    }

    @Test
    fun `other days count days not sessions`() {
        fun session(id: String, at: String) = EventSession(id, at, "Europe/Kyiv")
        // Два сеанси одного дня — «ще 1 дата» збрехало б.
        assertEquals(0, EventSeries.otherDays(listOf(session("m", "2026-10-27T13:30:00Z"), session("e", "2026-10-27T16:30:00Z"))))
        // Прокат з розривами: число днів, а не проміжок.
        assertEquals(2, EventSeries.otherDays(listOf(
            session("a", "2026-10-05T16:00:00Z"), session("b", "2026-10-12T16:00:00Z"), session("c", "2026-10-27T16:00:00Z"))))
    }

    @Test
    fun `a day is the session's own day and not the UTC one`() {
        // 00:30 за Києвом — це 22:30 UTC напередодні; за UTC вийшло б два дні.
        val sessions = listOf(
            EventSession("night", "2026-12-22T22:30:00Z", "Europe/Kyiv"),
            EventSession("morning", "2026-12-23T08:00:00Z", "Europe/Kyiv"),
        )
        assertEquals(0, EventSeries.otherDays(sessions))
    }
}
