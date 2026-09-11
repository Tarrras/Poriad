package app.poruch.android.feature.editor

import app.poruch.domain.EventDraft
import app.poruch.domain.PlaceResult
import app.poruch.domain.SafetyRules
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
    val capacity: String = DEFAULT_CAPACITY,
    val minAge: String = DEFAULT_MIN_AGE,
    /** Empty means «no upper bound», which is the ordinary case. */
    val maxAge: String = "",
    val approvalRequired: Boolean = false
) {
    /**
     * Крапка зустрічі, якщо вона вже є.
     *
     * Питаємо самі координати, а не окремий прапорець: прапорець умів розійтися з ними — подія,
     * відкрита на редагування, приходила з координатами й без нього.
     */
    val point: Pair<Double, Double>?
        get() = latitude.toDoubleOrNull()?.let { lat -> longitude.toDoubleOrNull()?.let { lon -> lat to lon } }

    /** Null until every field parses; the publish button follows this, so it can never lie. */
    fun toDraft(imageUrl: String?): EventDraft? = runCatching {
        val zone = ZoneId.of(timeZone)
        EventDraft(
            title = title.trim(), description = description.trim(), category = category,
            city = city.trim(), address = address.trim(),
            latitude = latitude.toDouble(), longitude = longitude.toDouble(),
            startsAt = LocalDateTime.parse(starts, LOCAL_FORMAT).atZone(zone).toInstant().toString(),
            endsAt = LocalDateTime.parse(ends, LOCAL_FORMAT).atZone(zone).toInstant().toString(),
            timeZone = timeZone, capacity = capacity.toInt(), imageUrl = imageUrl,
            minAge = minAge.toInt(), maxAge = maxAge.trim().takeIf { it.isNotEmpty() }?.toInt(),
            approvalRequired = approvalRequired
        ).also { if (!SafetyRules.isAgeLimit(it.minAge, it.maxAge)) error("age limits") }
    }.getOrNull()

    companion object {
        const val DEFAULT_CATEGORY = "social"
        const val DEFAULT_CAPACITY = "20"
        val DEFAULT_MIN_AGE = SafetyRules.MIN_SIGNUP_AGE.toString()
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
    val picker: PickerRequest? = null,
    /** Пояс визначено за місцем події, а не взято з пристрою. Різні ступені впевненості. */
    val timeZoneFromPlace: Boolean = false,
    /**
     * Адреси, що збігаються з набраним.
     *
     * Координати — не те, що людина знає про місце зустрічі. Вона знає вулицю й будинок, тож
     * набирає їх, а крапку ставить застосунок. Мапа лишається для випадків, яких немає в жодному
     * довіднику: «біля третього дерева» чи новобудова без адреси.
     */
    val addressSuggestions: List<PlaceResult> = emptyList(),
    /**
     * Відкрито екран вибору точки.
     *
     * Міні-мапа в анкеті нічого не обирає — вона показує вибране. Обирати на ній означало б
     * ставити крапку в клаптику 260 dp, де половину екрана затуляє палець.
     */
    val pickingPoint: Boolean = false,
    /**
     * Адреса під ціллю на екрані вибору. Порожня, доки відповідь у дорозі.
     *
     * Крапка на мапі — це координати, а людина обирає місце. Без назви вулиці під ціллю вибір
     * лишався б здогадом: схоже на той двір чи вже сусідній.
     */
    val aimAddress: String = ""
) {
    val point get() = form.point
    val pointChosen get() = point != null

    /** Each step guards only its own fields, so «Далі» never blocks on a later one. */
    val canAdvance: Boolean
        get() = when (step) {
            EditorStep.ABOUT -> form.title.isNotBlank()
            EditorStep.PLACE -> form.city.isNotBlank() && form.address.isNotBlank() && point != null
            EditorStep.SCHEDULE -> form.toDraft(null) != null
        }
}

/** Which date field the picker is currently editing. */
enum class PickerRequest { STARTS, ENDS }

sealed interface EditorIntent {
    data class Edit(val change: EditorForm.() -> EditorForm) : EditorIntent
    data class PickPoint(val latitude: Double, val longitude: Double) : EditorIntent
    /** Відкрити й закрити повноекранну мапу вибору. */
    data class ShowPointPicker(val open: Boolean) : EditorIntent
    /** Ціль зупинилась ось тут — спитати, що це за адреса. */
    data class AimAt(val latitude: Double, val longitude: Double) : EditorIntent
    /** Обрана підказка адреси: разом із нею приходить і крапка. */
    data class PickAddress(val place: PlaceResult) : EditorIntent
    data object Next : EditorIntent
    data object Back : EditorIntent
    data object Submit : EditorIntent
    data class ShowPicker(val request: PickerRequest?) : EditorIntent
    data class SetDateTime(val request: PickerRequest, val value: LocalDateTime) : EditorIntent
}

sealed interface EditorEffect {
    data object Close : EditorEffect
}
