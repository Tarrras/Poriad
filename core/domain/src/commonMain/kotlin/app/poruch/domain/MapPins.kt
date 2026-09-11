package app.poruch.domain

import kotlin.math.roundToLong

/**
 * Один пін на мапі — це **місце**, а не подія.
 *
 * Причина в даних, а не в естетиці. Координати імпортованих подій беруться з кеша майданчиків, тож
 * усі події одного закладу мають рівно ту саму точку: у Києві 432 події стоять на 71 точці, у
 * найбільшій — 68. Малювати їх окремими пінами означає малювати 68 однакових пінів один поверх
 * одного: вони не розходяться за жодного зуму, а тап дістає завжди верхній.
 *
 * Групування живе тут, а не в кожному клієнті, щоб Android та iOS показували ту саму мапу. Працює
 * над [EventIndexEntry], а не над [Event]: пін читає з події координати й категорію, і тягнути
 * заради нього обкладинку з адресою означало б тягнути їх для всіх 432 подій міста.
 */
data class VenuePin(
    val latitude: Double,
    val longitude: Double,
    /** Усі події цього місця, від найближчої до найдальшої. */
    val eventIds: List<String>,
    /** Подія, чиїм значком і категорією підписано пін — найближча за часом. */
    val representative: EventIndexEntry
) {
    val count get() = eventIds.size
    val hasMany get() = eventIds.size > 1

    fun contains(eventId: String?) = eventId != null && eventId in eventIds
}

object MapPins {

    /**
     * Шоста цифра після коми — це ≈11 см. Точки, що збіглися до такої міри, — те саме місце, і
     * округлення тут захищає від порівняння двійкових дробів на рівність, а не склеює сусідів.
     */
    private const val PRECISION = 1_000_000.0

    /**
     * Ключ місця — **пара**, а не згорнуте в одне число `lat*31 + lon`.
     *
     * Стара згортка колізіювала: підняти широту на 1e-6 і опустити довготу на 31e-6 дає те саме
     * число, тобто два майданчики за три метри одне від одного зливались у пін. Для мапи це було
     * майже непомітно, але на цьому ж ключі стоїть [DuplicateEvents], а вона вже не фарбує пін, а
     * **прибирає** подію зі списку — там ціна помилки інша.
     */
    internal data class Place(val latitude: Long, val longitude: Long)

    private fun key(latitude: Double, longitude: Double) =
        Place((latitude * PRECISION).roundToLong(), (longitude * PRECISION).roundToLong())

    internal fun placeOf(entry: EventIndexEntry) = key(entry.latitude, entry.longitude)

    /**
     * Групує події в піни місць. Порядок пінів і порядок подій усередині — за часом початку, тож
     * мапа й карусель читають той самий список однаково.
     */
    fun group(events: List<EventIndexEntry>): List<VenuePin> {
        if (events.isEmpty()) return emptyList()
        val byPlace = LinkedHashMap<Place, MutableList<EventIndexEntry>>()
        for (event in events.sortedBy { it.startsAt }) {
            byPlace.getOrPut(key(event.latitude, event.longitude)) { mutableListOf() }.add(event)
        }
        return byPlace.values.map { atPlace ->
            val first = atPlace.first()
            VenuePin(first.latitude, first.longitude, atPlace.map { it.id }, first)
        }
    }
}
