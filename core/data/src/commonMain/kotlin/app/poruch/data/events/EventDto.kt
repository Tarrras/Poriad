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
 * Один рядок `public.event_result`, як його віддає RPC.
 *
 * Проєкція плоска — сервер не має композитних типів на кожну грань — тож розділення на кімнату й
 * оголошення відбувається тут, рівно один раз. Далі жоден екран уже не бачить `origin`: він бачить
 * або [Gathering], або [Listing], і не може випадково показати одне як інше.
 */
@Serializable
internal data class EventDto(
    val id: String, val title: String,
    /**
     * Порожній опис сервер не надсилає взагалі: `jsonb_strip_nulls` знімає його з 867 подій із
     * 1256. Тому значення за замовчуванням, а не обовʼязкове поле — інакше розбір падав би на
     * кожній другій афіші.
     */
    val description: String = "",
    val category: String,
    val city: String, val address: String,
    // Null для імпортованої афіші. Не-nullable поле тут валило розбір УСІЄЇ відповіді,
    // тож мапа порожніла через один такий рядок.
    @SerialName("organizer_id") val organizerId: String? = null,
    // Blank when the organizer has no public profile yet; naming the fallback is the UI's job.
    @SerialName("organizer_name") val organizerName: String = "",
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String,
    @SerialName("time_zone") val timeZone: String,
    val status: String, val latitude: Double, val longitude: Double,
    // Null для афіші, відколи 20260907150000 зняла `not null`. Старий сервер віддає тут вигадану
    // одиницю — вона нікуди не потрапить, бо для афіші кімната не будується взагалі.
    val capacity: Int? = null,
    @SerialName("attendee_count") val attendeeCount: Int = 0,
    val joined: Boolean = false,
    @SerialName("image_url") val imageUrl: String? = null,
    // Defaults keep an old server (or a cached row written before the safety migration) readable:
    // the app then shows an event with the platform floor, which is what such a row means.
    @SerialName("min_age") val minAge: Int = SafetyRules.MIN_SIGNUP_AGE,
    @SerialName("max_age") val maxAge: Int? = null,
    @SerialName("approval_required") val approvalRequired: Boolean = false,
    val membership: String = Membership.NONE,
    // Рід події. Сервер віддає його з міграції імпорту; збірка проти старішої бази бачить усе як
    // спільнотне — те, чим воно там і було.
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
     * Кімната будується лише там, де сервер обіцяє її частини: `events_community_has_organizer_ck`
     * і `events_community_has_capacity_ck` роблять обидва поля обов'язковими саме й тільки для
     * `origin = 'community'`. Якщо їх усе-таки немає — рядок зіпсований, і чесніше віддати подію
     * без дій, ніж домалювати місткість, якої ніхто не встановлював.
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
     * Назва джерела обов'язкова для показу (docs/event-ingestion.md §8). `organizer_name` уже
     * містить її — проєкція робить `coalesce(profile, source)` — тож запасний варіант тут не
     * вигадка, а те саме значення з іншої колонки.
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
