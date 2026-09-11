package app.poruch.data.events

import app.poruch.domain.DiscoveryPage
import app.poruch.domain.EventIndexEntry
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull

/**
 * Відповідь `public.discover_events`: повний індекс, чесне число і перше вікно карток.
 *
 * Індекс приїжджає **масивом масивів**, а не масивом обʼєктів, і це не мікрооптимізація. У старій
 * відповіді на 300 подій основною вагою були не значення, а двадцять вісім разів повторені назви
 * полів; позиційний кортеж прибирає їх усі. Ціна — позиції треба тримати в синхроні з міграцією
 * `20260911070031`, тому вони названі константами, а не написані цифрами по тексту.
 */
@Serializable
internal data class DiscoveryEnvelope(
    val total: Int = 0,
    val truncated: Boolean = false,
    val index: List<JsonArray> = emptyList(),
    val cards: List<EventDto> = emptyList()
) {
    fun domain() = DiscoveryPage(
        // Зіпсований кортеж — це одна відсутня подія, а не порожня мапа: рядок, який ми не
        // розібрали, просто не існує для цього екрана.
        index = index.mapNotNull { it.indexEntry() },
        total = total,
        truncated = truncated,
        cards = cards.map { it.domain() }
    )
}

/** Позиції в кортежі індексу. Порядок той самий, що в `jsonb_build_array` міграції. */
private object Column {
    const val ID = 0
    const val LATITUDE = 1
    const val LONGITUDE = 2
    const val CATEGORY = 3
    const val STARTS_AT = 4
    const val TIME_ZONE = 5
    const val TITLE = 6
    const val ORIGIN = 7
    const val SOURCE = 8
    const val CAPACITY = 9
    const val ATTENDEE_COUNT = 10
    const val WIDTH = 11
}

private fun JsonArray.indexEntry(): EventIndexEntry? {
    if (size < Column.WIDTH) return null
    val id = text(Column.ID) ?: return null
    val latitude = number(Column.LATITUDE) ?: return null
    val longitude = number(Column.LONGITUDE) ?: return null
    return EventIndexEntry(
        id = id,
        latitude = latitude,
        longitude = longitude,
        category = text(Column.CATEGORY).orEmpty(),
        startsAt = text(Column.STARTS_AT).orEmpty(),
        timeZone = text(Column.TIME_ZONE).orEmpty(),
        title = text(Column.TITLE).orEmpty(),
        origin = text(Column.ORIGIN).orEmpty(),
        source = text(Column.SOURCE),
        capacity = int(Column.CAPACITY),
        attendeeCount = int(Column.ATTENDEE_COUNT) ?: 0
    )
}

private fun JsonArray.at(position: Int) = getOrNull(position)?.takeIf { it != JsonNull } as? JsonPrimitive
private fun JsonArray.text(position: Int) = at(position)?.contentOrNull
private fun JsonArray.number(position: Int) = at(position)?.doubleOrNull
private fun JsonArray.int(position: Int) = at(position)?.intOrNull
