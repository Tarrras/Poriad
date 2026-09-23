package app.poruch.android.feature.editor

import app.poruch.domain.AppError
import app.poruch.domain.ContactRules
import app.poruch.domain.DraftField
import app.poruch.domain.EventDraft
import app.poruch.domain.PlaceResult
import app.poruch.domain.SafetyRules
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Форма, як її набрали: рядки, бо недонабране число — ще не число. */
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
    /** Порожньо — без верхньої межі. */
    val maxAge: String = "",
    val approvalRequired: Boolean = false,
    /** Чат учасників. Порожньо — без чату. */
    val contactUrl: String = ""
) {
    /** Крапка зустрічі, якщо є. З самих координат, а не з прапорця: прапорець розходився з ними. */
    val point: Pair<Double, Double>?
        get() = latitude.toDoubleOrNull()?.let { lat -> longitude.toDoubleOrNull()?.let { lon -> lat to lon } }

    /** Null, поки не розбирається кожне поле. Кнопка публікації дивиться сюди. */
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
            approvalRequired = approvalRequired, contactUrl = ContactRules.normalize(contactUrl)
        ).also {
            if (!SafetyRules.isAgeLimit(it.minAge, it.maxAge)) error("age limits")
            if (!ContactRules.isContactUrl(it.contactUrl)) error("contact url")
        }
    }.getOrNull()

    /**
     * Що не так у формі, за тими самими правилами, що й [EventDraft.validate]: недонабране число
     * чи дата стають явно хибним значенням, і доменна перевірка називає поле.
     */
    fun problems(now: Instant = Instant.now()): List<DraftField> {
        val zone = runCatching { ZoneId.of(timeZone) }.getOrNull()
        fun instant(value: String) = runCatching { LocalDateTime.parse(value, LOCAL_FORMAT).atZone(zone).toInstant().toString() }
            .getOrDefault("")
        return EventDraft(
            title = title, description = description, category = category, city = city, address = address,
            latitude = latitude.toDoubleOrNull() ?: Double.NaN, longitude = longitude.toDoubleOrNull() ?: Double.NaN,
            startsAt = instant(starts), endsAt = instant(ends), timeZone = timeZone,
            capacity = capacity.toIntOrNull() ?: 0, minAge = minAge.toIntOrNull() ?: 0,
            maxAge = maxAge.trim().takeIf { it.isNotEmpty() }?.let { it.toIntOrNull() ?: -1 },
            approvalRequired = approvalRequired, contactUrl = ContactRules.normalize(contactUrl)
        ).validate(now.toString())
    }

    companion object {
        const val DEFAULT_CATEGORY = "social"
        const val DEFAULT_CAPACITY = "20"
        val DEFAULT_MIN_AGE = SafetyRules.MIN_SIGNUP_AGE.toString()
        /** Формат дат у чернетці: локальний час, не UTC. */
        val LOCAL_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
    }
}

enum class EditorStep(
    /** Поля, які людина вводить на цьому кроці: їхні помилки тримають «Далі». */
    val fields: Set<DraftField>
) {
    ABOUT(setOf(DraftField.TITLE, DraftField.DESCRIPTION, DraftField.CATEGORY)),
    PLACE(setOf(DraftField.ADDRESS, DraftField.LOCATION)),
    // Фото додають після публікації, тож IMAGE_URL тут лише щоб кожне поле мало свій крок.
    SCHEDULE(
        setOf(
            DraftField.STARTS_AT, DraftField.ENDS_AT, DraftField.TIME_ZONE, DraftField.CAPACITY,
            DraftField.AGE_LIMITS, DraftField.CONTACT_URL, DraftField.IMAGE_URL
        )
    );

    val isLast get() = this == SCHEDULE
    fun next() = entries.getOrElse(ordinal + 1) { this }
    fun previous() = entries.getOrElse(ordinal - 1) { this }
}

data class EditorState(
    val editing: Boolean = false,
    val step: EditorStep = EditorStep.ABOUT,
    val form: EditorForm = EditorForm(),
    val mutating: Boolean = false,
    /** Де відкривається мапа до вибору крапки. */
    val mapLatitude: Double = 0.0,
    val mapLongitude: Double = 0.0,
    val picker: PickerRequest? = null,
    /** Пояс визначено за місцем події, а не взято з пристрою. */
    val timeZoneFromPlace: Boolean = false,
    /** Підказки адрес: людина набирає вулицю й будинок, крапку ставить застосунок. */
    val addressSuggestions: List<PlaceResult> = emptyList(),
    /** Відкрито повноекранний вибір точки: на міні-мапі 260 dp обирати незручно. */
    val pickingPoint: Boolean = false,
    /** Адреса під ціллю на екрані вибору. Порожня, поки відповідь у дорозі. */
    val aimAddress: String = "",
    /** «Далі» натиснули з помилками: тепер вони видні під полями, поки крок не зміниться. */
    val showProblems: Boolean = false,
    /** Публікацію відхилено: текст стоїть над кнопкою, а не зникає банером. */
    val failure: AppError? = null
) {
    val point get() = form.point
    val pointChosen get() = point != null

    /** Кожен крок перевіряє лише свої поля, тож «Далі» не блокується наступним. */
    val stepProblems: List<DraftField> get() = form.problems().filter { it in step.fields }
}

/** Яке поле дати зараз редагує пікер. */
enum class PickerRequest { STARTS, ENDS }

sealed interface EditorIntent {
    data class Edit(val change: EditorForm.() -> EditorForm) : EditorIntent
    data class PickPoint(val latitude: Double, val longitude: Double) : EditorIntent
    /** Відкрити й закрити повноекранну мапу вибору. */
    data class ShowPointPicker(val open: Boolean) : EditorIntent
    /** Ціль зупинилась: спитати адресу. */
    data class AimAt(val latitude: Double, val longitude: Double) : EditorIntent
    /** Обрана підказка адреси: разом із нею приходить і крапка. */
    data class PickAddress(val place: PlaceResult) : EditorIntent
    data object Next : EditorIntent
    data object Back : EditorIntent
    data object Submit : EditorIntent
    data class ShowPicker(val request: PickerRequest?) : EditorIntent
    data class SetDateTime(val request: PickerRequest, val value: LocalDateTime) : EditorIntent
    /** Відповідь системи на [EditorEffect.AskNotificationPermission]. */
    data class NotificationPermissionAnswered(val granted: Boolean) : EditorIntent
}

sealed interface EditorEffect {
    data object Close : EditorEffect
    data object AskNotificationPermission : EditorEffect
}
