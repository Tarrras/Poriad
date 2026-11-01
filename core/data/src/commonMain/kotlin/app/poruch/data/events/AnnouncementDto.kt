package app.poruch.data.events

import app.poruch.domain.AnnouncementFill
import app.poruch.domain.ContactRules
import app.poruch.domain.EventCategory
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toInstant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Відповідь `parse-announcement` (`supabase/functions/parse-announcement/announce.ts`): назва й опис завжди, решта — лише
 * якщо є в тексті. Час — місцевий `YYYY-MM-DDTHH:MM` у поясі форми; тут він стає ISO в UTC, як у чернетці.
 */
@Serializable
internal data class AnnouncementDto(
    val title: String,
    val description: String,
    val category: String? = null,
    @SerialName("starts_at") val startsAt: String? = null,
    @SerialName("ends_at") val endsAt: String? = null,
    val place: String? = null,
    val capacity: Int? = null,
    @SerialName("min_age") val minAge: Int? = null,
    @SerialName("contact_url") val contactUrl: String? = null
) {
    fun domain(timeZone: String): AnnouncementFill {
        val zone = runCatching { TimeZone.of(timeZone) }.getOrDefault(TimeZone.currentSystemDefault())
        fun instant(local: String?) = local?.let { runCatching { LocalDateTime.parse(it).toInstant(zone).toString() }.getOrNull() }
        val start = instant(startsAt)
        return AnnouncementFill(
            title = title.trim().takeIf { it.isNotEmpty() },
            description = description.trim().takeIf { it.isNotEmpty() },
            category = EventCategory.fromKey(category).takeIf { it != EventCategory.UNKNOWN },
            startsAt = start,
            // Кінець без початку нічого не каже.
            endsAt = instant(endsAt).takeIf { start != null },
            address = place?.trim()?.takeIf { it.isNotEmpty() },
            capacity = capacity,
            minAge = minAge,
            contactUrl = ContactRules.normalize(contactUrl)?.takeIf { ContactRules.isContactUrl(it) }
        )
    }
}
