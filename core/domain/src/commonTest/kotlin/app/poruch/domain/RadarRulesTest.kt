package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals

/** «Ваше»: дати артистів по одній на подію і бюджет рядків на все особисте. */
class RadarRulesTest {
    private fun row(name: String, event: String? = null, at: String = "2026-11-08T17:00:00Z") = ArtistRadar(
        name, name, null, event?.let { RadarEvent(it, it, at, "Europe/Kyiv") }, if (event != null) 1 else 0, emptyList()
    )

    @Test fun oneRowPerEventWithEveryArtistNearestFirst() {
        val dates = RadarRules.dates(
            listOf(
                row("Пучков", "obkatka", "2026-10-29T17:00:00Z"), row("Бережко", "vechir", "2026-10-29T16:00:00Z"),
                row("Редзель", "obkatka", "2026-10-29T17:00:00Z"), row("Без дат"), row("Скремінський", "obkatka", "2026-10-29T17:00:00Z")
            )
        )
        assertEquals(listOf("vechir", "obkatka"), dates.map { it.event.eventId })
        assertEquals(listOf("Пучков", "Редзель", "Скремінський"), dates[1].artists)
    }

    @Test fun plansComeFirstAndHiddenDatesKeepTheFollowsRow() {
        // Два плани й шість дат: одна дата і «Ви стежите», куди ведуть решта.
        assertEquals(YoursSlots(2, false, false, 1, true), HomeRules.yours(2, false, false, 6, false))
        // Гість: стос, дати влазять без «Ви стежите».
        assertEquals(YoursSlots(0, false, true, 3, false), HomeRules.yours(0, false, true, 3, false))
        // Тиждень, дати й підписки: «Ви стежите» тримає місце.
        assertEquals(YoursSlots(0, false, true, 2, true), HomeRules.yours(0, false, true, 3, true))
        // Три плани й «чекають ще» займають усе.
        assertEquals(YoursSlots(3, true, false, 0, false), HomeRules.yours(3, true, true, 4, true))
        // Ніде не більше чотирьох рядків.
        for (plans in 0..3) for (dates in 0..6) for (deck in listOf(false, true)) for (follows in listOf(false, true)) {
            val s = HomeRules.yours(plans, plans == 3, deck, dates, follows)
            val rows = s.plans + listOf(s.waiting, s.deck, s.follows).count { it } + s.dates
            assert(rows <= HomeRules.YOURS_ROWS) { "$plans/$dates/$deck/$follows → $s" }
        }
    }
}
