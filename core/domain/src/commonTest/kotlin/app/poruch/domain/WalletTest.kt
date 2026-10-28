package app.poruch.domain

import kotlin.test.*
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone

/** Квитки різних продавців читаються в ту саму чернетку; дата покупки не плутається з початком. */
class WalletTest {
    private val today = LocalDate(2026, 10, 28)
    private val kyiv = TimeZone.of("Europe/Kyiv")

    private val multiplex = """
        MULTIPLEX
        Електронний квиток
        Фільм: Дюна: Частина друга
        Кінотеатр: Multiplex Respublika Park
        Зал: 5
        Дата: 30.10.2026
        Початок: 19:40
        Ряд 7 Місце 12
        Ціна: 250 грн
        Дата покупки: 20.10.2026 12:31
    """.trimIndent()

    @Test fun multiplexTicketReadsByLabels() {
        val draft = TicketReader.read(multiplex, today)
        assertEquals("Дюна: Частина друга", draft.title)
        assertEquals("Multiplex Respublika Park, зал 5", draft.place)
        assertEquals(LocalDateTime(2026, 10, 30, 19, 40), draft.start, "початок, а не дата покупки")
        assertEquals(listOf(TicketSeat("7", "12")), draft.seats)
        assertEquals("full", draft.parsed)
    }

    @Test fun severalTicketsInOneFileGiveSeveralSeats() {
        val two = multiplex + "\n" + multiplex.replace("Місце 12", "Місце 13")
        assertEquals(listOf(TicketSeat("7", "12"), TicketSeat("7", "13")), TicketReader.read(two, today).seats)
    }

    @Test fun concertTicketWithoutLabels() {
        val draft = TicketReader.read("""
            ЕЛЕКТРОННИЙ КВИТОК
            Один в каное
            14 грудня 2026, 19:00
            Палац Спорту, Київ
            Сектор: Партер Ряд: 5 Місце: 10
            Ціна: 900 грн
            concert.ua
        """.trimIndent(), today)
        assertEquals("Один в каное", draft.title)
        assertEquals(LocalDateTime(2026, 12, 14, 19, 0), draft.start)
        assertEquals(listOf(TicketSeat("5", "10")), draft.seats)
    }

    @Test fun doorsTimeLosesToStartTime() {
        val draft = TicketReader.read("""
            karabas.com
            Ліст. Безмежжя уяви (Музичний салон НФУ)
            Національна філармонія України
            30.10.2026 Вхід з 15:30 Початок о 16:00
            Ряд 3, Місце 15
            Замовлення №123456 від 21.10.2026 10:15
        """.trimIndent(), today)
        assertEquals("Ліст. Безмежжя уяви (Музичний салон НФУ)", draft.title)
        assertEquals(LocalDateTime(2026, 10, 30, 16, 0), draft.start)
    }

    @Test fun dateWithoutYearIsTheNextOne() {
        assertEquals(LocalDateTime(2026, 11, 1, 20, 0), TicketReader.read("Стендап\nСб, 1 листопада о 20:00", today).start)
        assertEquals(LocalDateTime(2027, 1, 5, 18, 30), TicketReader.read("Щедрик\n5 січня 18:30", today).start)
    }

    @Test fun titleIsNotCutByWordsInsideIt() {
        assertEquals("Шоу «Що нового?»", TicketReader.read("Шоу «Що нового?»\n1 листопада 20:00", today).title, "«Шоу» без двокрапки — не підпис")
        assertEquals("Частина друга", TicketReader.read("Квиток\nЧастина друга\n1 листопада 20:00", today).title, "«Частина» — не «час»")
    }

    @Test fun nothingReadableIsAnEmptyDraft() {
        val draft = TicketReader.read("", today)
        assertNull(draft.title); assertNull(draft.start)
        assertEquals("none", draft.parsed)
    }

    private fun entry(id: String, title: String, startsAt: String, sessions: List<EventSession> = emptyList()) = EventIndexEntry(
        id, 50.45, 30.52, EventCategory.MUSIC, startsAt, "Europe/Kyiv", title, EventOrigin.IMPORT, sessions = sessions
    )

    @Test fun ticketFindsItsListing() {
        // 30.10.2026 Київ — уже зимовий час, UTC+2: 16:00 місцевого — 14:00Z.
        val index = listOf(
            entry("liszt", "ЛІСТ. БЕЗМЕЖЖЯ УЯВИ (МУЗИЧНИЙ САЛОН НФУ)", "2026-10-30T14:00:00Z"),
            entry("other", "Вечір джазу", "2026-10-30T14:00:00Z"),
        )
        val draft = TicketDraft(title = "Ліст. Безмежжя уяви", start = LocalDateTime(2026, 10, 30, 16, 0))
        assertEquals("liszt", TicketMatch.match(draft, index, kyiv))
    }

    @Test fun cinemaWithoutListingStaysOnItsOwn() {
        val index = listOf(entry("liszt", "Ліст. Безмежжя уяви", "2026-10-30T14:00:00Z"))
        assertNull(TicketMatch.match(TicketDraft(title = "Дюна: Частина друга", start = LocalDateTime(2026, 10, 30, 16, 0)), index, kyiv))
        assertNull(TicketMatch.match(TicketDraft(title = "Ліст. Безмежжя уяви", start = LocalDateTime(2026, 10, 31, 16, 0)), index, kyiv),
            "та сама назва іншого дня — інший сеанс, якого в індексі нема")
    }

    @Test fun ticketForAnotherSessionOpensThatSession() {
        val index = listOf(entry("first", "Тіні забутих предків", "2026-10-30T16:00:00Z",
            sessions = listOf(EventSession("first", "2026-10-30T16:00:00Z", "Europe/Kyiv"), EventSession("second", "2026-11-05T17:00:00Z", "Europe/Kyiv"))))
        val draft = TicketDraft(title = "Тіні забутих предків", start = LocalDateTime(2026, 11, 5, 19, 0))
        assertEquals("second", TicketMatch.match(draft, index, kyiv))
    }
}
