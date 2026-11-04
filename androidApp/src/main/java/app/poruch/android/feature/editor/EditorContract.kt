package app.poruch.android.feature.editor

import android.net.Uri
import app.poruch.domain.AnnouncementFill
import app.poruch.domain.DraftMedia
import app.poruch.domain.EventCategory
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
    val category: EventCategory = DEFAULT_CATEGORY,
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
    val contactUrl: String = "",
    /** Фото й відео в порядку показу, перше — обкладинка. Нові лежать на телефоні до публікації. */
    val media: List<DraftMedia> = emptyList(),
    /** Ціна входу, гривні (docs/organizers-1.5.md, 1.7). Порожньо — безкоштовно. */
    val price: String = ""
) {
    /** Крапка зустрічі, якщо є. З самих координат, а не з прапорця: прапорець розходився з ними. */
    val point: Pair<Double, Double>?
        get() = latitude.toDoubleOrNull()?.let { lat -> longitude.toDoubleOrNull()?.let { lon -> lat to lon } }

    /**
     * Null, поки не розбирається кожне поле. Кнопка публікації дивиться сюди. [media] null — медіа події не чіпати;
     * [mediaBase] — з чернетки правки ([app.poruch.shared.PoruchApp.editDraft]).
     */
    fun toDraft(imageUrl: String?, media: List<DraftMedia>?, mediaBase: Set<String>? = null): EventDraft? = runCatching {
        val zone = ZoneId.of(timeZone)
        EventDraft(
            title = title.trim(), description = description.trim(), category = category,
            city = city.trim(), address = address.trim(),
            latitude = latitude.toDouble(), longitude = longitude.toDouble(),
            startsAt = LocalDateTime.parse(starts, LOCAL_FORMAT).atZone(zone).toInstant().toString(),
            endsAt = LocalDateTime.parse(ends, LOCAL_FORMAT).atZone(zone).toInstant().toString(),
            timeZone = timeZone, capacity = capacity.toInt(), imageUrl = imageUrl,
            minAge = minAge.toInt(), maxAge = maxAge.trim().takeIf { it.isNotEmpty() }?.toInt(),
            approvalRequired = approvalRequired, contactUrl = ContactRules.normalize(contactUrl), media = media,
            mediaBase = mediaBase, price = price.trim().takeIf { it.isNotEmpty() }?.toInt()
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
            approvalRequired = approvalRequired, contactUrl = ContactRules.normalize(contactUrl), media = media,
            price = price.trim().takeIf { it.isNotEmpty() }?.let { it.toIntOrNull() ?: -1 }
        ).validate(now.toString())
    }

    companion object {
        val DEFAULT_CATEGORY = EventCategory.SOCIAL
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
    // IMAGE_URL — і понад п'ять фото чи відео: вони на першому кроці.
    ABOUT(setOf(DraftField.TITLE, DraftField.DESCRIPTION, DraftField.CATEGORY, DraftField.IMAGE_URL)),
    PLACE(setOf(DraftField.ADDRESS, DraftField.LOCATION)),
    SCHEDULE(setOf(DraftField.STARTS_AT, DraftField.ENDS_AT, DraftField.TIME_ZONE)),
    PEOPLE(setOf(DraftField.CAPACITY, DraftField.AGE_LIMITS, DraftField.CONTACT_URL, DraftField.PRICE));

    val isLast get() = this == PEOPLE
    fun next() = entries.getOrElse(ordinal + 1) { this }
    fun previous() = entries.getOrElse(ordinal - 1) { this }
}

data class EditorState(
    val editing: Boolean = false,
    /** Правка події з оплатою онлайн: спосіб оплати застосунок не міняє (лише кабінет), але й не каже «на місці». */
    val payOnline: Boolean = false,
    val step: EditorStep = EditorStep.ABOUT,
    val form: EditorForm = EditorForm(),
    val mutating: Boolean = false,
    /** Де відкривається мапа до вибору крапки. */
    val mapLatitude: Double = 0.0,
    val mapLongitude: Double = 0.0,
    val picker: PickerRequest? = null,
    /** Пікер відкрито на годині, а не на дні. */
    val pickerTime: Boolean = false,
    /** Підказки адрес: людина набирає вулицю й будинок, крапку ставить застосунок. */
    val addressSuggestions: List<PlaceResult> = emptyList(),
    /** Відкрито повноекранний вибір точки: на міні-мапі 260 dp обирати незручно. */
    val pickingPoint: Boolean = false,
    /** Адреса під ціллю на екрані вибору. Порожня, поки відповідь у дорозі. */
    val aimAddress: String = "",
    /** «Далі» натиснули з помилками: тепер вони видні під полями, поки крок не зміниться. */
    val showProblems: Boolean = false,
    /** Публікацію відхилено: текст стоїть над кнопкою, а не зникає банером. */
    val failure: AppError? = null,
    /** Відкрита шторка підтвердження: що саме зникне. */
    val discarding: Discard? = null,
    /** Хто збирає — ім'я на квитку, як його побачать на головній. */
    val host: String? = null,
    /** Скільки вже йде: нова зустріч друкується «0/20». */
    val taken: Int = 0,
    /** Скільки людей поруч почують про нову зустріч у цій крапці («Мої місця»). Null — менше трьох, не знаємо чи правимо. */
    val audience: Int? = null,
    /** Текст, вставлений у рядку «Є готовий анонс?». */
    val announce: String = "",
    val announcing: Boolean = false,
    /** Що заповнив анонс: рядок згорнутий у «Заповнили з анонсу…». Null — рядок із «Вставити». */
    val announced: AnnouncementFill? = null,
    /** «Вставити», а в буфері нема тексту: рядок під кнопкою до наступної спроби. */
    val clipboardEmpty: Boolean = false,
    /** Скільки обраних файлів ще стискаємо. */
    val importing: Int = 0,
    /** Котрийсь обраний файл не вдалося додати: рядок під плитками до наступного вибору. */
    val mediaFailed: Boolean = false,
    /** Відео, обрізані до перших 30 с: «Перші 30 секунд» під мініатюрою. */
    val trimmed: Set<String> = emptySet(),
    /** «Завантажуємо 2 з 4» під час публікації. */
    val upload: app.poruch.shared.MediaUpload? = null,
    /** Нова подія публікується: накладка з анімацією й лічильником файлів. */
    val publishing: Boolean = false
) {
    val point get() = form.point
    val pointChosen get() = point != null

    /** Є що стерти: чернетка з текстом, адресою чи файлами. */
    val canStartOver get() = !editing &&
        (form.title.isNotBlank() || form.description.isNotBlank() || form.address.isNotBlank() || form.media.isNotEmpty())

    /** Скільки ще файлів можна додати. */
    val mediaRoom get() = app.poruch.domain.MediaRules.MAX_ITEMS - form.media.size - importing

    /** Кожен крок перевіряє лише свої поля, тож «Далі» не блокується наступним. */
    val stepProblems: List<DraftField> get() = form.problems().filter { it in step.fields }
}

/** Що зникне після підтвердження: правки наявної події чи чернетка нової. */
enum class Discard { CHANGES, DRAFT }

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
    data class ShowPicker(val request: PickerRequest?, val time: Boolean = false) : EditorIntent
    data class SetDateTime(val request: PickerRequest, val value: LocalDateTime) : EditorIntent
    /** Хрестик чи системне «назад» з першого кроку. Правки наявної події спершу підтверджують. */
    data object Close : EditorIntent
    /** Відкрити чи сховати (null) шторку підтвердження. */
    data class AskDiscard(val what: Discard?) : EditorIntent
    /** Що саме відкинути — у самому намірі: шторка, закриваючись, спершу кличе `onDismiss`, і стан уже порожній. */
    data class ConfirmDiscard(val what: Discard) : EditorIntent
    /** Відповідь системи на [EditorEffect.AskNotificationPermission]. */
    data class NotificationPermissionAnswered(val granted: Boolean) : EditorIntent
    /** «Вставити»: текст з буфера, прочитаний у кліку (null — буфер порожній чи не текст), і одразу заповнення. */
    data class PasteAnnounce(val text: String?) : EditorIntent
    /** «Інший текст»: знову рядок із «Вставити». */
    data object ReopenAnnounce : EditorIntent
    /** Обране в системному виборі фото й відео. */
    data class AddMedia(val uris: List<Uri>) : EditorIntent
    data class RemoveMedia(val index: Int) : EditorIntent
    /** Перетягнули плитку: перше стане обкладинкою. */
    data class MoveMedia(val from: Int, val to: Int) : EditorIntent
}

sealed interface EditorEffect {
    data object Close : EditorEffect
    /** Гість натиснув «Опублікувати»: вхід поверх редактора, після нього подія публікується сама. */
    data object SignIn : EditorEffect
    /** Нову подію опубліковано: редактор поступається екрану «Подію створено». */
    data object Published : EditorEffect
    data object AskNotificationPermission : EditorEffect
}
