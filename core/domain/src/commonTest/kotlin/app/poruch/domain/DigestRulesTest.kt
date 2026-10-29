package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant
import kotlinx.datetime.TimeZone

/**
 * Дайджест у вільний час (docs/return-hooks.md, хвиля 2): про вихідні — до чотирьох четвергів о 18:00, про пт-вечір–нд;
 * про будні — понеділок о 17:00, лише коли будні обрано; не менше трьох подій; одна вирізнена подія з причинами.
 */
class DigestRulesTest {
    private val kyiv = TimeZone.of("Europe/Kyiv")
    // Середа, 23 вересня 2026, полудень у Києві. Четвер — 24-го, пʼятниця — 25-го, вихідні — 26–27-го.
    private val wednesday = Instant.parse("2026-09-23T09:00:00Z")
    private val thursdayFire = Instant.parse("2026-09-24T15:00:00Z").toEpochMilliseconds()

    private fun entry(
        id: String, startsAt: String, sessions: List<String> = emptyList(), origin: EventOrigin = EventOrigin.IMPORT,
        category: EventCategory = EventCategory.GAMES, company: Int = 0
    ) = EventIndexEntry(
        id = id, latitude = 50.45, longitude = 30.52, category = category,
        startsAt = startsAt, timeZone = "Europe/Kyiv", title = "Подія $id", origin = origin,
        sessions = sessions.mapIndexed { i, s -> EventSession("$id-$i", s, "Europe/Kyiv") }, companyCount = company
    )

    private val weekend = listOf(
        entry("a", "2026-09-26T10:00:00Z"),
        entry("b", "2026-09-27T16:00:00Z"),
        entry("c", "2026-09-25T21:30:00Z") // субота, 00:30 за Києвом
    )

    /** [count] подій на суботу [saturday] (YYYY-MM-DD), полудень за Києвом. */
    private fun saturday(saturday: String, count: Int) = (1..count).map { entry("$saturday-$it", "${saturday}T09:00:00Z") }

    @Test fun weekendFiresThursdayAtSixAndCountsFridayEvening() {
        val fridayDay = entry("fri-day", "2026-09-25T13:00:00Z") // 16:00 за Києвом — ще робота
        val fridayEvening = entry("fri-eve", "2026-09-25T17:00:00Z") // 20:00
        val monday = entry("mon", "2026-09-27T21:00:00Z") // понеділок, 00:00 за Києвом
        val digest = DigestRules.plan(weekend + fridayDay + fridayEvening + monday, "Київ", enabled = true, now = wednesday, zone = kyiv).single()
        assertEquals(DigestKind.WEEKEND, digest.kind)
        assertEquals(4, digest.count)
        assertEquals(listOf("Подія a", "Подія b"), digest.titles)
        assertEquals(thursdayFire, digest.fireAtEpochMillis)
        assertEquals("Київ", digest.city)
        assertEquals(1, digest.week)
    }

    @Test fun runCountsWhenAnySessionFallsInTheWindow() {
        val run = entry("run", "2026-09-24T16:00:00Z", listOf("2026-09-24T16:00:00Z", "2026-09-26T16:00:00Z"))
        assertEquals(4, DigestRules.plan(weekend + run, null, true, wednesday, kyiv).single().count)
    }

    @Test fun afterThursdaySixItTargetsNextWeek() {
        val thursdayEvening = Instant.parse("2026-09-24T16:00:00Z")
        val next = listOf("2026-10-03T10:00:00Z", "2026-10-03T12:00:00Z", "2026-10-04T10:00:00Z").mapIndexed { i, s -> entry("n$i", s) }
        val digest = DigestRules.plan(weekend + next, "Київ", true, thursdayEvening, kyiv).single()
        assertEquals(3, digest.count)
        assertEquals(Instant.parse("2026-10-01T15:00:00Z").toEpochMilliseconds(), digest.fireAtEpochMillis)
        assertEquals(1, digest.week)
    }

    @Test fun ladderCoversFourThursdaysSkipsThinOnesAndStopsAfterTheFourth() {
        // Середа, 14 жовтня: четверги 15, 22, 29 жовтня й 5 листопада; 25 жовтня Київ переходить на зимовий час.
        val now = Instant.parse("2026-10-14T09:00:00Z")
        val index = saturday("2026-10-17", 4) + saturday("2026-10-24", 2) + saturday("2026-10-31", 3) +
            saturday("2026-11-07", 5) + saturday("2026-11-14", 6)
        val ladder = DigestRules.plan(index, "Київ", true, now, kyiv)
        assertEquals(listOf(1, 3, 4), ladder.map { it.week })
        assertEquals(listOf(4, 3, 5), ladder.map { it.count })
        assertEquals(
            listOf("2026-10-15T15:00:00Z", "2026-10-29T16:00:00Z", "2026-11-05T16:00:00Z").map { Instant.parse(it).toEpochMilliseconds() },
            ladder.map { it.fireAtEpochMillis }
        )
    }

    /** Будні вечори: понеділок о 17:00 про вечори пн–пт; денна подія середи — не в обраний слот. */
    @Test fun weekdaysOnlyWhenChosenAndOnlyInChosenSlots() {
        val evenings = (1..3).map { entry("eve$it", "2026-09-29T16:00:00Z") } // вівторок, 19:00
        val day = entry("day", "2026-09-30T07:00:00Z") // середа, 10:00
        val index = weekend + evenings + day
        val digest = DigestRules.plan(index, "Київ", true, wednesday, kyiv, Taste(times = listOf(TimeSlot.WEEKDAY_EVENING))).single()
        assertEquals(DigestKind.WEEKDAYS, digest.kind)
        assertEquals(3, digest.count)
        assertEquals(Instant.parse("2026-09-28T14:00:00Z").toEpochMilliseconds(), digest.fireAtEpochMillis)
        assertEquals(11, digest.id)

        val both = DigestRules.plan(index, "Київ", true, wednesday, kyiv,
            Taste(times = listOf(TimeSlot.WEEKDAY_EVENING, TimeSlot.WEEKEND_DAY, TimeSlot.WEEKEND_EVENING)))
        assertEquals(listOf(DigestKind.WEEKEND, DigestKind.WEEKDAYS), both.map { it.kind }.distinct())
    }

    /** Лише вечори вихідних: денна субота й ніч на суботу (00:30 — денний слот) випадають, вечір пʼятниці лишається. */
    @Test fun weekendSlotsNarrowTheWindow() {
        val fridayEvening = entry("fri-eve", "2026-09-25T17:00:00Z")
        val saturdayEvening = entry("sat-eve", "2026-09-26T16:00:00Z") // 19:00
        val digest = DigestRules.plan(weekend + fridayEvening + saturdayEvening, "Київ", true, wednesday, kyiv,
            Taste(times = listOf(TimeSlot.WEEKEND_EVENING))).single()
        assertEquals(3, digest.count, "b, Friday evening and Saturday evening")
        assertEquals(listOf("Подія b", "Подія fri-eve"), digest.titles)
    }

    /** Вирізнена подія: найбільше причин, рівні — за смаком (порядком видачі); прокат — не «один вечір». */
    @Test fun leadIsTheRarestOfWhatFits() {
        val run = entry("run", "2026-09-26T10:00:00Z", listOf("2026-09-26T10:00:00Z", "2026-10-03T10:00:00Z"))
        val single = entry("single", "2026-09-26T12:00:00Z")
        val company = entry("company", "2026-09-26T14:00:00Z", company = 2)
        val followed = entry("followed", "2026-09-26T16:00:00Z")
        val digest = DigestRules.plan(listOf(run, single, company, followed), "Київ", true, wednesday, kyiv,
            followed = mapOf("followed" to "Атлас")).single()
        assertEquals("Подія company", digest.lead)
        assertEquals(listOf(DigestReason.COMPANY, DigestReason.ONE_NIGHT), digest.reasons)
        assertNull(digest.followName)

        val (lead, reasons) = DigestRules.lead(listOf(run, single, followed), Taste(), mapOf("followed" to "Атлас"))!!
        assertEquals("followed", lead.id)
        assertEquals(listOf(DigestReason.FOLLOWED, DigestReason.ONE_NIGHT), reasons)
    }

    /** «Біля вас» — ще одна причина: з рівних причин виграє подія в «Моїх місцях». */
    @Test fun nearIsAReason() {
        val single = entry("single", "2026-09-26T12:00:00Z")
        val near = entry("near", "2026-09-26T14:00:00Z")
        val (lead, reasons) = DigestRules.lead(listOf(single, near), Taste(), emptyMap(), near = setOf("near"))!!
        assertEquals("near", lead.id)
        assertEquals(listOf(DigestReason.NEAR, DigestReason.ONE_NIGHT), reasons)
    }

    @Test fun leadFallsBackToTasteOrNothing() {
        val rooms = (1..3).map { entry("room$it", "2026-09-26T10:00:00Z", origin = EventOrigin.COMMUNITY, category = EventCategory.MUSIC) }
        val music = Taste(interests = listOf(EventCategory.MUSIC), answered = true)
        assertEquals("room1" to listOf(DigestReason.FOR_YOU), DigestRules.lead(rooms, music, emptyMap())?.let { it.first.id to it.second })
        assertNull(DigestRules.lead(rooms, Taste(), emptyMap()), "nothing stands out — just the count")
    }

    @Test fun idKeepsKindAndWeekApart() {
        assertEquals(DigestKind.WEEKDAYS, WeekendDigest.kindOf(12))
        assertEquals(2, WeekendDigest.weekOf(12))
        assertEquals(DigestKind.WEEKEND, WeekendDigest.kindOf(3))
        assertEquals(3, WeekendDigest.weekOf(3))
    }

    @Test fun silentWhenDisabledOrTooFew() {
        assertTrue(DigestRules.plan(weekend, "Київ", enabled = false, now = wednesday, zone = kyiv).isEmpty())
        assertTrue(DigestRules.plan(weekend.take(2), "Київ", enabled = true, now = wednesday, zone = kyiv).isEmpty())
    }
}
