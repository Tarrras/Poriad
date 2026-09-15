package app.poruch.data.events

import app.poruch.domain.Event
import app.poruch.domain.EventOrigin
import app.poruch.domain.Gathering
import app.poruch.domain.ImportStatus
import app.poruch.domain.Listing
import app.poruch.domain.Membership
import app.poruch.domain.SafetyRules
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName

/**
 * Рядок `public.event_result` з RPC. Проєкція плоска, тож розділення на [Gathering] і [Listing]
 * відбувається тут один раз, і далі екрани `origin` не бачать.
 */
@Serializable
internal data class EventDto(
    val id: String, val title: String,
    /** Порожній опис сервер не надсилає (`jsonb_strip_nulls`), тому default, а не обов'язкове поле. */
    val description: String = "",
    val category: String,
    val city: String, val address: String,
    // Null для афіші. Не-nullable поле валило розбір усієї відповіді через один рядок.
    @SerialName("organizer_id") val organizerId: String? = null,
    // Порожній, поки в організатора нема публічного профілю. Заміну підбирає UI.
    @SerialName("organizer_name") val organizerName: String = "",
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String,
    @SerialName("time_zone") val timeZone: String,
    val status: String, val latitude: Double, val longitude: Double,
    // Null для афіші (з міграції 20260907150000). Старий сервер віддає одиницю, вона нікуди не потрапить.
    val capacity: Int? = null,
    @SerialName("attendee_count") val attendeeCount: Int = 0,
    val joined: Boolean = false,
    @SerialName("image_url") val imageUrl: String? = null,
    // Default тримає читабельним старий сервер і кеш до міграції безпеки: тоді діє мінімум платформи.
    @SerialName("min_age") val minAge: Int = SafetyRules.MIN_SIGNUP_AGE,
    @SerialName("max_age") val maxAge: Int? = null,
    @SerialName("approval_required") val approvalRequired: Boolean = false,
    val membership: String = Membership.NONE,
    // Старіша база без міграції імпорту віддає все як спільнотне, чим воно там і є.
    val origin: String = EventOrigin.COMMUNITY,
    @SerialName("source_name") val sourceName: String? = null,
    @SerialName("canonical_url") val canonicalUrl: String? = null,
    @SerialName("import_status") val importStatus: String? = null,
    @SerialName("price_min") val priceMin: Double? = null,
    @SerialName("is_free") val isFree: Boolean? = null
) {
    fun domain() = Event(
        id = id, title = title, description = description, category = category,
        city = city, address = address,
        startsAt = startsAt, endsAt = endsAt, timeZone = timeZone, status = status,
        latitude = latitude, longitude = longitude, imageUrl = imageUrl,
        gathering = gathering(), listing = listing()
    )

    /**
     * Кімната лише для `origin = 'community'`, де сервер гарантує організатора й місткість
     * (`events_community_has_*_ck`). Без них рядок зіпсований: віддаємо подію без дій, а не вигадуємо місткість.
     */
    private fun gathering(): Gathering? {
        if (origin != EventOrigin.COMMUNITY) return null
        return Gathering(
            organizerId = organizerId ?: return null,
            organizerName = organizerName,
            capacity = capacity ?: return null,
            attendeeCount = attendeeCount,
            joined = joined,
            membership = membership,
            approvalRequired = approvalRequired,
            minAge = minAge,
            maxAge = maxAge
        )
    }

    /**
     * Назва джерела обов'язкова (docs/event-ingestion.md §8). Запасний варіант — `organizer_name`:
     * проєкція робить `coalesce(profile, source)`, тож це те саме значення з іншої колонки.
     */
    private fun listing(): Listing? {
        if (origin == EventOrigin.COMMUNITY) return null
        return Listing(
            sourceName = sourceName?.takeIf { it.isNotBlank() } ?: organizerName,
            canonicalUrl = canonicalUrl,
            priceMin = priceMin,
            isFree = isFree,
            status = importStatus ?: ImportStatus.LIVE
        )
    }
}

@Serializable
internal data class AttendeeDto(
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("avatar_url") val avatarUrl: String? = null
) {
    fun domain() = app.poruch.domain.Attendee(userId, displayName, avatarUrl)
}
