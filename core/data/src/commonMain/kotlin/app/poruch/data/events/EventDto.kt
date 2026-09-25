package app.poruch.data.events

import app.poruch.domain.Event
import app.poruch.domain.EventOrigin
import app.poruch.domain.Gathering
import app.poruch.domain.ImportStatus
import app.poruch.domain.Listing
import app.poruch.domain.Membership
import app.poruch.domain.Place
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
    @SerialName("is_free") val isFree: Boolean? = null,
    // Лише для організатора й підтверджених: решті сервер віддає null. Картки з `discover_events` його не несуть.
    @SerialName("contact_url") val contactUrl: String? = null,
    // Лише афіша (міграція 20260925120000). `event_details` і кеш до неї поля не несуть.
    @SerialName("place_id") val placeId: String? = null,
    @SerialName("place_name") val placeName: String? = null
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
            maxAge = maxAge,
            contactUrl = contactUrl
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
            status = importStatus ?: ImportStatus.LIVE,
            placeId = placeId,
            placeName = placeName
        )
    }
}

/** Елемент відповіді `search_places`. */
@Serializable
internal data class PlaceDto(
    val id: String,
    val name: String,
    val city: String = "",
    val address: String = "",
    val latitude: Double,
    val longitude: Double,
    val upcoming: Int = 0
) {
    fun domain() = Place(id, name, city, address, latitude, longitude, upcoming)
}

/** Рядок `public.message_result` з `event_messages`. */
@Serializable
internal data class ChatMessageDto(
    val id: String,
    @SerialName("event_id") val eventId: String,
    @SerialName("author_id") val authorId: String,
    @SerialName("author_name") val authorName: String = "",
    @SerialName("avatar_url") val avatarUrl: String? = null,
    val body: String = "",
    @SerialName("created_at") val createdAt: String = ""
) {
    fun domain() = app.poruch.domain.ChatMessage(id, eventId, authorId, authorName, avatarUrl, body, createdAt)
}

/** Рядок `public.chat_unread_result` з `my_chat_unread`. */
@Serializable
internal data class ChatUnreadDto(
    @SerialName("event_id") val eventId: String,
    @SerialName("event_title") val eventTitle: String = "",
    val unread: Int = 0,
    @SerialName("last_message_id") val lastMessageId: String,
    @SerialName("last_author_name") val lastAuthorName: String = "",
    @SerialName("last_body") val lastBody: String = "",
    @SerialName("last_at") val lastAt: String = ""
) {
    fun domain() = app.poruch.domain.ChatUnread(eventId, eventTitle, unread, lastMessageId, lastAuthorName, lastBody, lastAt)
}

/** Рядок `public.join_request_result` з `my_join_requests`. */
@Serializable
internal data class JoinRequestDto(
    @SerialName("event_id") val eventId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String = "",
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("requested_at") val requestedAt: String = ""
) {
    fun domain() = app.poruch.domain.JoinRequest(eventId, userId, displayName, avatarUrl, requestedAt)
}

@Serializable
internal data class AttendeeDto(
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("avatar_url") val avatarUrl: String? = null
) {
    fun domain() = app.poruch.domain.Attendee(userId, displayName, avatarUrl)
}
