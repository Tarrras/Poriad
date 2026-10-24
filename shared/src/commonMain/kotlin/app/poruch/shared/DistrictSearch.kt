package app.poruch.shared

import app.poruch.domain.District
import app.poruch.domain.DistrictHit
import app.poruch.domain.EventIndexEntry

/**
 * Секція «Райони» пошуку мапи й головної. Числа — з індексу міста, як у закладів, і рахуються лише тоді, коли змінились
 * текст, райони чи індекс: точка в полігоні для тисяч подій не повторюється на кожну картку, що доїхала.
 */
internal class DistrictSearch {
    private var from: Triple<String, List<District>, List<EventIndexEntry>>? = null
    private var hits: List<DistrictHit> = emptyList()

    fun hits(text: String, districts: List<District>, index: List<EventIndexEntry>): List<DistrictHit> {
        val last = from
        if (last == null || last.first != text || last.second !== districts || last.third !== index) {
            hits = if (text.isBlank()) emptyList() else District.search(districts, text, index)
            from = Triple(text, districts, index)
        }
        return hits
    }
}
