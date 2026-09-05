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
)
data class CityResult(val name: String, val latitude: Double, val longitude: Double)
data class EventDraft(
    val title: String, val description: String, val category: String, val city: String,
    val address: String, val latitude: Double, val longitude: Double, val startsAt: String,
    val endsAt: String, val timeZone: String, val capacity: Int, val imageUrl: String? = null
) {
    fun validate(now: String): List<String> = buildList {
        if (title.trim().length !in 3..120) add("title")
        if (description.trim().length !in 10..5000) add("description")
        if (category !in setOf("music", "sport", "art", "food", "games", "outdoors", "social")) add("category")
        if (city.isBlank() || address.isBlank()) add("address")
        if (!latitude.isFinite() || !longitude.isFinite() || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) add("location")
        if (capacity !in 1..10000) add("capacity")
        val start = runCatching { Instant.parse(startsAt) }.getOrNull()
        val end = runCatching { Instant.parse(endsAt) }.getOrNull()
        val current = runCatching { Instant.parse(now) }.getOrNull()
        if (start == null || current == null || start <= current) add("startsAt")
        if (end == null || start == null || end <= start) add("endsAt")
        if (runCatching { TimeZone.of(timeZone) }.isFailure) add("timeZone")
        if (imageUrl != null && !imageUrl.startsWith("https://")) add("imageUrl")
    }
}
