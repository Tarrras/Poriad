package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals

/** «Ваші артисти»: хто їде в місто — першими й найближчі першими, далі тур іншими містами, далі без анонсів за іменем. */
class RadarRulesTest {
    private fun row(name: String, next: String? = null, elsewhere: String? = null) = ArtistRadar(
        name, name, null, next?.let { RadarEvent("e-$name", name, it, "Europe/Kyiv") }, if (next != null) 1 else 0,
        listOfNotNull(elsewhere?.let { RadarCity("Львів", it) })
    )

    @Test fun inTheCityFirstThenTourThenQuiet() {
        val rows = listOf(
            row("Яр"), row("Бумбокс", elsewhere = "2026-11-20T18:00:00Z"), row("Антитіла"),
            row("ТІК", next = "2026-12-14T17:00:00Z"), row("Kalush", next = "2026-11-08T17:00:00Z"),
            row("Океан Ельзи", elsewhere = "2026-11-02T18:00:00Z")
        )
        assertEquals(
            listOf("Kalush", "ТІК", "Океан Ельзи", "Бумбокс", "Антитіла", "Яр"),
            RadarRules.order(rows).map { it.name }
        )
    }
}
