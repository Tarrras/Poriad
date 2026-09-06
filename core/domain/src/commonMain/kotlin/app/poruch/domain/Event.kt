package app.poruch.domain

import kotlin.time.Instant
import kotlinx.datetime.TimeZone

/** Immutable UI-independent event model. Timestamps are ISO-8601 UTC instants. */
data class Event(
    val id: String, val title: String, val description: String, val category: String,
    val city: String, val address: String, val organizerId: String, val organizerName: String,
    val startsAt: String, val endsAt: String, val timeZone: String, val status: String,
    val latitude: Double, val longitude: Double, val capacity: Int, val attendeeCount: Int,
    val joined: Boolean, val imageUrl: String?
) {
    val isCancelled get() = status == EventStatus.CANCELLED
    val isPublished get() = status == EventStatus.PUBLISHED
    val seatsLeft get() = (capacity - attendeeCount).coerceAtLeast(0)
    val isFull get() = seatsLeft == 0
}

/** Event lifecycle, as the `events.status` column spells it. */
object EventStatus {
    const val PUBLISHED = "published"
    const val CANCELLED = "cancelled"
}
data class Attendee(val userId: String, val name: String, val avatarUrl: String?)
data class CityResult(val name: String, val latitude: Double, val longitude: Double)
data class EventDraft(
    val title: String, val description: String, val category: String, val city: String,
    val address: String, val latitude: Double, val longitude: Double, val startsAt: String,
    val endsAt: String, val timeZone: String, val capacity: Int, val imageUrl: String? = null
) {
    fun validate(now: String): List<DraftField> = buildList {
        if (title.trim().length !in EventRules.titleLength) add(DraftField.TITLE)
        if (description.trim().length !in EventRules.descriptionLength) add(DraftField.DESCRIPTION)
        if (!EventRules.isCategory(category)) add(DraftField.CATEGORY)
        if (city.isBlank() || address.isBlank()) add(DraftField.ADDRESS)
        if (!latitude.isFinite() || !longitude.isFinite() || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) add(DraftField.LOCATION)
        if (capacity !in EventRules.capacity) add(DraftField.CAPACITY)
        val start = runCatching { Instant.parse(startsAt) }.getOrNull()
        val end = runCatching { Instant.parse(endsAt) }.getOrNull()
        val current = runCatching { Instant.parse(now) }.getOrNull()
        if (start == null || current == null || start <= current) add(DraftField.STARTS_AT)
        if (end == null || start == null || end <= start) add(DraftField.ENDS_AT)
        if (runCatching { TimeZone.of(timeZone) }.isFailure) add(DraftField.TIME_ZONE)
        if (imageUrl != null && !imageUrl.startsWith("https://")) add(DraftField.IMAGE_URL)
    }
}
