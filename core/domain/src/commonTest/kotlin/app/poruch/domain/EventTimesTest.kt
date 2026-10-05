package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

/** Два питання про час: чи подія йде зараз і чи це сеанс, а не прокат. */
class EventTimesTest {
    private fun event(startsAt: String, endsAt: String, zone: String = "Europe/Kyiv", title: String = "Виставка") = Event(
        id = "e", title = title, description = "", category = EventCategory.ART, city = "Київ",
        address = "Поділ", startsAt = startsAt, endsAt = endsAt, timeZone = zone,
        status = EventStatus.PUBLISHED, latitude = 50.45, longitude = 30.52,
        listing = Listing(sourceName = "Karabas")
    )

    private val now = Instant.parse("2026-09-11T09:00:00Z")

    @Test fun aConcertThatStartedAnHourAgoIsUnderwayButNotARun() {
        val concert = event("2026-09-11T11:00:00+03:00", "2026-09-11T15:00:00+03:00")
        assertTrue(concert.isUnderway(now))
        assertFalse(concert.isMultiDay)
    }

    @Test fun anExhibitionThatRunsForWeeksIsBoth() {
        val exhibition = event("2026-07-16T10:00:00+03:00", "2026-09-30T20:00:00+03:00")
        assertTrue(exhibition.isUnderway(now))
        assertTrue(exhibition.isMultiDay)
    }

    /** Стендап, що вже йде, не пропонуємо: не встигнеш. Виставку посеред прокату — так. */
    @Test fun aStartedSessionIsNotListedButARunningExhibitionIs() {
        assertFalse(event("2026-09-11T11:00:00+03:00", "2026-09-11T15:00:00+03:00").isListed(now), "started session")
        assertTrue(event("2026-09-11T12:30:00+03:00", "2026-09-11T15:00:00+03:00").isListed(now), "session ahead")
        assertTrue(event("2026-07-16T10:00:00+03:00", "2026-09-30T20:00:00+03:00").isListed(now), "running exhibition")
        assertFalse(event("2026-07-16T10:00:00+03:00", "2026-09-11T11:00:00+03:00").isListed(now), "ended run")
    }

    /** Ярмарок на день — як прокат: приходять будь-коли. Але «Ярмарок» на дві години — вистава, а не ярмарок. */
    @Test fun aOneDayFairStaysListedButAShortShowNamedSoDoesNot() {
        val fair = { title: String, ends: String -> event("2026-09-11T10:00:00+03:00", ends, title = title) }
        assertTrue(fair("КОТИКИ ФЕСТ", "2026-09-11T18:00:00+03:00").isListed(now), "day festival")
        assertTrue(fair("Різдвяний ярмарок", "2026-09-11T18:00:00+03:00").isListed(now), "day fair")
        assertFalse(fair("Сорочинський ярмарок (Театр Оперети)", "2026-09-11T12:30:00+03:00").isListed(now), "a play named fair")
        assertFalse(fair("Смерть комівояжера", "2026-09-11T18:00:00+03:00").isListed(now), "a play with a made-up end")
    }

    /** Вечір через північ — один вечір, а не прокат. */
    @Test fun aConcertPastMidnightIsStillOneEvening() {
        val concert = event("2026-09-11T22:00:00+03:00", "2026-09-12T02:00:00+03:00")
        assertFalse(concert.isMultiDay)
    }

    /** Прокат — прокат і до відкриття: «до коли» не залежить від «зараз». */
    @Test fun aRunIsARunBeforeItOpens() {
        val future = event("2026-10-01T10:00:00+03:00", "2026-11-01T20:00:00+03:00")
        assertFalse(future.isUnderway(now))
        assertTrue(future.isMultiDay)
    }

    /** Зіпсований рядок не має валити екран. */
    @Test fun brokenTimestampsAnswerNoWithoutThrowing() {
        assertFalse(event("not-a-date", "also-not-a-date").isMultiDay)
        assertFalse(event("2026-07-16T10:00:00+03:00", "not-a-date").isUnderway(now))
    }
}
