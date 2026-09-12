package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

/**
 * Подія, що вже почалась, але ще не скінчилась, і подія, що триває тижнями.
 *
 * До цієї роботи ні того, ні того не існувало: сервер відсікав за часом початку, а підпис знав
 * лише «коли почнеться». Тут перевіряються два питання, які клієнт тепер ставить замість того:
 * чи вона йде просто зараз, і чи це взагалі сеанс, а не прокат.
 */
class EventTimesTest {
    private fun event(startsAt: String, endsAt: String, zone: String = "Europe/Kyiv") = Event(
        id = "e", title = "Виставка", description = "", category = "art", city = "Київ",
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

    /**
     * Календар сказав би «так»: подія кінчається наступного числа. Але це один вечір, і проміжок
     * дат замість «22:00» зіпсував би про нього головне.
     */
    @Test fun aConcertPastMidnightIsStillOneEvening() {
        val concert = event("2026-09-11T22:00:00+03:00", "2026-09-12T02:00:00+03:00")
        assertFalse(concert.isMultiDay)
    }

    /** Прокат лишається прокатом і до відкриття: питання «до коли» не залежить від «зараз». */
    @Test fun aRunIsARunBeforeItOpens() {
        val future = event("2026-10-01T10:00:00+03:00", "2026-11-01T20:00:00+03:00")
        assertFalse(future.isUnderway(now))
        assertTrue(future.isMultiDay)
    }

    /** Зіпсований рядок із сервера не має валити екран. */
    @Test fun brokenTimestampsAnswerNoWithoutThrowing() {
        assertFalse(event("not-a-date", "also-not-a-date").isMultiDay)
        assertFalse(event("2026-07-16T10:00:00+03:00", "not-a-date").isUnderway(now))
    }
}
