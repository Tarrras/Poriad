package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant
import kotlinx.datetime.TimeZone

/** Стос «Ваш тиждень»: тиждень наперед, без скасованих, не більше трьох одного жанру поспіль, менше чотирьох — нічого. */
class DeckRulesTest {
    // Середа, 23 вересня 2026, полудень у Києві.
    private val now = Instant.parse("2026-09-23T09:00:00Z")

    private fun event(id: String, startsAt: String = "2026-09-25T16:00:00Z", category: EventCategory = EventCategory.MUSIC, status: EventStatus = EventStatus.PUBLISHED) = Event(
        id = id, title = id, description = "", category = category, city = "Київ", address = "Поділ",
        startsAt = startsAt, endsAt = startsAt.replace("16:00", "18:00"), timeZone = "Europe/Kyiv", status = status,
        latitude = 0.0, longitude = 0.0
    )

    @Test fun weekAheadOnlyAndNoCancelled() {
        val events = listOf(
            event("a"), event("b", category = EventCategory.COMEDY), event("c", category = EventCategory.FOOD),
            event("far", "2026-10-05T16:00:00Z"), event("gone", status = EventStatus.CANCELLED), event("d", category = EventCategory.ART)
        )
        assertEquals(listOf("a", "b", "c", "d"), DeckRules.pick(events, now).map { it.id })
    }

    @Test fun noLongStreaksOfOneGenre() {
        val music = (1..5).map { event("m$it") }
        val comedy = event("c1", category = EventCategory.COMEDY)
        assertEquals(listOf("m1", "m2", "m3", "c1", "m4", "m5"), DeckRules.pick(music + comedy, now).map { it.id })
    }

    @Test fun tooFewMeansNoDeck() {
        assertTrue(DeckRules.pick(listOf(event("a"), event("b"), event("c")), now).isEmpty())
        assertEquals(DeckRules.MAX, DeckRules.pick((1..20).map { event("e$it", category = EventCategory.entries[it % 5]) }, now).size)
    }

    @Test fun weekIsItsMonday() {
        val kyiv = TimeZone.of("Europe/Kyiv")
        assertEquals("2026-09-21", DeckRules.week(now, kyiv))
        assertEquals("2026-09-28", DeckRules.week(Instant.parse("2026-09-28T06:00:00Z"), kyiv))
    }

    /** Що це за подія в стосі: речення агента імпорту й уривок опису разом, порожнє — null. */
    @Test fun aboutKeepsBothTheLineAndTheExcerpt() {
        assertEquals(EventAbout("Стендап про стосунки", "Довгий опис"),
            event("a").copy(description = "Довгий опис", blurb = " Стендап про стосунки ").about)
        assertEquals(EventAbout(null, "Довгий опис."), event("a").copy(description = "Довгий\n\n опис.", blurb = "  ").about)
        assertEquals(EventAbout(null, null), event("a").about)
    }
}
