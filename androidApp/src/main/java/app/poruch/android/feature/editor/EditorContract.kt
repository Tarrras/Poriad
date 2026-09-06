package app.poruch.android.feature.editor

import app.poruch.domain.EventDraft
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** The form as the reader typed it: strings, because a half-typed number is not a number yet. */
data class EditorForm(
    val title: String = "",
    val description: String = "",
    val category: String = DEFAULT_CATEGORY,
    val city: String = "",
    val address: String = "",
    val latitude: String = "",
    val longitude: String = "",
    val timeZone: String = ZoneId.systemDefault().id,
    val starts: String = "",
    val ends: String = "",
    val capacity: String = DEFAULT_CAPACITY
) {
    /** Null until every field parses; the publish button follows this, so it can never lie. */
    fun toDraft(imageUrl: String?): EventDraft? = runCatching {
        val zone = ZoneId.of(timeZone)
        EventDraft(
            title = title.trim(), description = description.trim(), category = category,
            city = city.trim(), address = address.trim(),
            latitude = latitude.toDouble(), longitude = longitude.toDouble(),
            startsAt = LocalDateTime.parse(starts, LOCAL_FORMAT).atZone(zone).toInstant().toString(),
            endsAt = LocalDateTime.parse(ends, LOCAL_FORMAT).atZone(zone).toInstant().toString(),
            timeZone = timeZone, capacity = capacity.toInt(), imageUrl = imageUrl
        )
    }.getOrNull()

    companion object {
        const val DEFAULT_CATEGORY = "social"
        const val DEFAULT_CAPACITY = "20"
        /** How dates are shown and stored in the draft. Local wall time, never UTC. */
        val LOCAL_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
    }
}

enum class EditorStep { ABOUT, PLACE, SCHEDULE;
    val isLast get() = this == SCHEDULE
    fun next() = entries.getOrElse(ordinal + 1) { this }
    fun previous() = entries.getOrElse(ordinal - 1) { this }
}

data class EditorState(
    val editing: Boolean = false,
    val step: EditorStep = EditorStep.ABOUT,
    val form: EditorForm = EditorForm(),
    val mutating: Boolean = false,
    /** Where the map opens before the reader drops a pin. */
    val mapLatitude: Double = 0.0,
    val mapLongitude: Double = 0.0,
    val picker: PickerRequest? = null
) {
    /** Each step guards only its own fields, so «Далі» never blocks on a later one. */
    val canAdvance: Boolean
        get() = when (step) {
            EditorStep.ABOUT -> form.title.isNotBlank()
            EditorStep.PLACE -> form.city.isNotBlank() && form.address.isNotBlank() &&
                form.latitude.toDoubleOrNull() != null && form.longitude.toDoubleOrNull() != null
            EditorStep.SCHEDULE -> form.toDraft(null) != null
        }
}

/** Which date field the picker is currently editing. */
enum class PickerRequest { STARTS, ENDS }

sealed interface EditorIntent {
    data class Edit(val change: EditorForm.() -> EditorForm) : EditorIntent
    data class PickPoint(val latitude: Double, val longitude: Double) : EditorIntent
    data object Next : EditorIntent
    data object Back : EditorIntent
    data object Submit : EditorIntent
    data class ShowPicker(val request: PickerRequest?) : EditorIntent
    data class SetDateTime(val request: PickerRequest, val value: LocalDateTime) : EditorIntent
}

sealed interface EditorEffect {
    data object Close : EditorEffect
}
