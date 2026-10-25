package app.poruch.shared

import app.poruch.domain.District
import app.poruch.domain.DistrictHit
import app.poruch.domain.EventIndexEntry

/**
 * Райони з числами для мапи й головної: секція «Райони» пошуку й список під чипом «Район». Числа — з індексу міста, як
 * у закладів, і рахуються лише тоді, коли змінились текст, райони чи індекс: точка в полігоні для тисяч подій не
 * повторюється на кожну картку, що доїхала. Один екземпляр — одне застосування, інакше пам'ять перетиралась би.
 */
internal class DistrictSearch {
    private var from: Triple<String?, List<District>, List<EventIndexEntry>>? = null
    private var hits: List<DistrictHit> = emptyList()

    /** Секція «Райони» за текстом пошуку. Без тексту — порожньо. */
    fun hits(text: String, districts: List<District>, index: List<EventIndexEntry>): List<DistrictHit> =
        remember(text, districts, index) { if (text.isBlank()) emptyList() else District.search(districts, text, index) }

    /** Усі райони міста: список під чипом «Район». */
    fun all(districts: List<District>, index: List<EventIndexEntry>): List<DistrictHit> =
        remember(null, districts, index) { District.ranked(districts, index) }

    private inline fun remember(
        text: String?, districts: List<District>, index: List<EventIndexEntry>, compute: () -> List<DistrictHit>
    ): List<DistrictHit> {
        val last = from
        if (last == null || last.first != text || last.second !== districts || last.third !== index) {
            hits = compute()
            from = Triple(text, districts, index)
        }
        return hits
    }
}
