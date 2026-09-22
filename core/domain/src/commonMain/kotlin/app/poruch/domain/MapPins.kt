package app.poruch.domain

import kotlin.math.roundToLong

/**
 * Пін на мапі — це місце, а не подія. Імпортовані події беруть координати з кеша майданчиків,
 * тож усі події закладу стоять на одній точці й окремими пінами перекривали б одна одну за
 * будь-якого зуму. Групуємо тут, щоб Android та iOS показували ту саму мапу, і над
 * [EventIndexEntry], бо піну досить координат і категорії.
 */
data class VenuePin(
    val latitude: Double,
    val longitude: Double,
    /** Усі події цього місця, від найближчої до найдальшої. */
    val eventIds: List<String>,
    /** Найближча за часом подія: її значок і категорія на піні. */
    val representative: EventIndexEntry
) {
    val count get() = eventIds.size
    val hasMany get() = eventIds.size > 1

    fun contains(eventId: String?) = eventId != null && eventId in eventIds
}

object MapPins {

    /** Шість знаків після коми ≈ 11 см. Округлення захищає від порівняння Double на рівність, а не склеює сусідів. */
    private const val PRECISION = 1_000_000.0

    /**
     * Ключ місця — пара, а не згортка `lat*31 + lon`: та колізіювала для сусідніх майданчиків,
     * а на цьому ж ключі стоїть [DuplicateEvents], яка вже прибирає події зі списку.
     */
    internal data class Place(val latitude: Long, val longitude: Long)

    private fun key(latitude: Double, longitude: Double) =
        Place((latitude * PRECISION).roundToLong(), (longitude * PRECISION).roundToLong())

    internal fun placeOf(entry: EventIndexEntry) = key(entry.latitude, entry.longitude)

    /** Групує події в піни місць. Піни й події всередині — за часом початку, як у каруселі. */
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

    /**
     * Інші картки на точці [event], за часом: «що ще в цьому закладі». Власна картка й сеанси її
     * прокату не рахуються — вони вже в каруселі дат.
     */
    fun othersAt(event: Event, index: List<EventIndexEntry>): List<EventIndexEntry> {
        val place = key(event.latitude, event.longitude)
        return index
            .filter { placeOf(it) == place && it.id != event.id && it.sessions.none { s -> s.id == event.id } }
            .sortedBy { it.startsAt }
    }
}
