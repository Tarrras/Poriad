package app.poruch.data

import app.poruch.domain.Event
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName

@Serializable
internal data class EventDto(
    val id: String, val title: String, val description: String, val category: String,
    val city: String, val address: String,
    @SerialName("organizer_id") val organizerId: String,
    @SerialName("organizer_name") val organizerName: String = "Організатор",
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String,
    @SerialName("time_zone") val timeZone: String,
    val status: String, val latitude: Double, val longitude: Double, val capacity: Int,
    @SerialName("attendee_count") val attendeeCount: Int = 0,
    val joined: Boolean = false,
    @SerialName("image_url") val imageUrl: String? = null
) {
    fun domain() = Event(id,title,description,category,city,address,organizerId,organizerName,startsAt,endsAt,timeZone,status,latitude,longitude,capacity,attendeeCount,joined,imageUrl)
}
