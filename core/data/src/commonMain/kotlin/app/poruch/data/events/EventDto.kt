package app.poruch.data.events

import app.poruch.domain.Artist
import app.poruch.domain.ArtistHit
import app.poruch.domain.ArtistRadar
import app.poruch.domain.PopularArtist
import app.poruch.domain.RadarCity
import app.poruch.domain.RadarEvent
import app.poruch.domain.ArtistKind
import app.poruch.domain.ArtistRole
import app.poruch.domain.EventCategory
import app.poruch.domain.CompanionCard
import app.poruch.domain.CompanionParent
import app.poruch.domain.CompanyPerson
import app.poruch.domain.CompanyTeaser
import app.poruch.domain.District
import app.poruch.domain.Event
import app.poruch.domain.EventOrigin
import app.poruch.domain.EventStatus
import app.poruch.domain.Follow
import app.poruch.domain.FollowKind
import app.poruch.domain.Gathering
import app.poruch.domain.ImportStatus
import app.poruch.domain.Listing
import app.poruch.domain.ListingState
import app.poruch.domain.Offer
import app.poruch.domain.Membership
import app.poruch.domain.PendingMeet
import app.poruch.domain.Place
import app.poruch.domain.Curfew
import app.poruch.domain.EventSafety
import app.poruch.domain.Shelter
import app.poruch.domain.ShelterKind
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
    /** Речення «що це» (20261109120000); лише в картках афіші. */
    val blurb: String? = null,
    /** Опис, що чіпляє (20261111120000); лише в картках афіші. */
    val pitch: String? = null,
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
    val membership: String = Membership.NONE.key,
    // Старіша база без міграції імпорту віддає все як спільнотне, чим воно там і є.
    val origin: String = EventOrigin.COMMUNITY.key,
    @SerialName("source_name") val sourceName: String? = null,
    @SerialName("canonical_url") val canonicalUrl: String? = null,
    @SerialName("import_status") val importStatus: String? = null,
    @SerialName("price_min") val priceMin: Double? = null,
    @SerialName("is_free") val isFree: Boolean? = null,
    // Лише для організатора й підтверджених: решті сервер віддає null. Картки з `discover_events` його не несуть.
    @SerialName("contact_url") val contactUrl: String? = null,
    // Лише афіша (міграція 20260925120000). `event_details` і кеш до неї поля не несуть.
    @SerialName("place_id") val placeId: String? = null,
    @SerialName("place_name") val placeName: String? = null,
    // Лише супутник (міграція 20260928140000). Картки з `discover_events` їх не несуть — лише `event_details`.
    @SerialName("companion_of") val companionOf: String? = null,
    @SerialName("companion_of_title") val companionOfTitle: String? = null,
    // R7а, міграція 20261029120000: питання до організатора збору й час афіші. Старий сервер їх не знає.
    @SerialName("companion_of_starts_at") val companionOfStartsAt: String? = null,
    @SerialName("meet_proposed") val meetProposed: String? = null,
    @SerialName("meet_decide_by") val meetDecideBy: String? = null,
    // Міграція 20261002120000. `jsonb_strip_nulls` прибирає поле, коли артистів нема, а старий сервер його не знає.
    val artists: List<ArtistDto> = emptyList(),
    // Лише афіша, міграція 20261026120000 (docs/event-offers.md, фаза 4). Старий сервер і кеш їх не несуть.
    val state: String? = null,
    @SerialName("previous_starts_at") val previousStartsAt: String? = null,
    @SerialName("checked_at") val checkedAt: String? = null,
    val offers: List<OfferDto> = emptyList()
) {
    fun domain() = Event(
        id = id, title = title, description = description, category = EventCategory.fromKey(category),
        city = city, address = address,
        startsAt = startsAt, endsAt = endsAt, timeZone = timeZone, status = EventStatus.fromKey(status),
        latitude = latitude, longitude = longitude, imageUrl = imageUrl,
        gathering = gathering(), listing = listing(),
        artists = artists.map { it.domain() }, blurb = blurb, pitch = pitch
    )

    /**
     * Кімната лише для `origin = 'community'`, де сервер гарантує організатора й місткість
     * (`events_community_has_*_ck`). Без них рядок зіпсований: віддаємо подію без дій, а не вигадуємо місткість.
     */
    private fun gathering(): Gathering? {
        if (EventOrigin.fromKey(origin) != EventOrigin.COMMUNITY) return null
        return Gathering(
            organizerId = organizerId ?: return null,
            organizerName = organizerName,
            capacity = capacity ?: return null,
            attendeeCount = attendeeCount,
            joined = joined,
            membership = Membership.fromKey(membership),
            approvalRequired = approvalRequired,
            minAge = minAge,
            maxAge = maxAge,
            contactUrl = contactUrl,
            companionOf = companionOf?.let { CompanionParent(it, companionOfTitle.orEmpty(), companionOfStartsAt) },
            pendingMeet = meetProposed?.let { proposed -> meetDecideBy?.let { PendingMeet(proposed, it) } }
        )
    }

    /**
     * Назва джерела обов'язкова (docs/event-ingestion.md §8). Запасний варіант — `organizer_name`:
     * проєкція робить `coalesce(profile, source)`, тож це те саме значення з іншої колонки.
     */
    private fun listing(): Listing? {
        if (EventOrigin.fromKey(origin) == EventOrigin.COMMUNITY) return null
        val status = ImportStatus.fromKey(importStatus)
        val state = ListingState.fromKey(state) ?: ListingState.of(status)
        return Listing(
            sourceName = sourceName?.takeIf { it.isNotBlank() } ?: organizerName,
            canonicalUrl = canonicalUrl,
            priceMin = priceMin,
            isFree = isFree,
            status = status,
            placeId = placeId,
            placeName = placeName,
            state = state,
            previousStartsAt = previousStartsAt.takeIf { state == ListingState.SCHEDULED },
            checkedAt = checkedAt,
            offers = offers.mapNotNull { it.domain() }
        )
    }
}

/** Продавець з `offers`. Без назви — не показуємо: атрибуція обов'язкова (§8). */
@Serializable
internal data class OfferDto(
    val source: String? = null,
    val url: String? = null,
    @SerialName("price_min") val priceMin: Double? = null,
    @SerialName("is_free") val isFree: Boolean? = null,
    val live: Boolean = true,
    /** Що сторінка продавця каже про цей сеанс: `cancelled` / `postponed`. Інше — не показуємо. */
    val says: String? = null
) {
    fun domain() = source?.takeIf { it.isNotBlank() }?.let {
        Offer(
            it, url?.takeIf { u -> u.startsWith("https://") }, priceMin, isFree, live,
            ListingState.fromKey(says)?.takeIf { s -> s == ListingState.CANCELLED || s == ListingState.POSTPONED }
        )
    }
}

/** Відповідь `event_safety`. */
@Serializable
internal data class SafetyDto(val shelters: List<ShelterDto> = emptyList(), val curfew: CurfewDto? = null) {
    fun domain() = EventSafety(shelters.map { it.domain() }, curfew?.let { Curfew(it.starts, it.ends) })
}

@Serializable
internal data class ShelterDto(
    val kind: String? = null,
    val address: String,
    @SerialName("distance_m") val distanceMeters: Int,
    val accessible: Boolean = false,
    val hours: String? = null,
    val latitude: Double,
    val longitude: Double
) {
    fun domain() = Shelter(ShelterKind.fromKey(kind), address, distanceMeters, accessible, hours, latitude, longitude)
}

@Serializable
internal data class CurfewDto(val starts: String, val ends: String)

/** Рядок `companions`: картка супутника без імен. */
@Serializable
internal data class CompanionDto(
    val id: String,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("time_zone") val timeZone: String,
    @SerialName("meet_note") val meetNote: String? = null,
    val capacity: Int,
    @SerialName("attendee_count") val attendeeCount: Int = 0,
    val membership: String = Membership.NONE.key,
    val mine: Boolean = false
) {
    fun domain() = CompanionCard(id, startsAt, timeZone, meetNote, capacity, attendeeCount, Membership.fromKey(membership), mine)
}

/** Рядок `company_teaser`: тизер «Хочу піти з компанією» без імен. */
@Serializable
internal data class CompanyTeaserDto(
    val count: Int = 0,
    val shared: List<String> = emptyList(),
    val mine: Boolean = false
) {
    fun domain() = CompanyTeaser(count, shared.categories(), mine)
}

/** Рядок `company_people`: людина з наміром на ту саму афішу. */
@Serializable
internal data class CompanyPersonDto(
    @SerialName("user_id") val userId: String,
    val name: String = "",
    @SerialName("avatar_url") val avatarUrl: String? = null,
    val bio: String? = null,
    val instagram: String? = null,
    val shared: List<String> = emptyList(),
    val attended: Int = 0,
    @SerialName("said_yes") val saidYes: Boolean = false,
    @SerialName("they_said_yes") val theySaidYes: Boolean = false,
    @SerialName("companion_id") val companionId: String? = null
) {
    fun domain() = CompanyPerson(userId, name, avatarUrl, bio, instagram, shared.categories(), attended,
        saidYes, theySaidYes, companionId)
}

/** Ключі категорій з сервера; невідомі (новіший сервер) — мимо. */
private fun List<String>.categories() = map { EventCategory.fromKey(it) }.filter { it != EventCategory.UNKNOWN }

/** Артист у картці події. `kind` буває відсутній: сервер не завжди знає вид. */
@Serializable
internal data class ArtistDto(
    val id: String,
    val name: String = "",
    val kind: String? = null,
    val role: String? = null
) {
    fun domain() = Artist(id, name, ArtistKind.fromKey(kind), ArtistRole.fromKey(role))
}

/** Елемент відповіді `artist_radar` (docs/artist-radar.md). */
@Serializable
internal data class ArtistRadarDto(
    val id: String,
    val name: String = "",
    val kind: String? = null,
    val next: RadarEventDto? = null,
    @SerialName("in_city") val inCity: Int = 0,
    val elsewhere: List<RadarCityDto> = emptyList()
) {
    fun domain() = ArtistRadar(id, name, ArtistKind.fromKey(kind), next?.domain(), inCity, elsewhere.map { it.domain() })
}

@Serializable
internal data class RadarEventDto(
    val id: String,
    val title: String = "",
    @SerialName("starts_at") val startsAt: String,
    @SerialName("time_zone") val timeZone: String = "Europe/Kyiv",
    val category: String? = null
) {
    fun domain() = RadarEvent(id, title, startsAt, timeZone, EventCategory.fromKey(category))
}

@Serializable
internal data class RadarCityDto(val city: String, @SerialName("starts_at") val startsAt: String) {
    fun domain() = RadarCity(city, startsAt)
}

/** Елемент відповіді `popular_artists`. */
@Serializable
internal data class PopularArtistDto(
    val id: String,
    val name: String = "",
    val kind: String? = null,
    val upcoming: Int = 0,
    @SerialName("first_at") val firstAt: String? = null
) {
    fun domain() = PopularArtist(id, name, ArtistKind.fromKey(kind), upcoming, firstAt)
}

/** Елемент відповіді `search_artists`. */
@Serializable
internal data class ArtistHitDto(
    val id: String,
    val name: String = "",
    val kind: String? = null,
    val upcoming: Int = 0
) {
    fun domain() = ArtistHit(id, name, ArtistKind.fromKey(kind), upcoming)
}

/** Елемент відповіді `city_districts`. Кільця — `[[lon, lat], …]`, у домені — пласкі `lon, lat…`. */
@Serializable
internal data class DistrictDto(
    val id: Long,
    val name: String,
    val former: String? = null,
    val aliases: List<String> = emptyList(),
    /** Місцевість: радіус кола в метрах. Нема — район. */
    val radius: Int? = null,
    val rings: List<List<List<Double>>> = emptyList()
) {
    fun domain(city: String) = District(
        id, city, name, former, aliases,
        rings.map { ring -> DoubleArray(ring.size * 2) { i -> ring[i / 2][i % 2] } },
        radiusM = radius
    )
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

/** Елемент відповіді `my_follows`: заклад чи організатор з тим, що потрібно списку. */
@Serializable
internal data class FollowDto(
    val kind: String,
    val id: String,
    val name: String = "",
    val city: String? = null,
    val address: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("artist_kind") val artistKind: String? = null,
    val upcoming: Int = 0,
    /** Нуль сервер не віддає. */
    val fresh: Int = 0
) {
    /** Невідомий рід (сервер новіший за застосунок) — не рядок списку, а відсутня підписка. */
    fun domain() = FollowKind.fromKey(kind)?.let {
        Follow(it, id, name, city.orEmpty(), address.orEmpty(), latitude, longitude, avatarUrl, upcoming, ArtistKind.fromKey(artistKind), fresh)
    }
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
