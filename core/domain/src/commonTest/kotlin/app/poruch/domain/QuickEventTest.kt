package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

/** «Швидка подія» (docs/creation-platform-plan-2026-11.md, етап 2): шаблони, чипи дня, година й підказка про кабінет. */
class QuickEventTest {
    private val kyiv = "Europe/Kyiv"
    private fun at(iso: String) = Instant.parse(iso).toEpochMilliseconds()
    private fun iso(millis: Long) = Instant.fromEpochMilliseconds(millis).toString()

    /** Маленька компанія — до 12 місць включно; 13 і більше — вже анонс першим. */
    @Test fun smallUpToTwelveSeats() {
        assertTrue(QuickEvent.isSmall(2)); assertTrue(QuickEvent.isSmall(12))
        assertFalse(QuickEvent.isSmall(13)); assertFalse(QuickEvent.isSmall(0))
        assertTrue(MeetupTemplate.entries.all { QuickEvent.isSmall(it.seats) }, "шаблони — маленькі зустрічі")
    }

    /** Нема ні адреси, ні точки — одне прохання про точку; точка є, а адреси нема — прохання про адресу. */
    @Test fun placeProblemsAskOnce() {
        val all = listOf(DraftField.TITLE, DraftField.ADDRESS, DraftField.LOCATION, DraftField.CAPACITY)
        assertEquals(listOf(DraftField.TITLE, DraftField.LOCATION, DraftField.CAPACITY), QuickEvent.placeProblems(all))
        assertEquals(listOf(DraftField.ADDRESS), QuickEvent.placeProblems(listOf(DraftField.ADDRESS)))
        assertEquals(listOf(DraftField.LOCATION), QuickEvent.placeProblems(listOf(DraftField.LOCATION)))
        assertEquals(emptyList(), QuickEvent.placeProblems(emptyList()))
    }

    /** Кіно 4, настолки 6, майстер-клас 8 — а не 20; жанр кіно — «зустрічі», бо `cinema` ховається з добірок. */
    @Test fun templatesSetGenreSeatsAndDuration() {
        assertEquals(listOf(4, 6, 6, 4, 8, 8), MeetupTemplate.entries.map { it.seats })
        assertEquals(EventCategory.SOCIAL, MeetupTemplate.CINEMA.category)
        assertEquals(EventCategory.GAMES, MeetupTemplate.BOARD_GAMES.category)
        assertTrue(MeetupTemplate.entries.all { it.seats <= QuickEvent.LARGE_SEATS && it.minutes in 60..240 })
        assertEquals(MeetupTemplate.WALK, MeetupTemplate.fromKey("walk"))
        assertNull(MeetupTemplate.fromKey("opera")); assertNull(MeetupTemplate.fromKey(null))
    }

    @Test fun theTemplateNamesTheEventOnlyUntilThePersonDoes() {
        assertEquals("Кава", QuickEvent.title("", null, "Кава"))
        assertEquals("Кава", QuickEvent.title("Настолки ", "Настолки", "Кава"), "ще назва попереднього шаблону")
        assertEquals("Настолки: Каркасон", QuickEvent.title("Настолки: Каркасон", "Настолки", "Кава"))
    }

    @Test fun theCabinetHintStartsAboveThirtySeats() {
        assertFalse(QuickEvent.isLarge(30)); assertTrue(QuickEvent.isLarge(31))
    }

    @Test fun onlyTheFourQuestionsStayOutOfMore() {
        assertEquals(
            setOf(DraftField.TITLE, DraftField.ADDRESS, DraftField.LOCATION, DraftField.STARTS_AT, DraftField.CAPACITY),
            DraftField.entries.filterNot(QuickEvent::isMore).toSet()
        )
    }

    /** Ср 11.11: субота 14.11. Пт 13.11: завтра вже субота, тож третій чип — неділя. Сб 14.11: наступна субота. */
    @Test fun theThirdDayIsTheNearestWeekendAfterTomorrow() {
        fun third(now: String) = QuickEvent.days(at(now), kyiv).also { days ->
            assertEquals(listOf(QuickDayKind.TODAY, QuickDayKind.TOMORROW, QuickDayKind.WEEKEND), days.map { it.kind })
        }.last()
        assertEquals("2026-11-14" to false, third("2026-11-11T10:00:00Z").let { it.date.toString() to it.sunday })
        assertEquals("2026-11-15" to true, third("2026-11-13T10:00:00Z").let { it.date.toString() to it.sunday })
        assertEquals("2026-11-21" to false, third("2026-11-14T10:00:00Z").let { it.date.toString() to it.sunday })
        // За Києвом уже четвер, хоч за UTC ще середа.
        assertEquals("2026-11-12", QuickEvent.days(at("2026-11-11T22:30:00Z"), kyiv).first().date.toString())
    }

    /** 19:00 за Києвом — 17:00 UTC (зимовий час). */
    @Test fun aNewMeetupStartsTonightOrTomorrowEvening() {
        assertEquals("2026-11-11T17:00:00Z", iso(QuickEvent.defaultStart(at("2026-11-11T10:00:00Z"), kyiv)))
        assertEquals("2026-11-12T17:00:00Z", iso(QuickEvent.defaultStart(at("2026-11-11T15:30:00Z"), kyiv)), "до 19:00 менше двох годин")
    }

    @Test fun aDayChipKeepsTheHourAndNeverLandsInThePast() {
        val now = at("2026-11-11T18:20:00Z") // 20:20 за Києвом
        val days = QuickEvent.days(now, kyiv)
        val evening = at("2026-11-12T17:30:00Z") // завтра 19:30
        assertEquals("2026-11-14T17:30:00Z", iso(QuickEvent.startOn(days[2], evening, now, kyiv)), "субота, та сама година")
        assertEquals("2026-11-11T20:00:00Z", iso(QuickEvent.startOn(days[0], evening, now, kyiv)), "сьогодні 19:30 минуло — 22:00")
        assertEquals("2026-11-12T17:00:00Z", iso(QuickEvent.startOn(days[1], null, now, kyiv)), "без години — 19:00")
        assertEquals(QuickDayKind.WEEKEND, QuickEvent.dayOf(at("2026-11-14T17:30:00Z"), now, kyiv))
        assertNull(QuickEvent.dayOf(at("2026-11-20T17:30:00Z"), now, kyiv), "інша дата")
    }

    @Test fun theEndKeepsTheOldDurationOrTakesTheTemplate() {
        val start = at("2026-11-12T17:00:00Z")
        assertEquals("2026-11-12T19:00:00Z", iso(QuickEvent.end(start)))
        assertEquals("2026-11-12T20:00:00Z", iso(QuickEvent.end(start, minutes = MeetupTemplate.BOARD_GAMES.minutes)))
        // Подія з сайту на три години лишається тригодинною, коли в застосунку пересунули початок.
        assertEquals("2026-11-12T20:00:00Z", iso(QuickEvent.end(start, at("2026-11-10T10:00:00Z"), at("2026-11-10T13:00:00Z"))))
        assertEquals("2026-11-12T19:00:00Z", iso(QuickEvent.end(start, at("2026-11-10T10:00:00Z"), at("2026-11-10T09:00:00Z"))), "зіпсована пара")
    }
}
