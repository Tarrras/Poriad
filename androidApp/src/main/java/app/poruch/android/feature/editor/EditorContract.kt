package app.poruch.android.feature.editor

import android.net.Uri
import app.poruch.domain.AnnouncementFill
import app.poruch.domain.DraftMedia
import app.poruch.domain.EventCategory
import app.poruch.domain.AppError
import app.poruch.domain.ContactRules
import app.poruch.domain.DraftField
import app.poruch.domain.EventDraft
import app.poruch.domain.MeetupTemplate
import app.poruch.domain.PlaceResult
import app.poruch.domain.QuickDay
import app.poruch.domain.QuickEvent
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
    val price: String = "",
    /** Коли платять: передоплата, а не на зустрічі. Лише з ціною. */
    val prepay: Boolean = false,
    /** Вхід платний: тоді є ціна й «Коли платять». Платно без ціни — помилка ціни, а не безкоштовна подія. */
    val paid: Boolean = false,
    /** Шаблон «швидкої події»: підсвічує чип і дає типовий опис. Правка наявної події його не має. */
    val template: MeetupTemplate? = null,
    /** «Лише за посиланням»: не на мапі, не в пошуку, без пушів (docs/link-only-2026-11.md). */
    val linkOnly: Boolean = false
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
            mediaBase = mediaBase, price = if (paid) price.trim().toInt() else null, prepay = paid && prepay,
            linkOnly = linkOnly, template = template?.key
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
            price = if (paid) price.trim().toIntOrNull() ?: -1 else null
        ).validate(now.toString())
    }

    /** Початок і кінець як мить: правила дня й тривалості ([QuickEvent]) рахують у мілісекундах. */
    val startMillis: Long? get() = millis(starts)
    val endMillis: Long? get() = millis(ends)

    private fun millis(value: String) = runCatching {
        LocalDateTime.parse(value, LOCAL_FORMAT).atZone(ZoneId.of(timeZone)).toInstant().toEpochMilli()
    }.getOrNull()

    private fun local(millis: Long) = runCatching {
        Instant.ofEpochMilli(millis).atZone(ZoneId.of(timeZone)).toLocalDateTime().format(LOCAL_FORMAT)
    }.getOrDefault("")

    /** Новий початок; кінець їде за ним, зберігаючи тривалість (без неї — шаблону чи типову). Як `moveStart` на iOS. */
    fun startingAt(start: Long) = copy(
        starts = local(start),
        ends = local(QuickEvent.end(start, startMillis, endMillis, template?.minutes ?: QuickEvent.DEFAULT_MINUTES))
    )

    /** Шаблон ставить жанр, місця й тривалість; [title] — назва, якщо людина ще не написала свою ([QuickEvent.title]). */
    fun with(template: MeetupTemplate, title: String) = copy(
        template = template, category = template.category, capacity = template.seats.toString(), title = title,
        ends = startMillis?.let { local(QuickEvent.end(it, minutes = template.minutes)) } ?: ends
    )

    /** Нова зустріч без початку (перша чи давня чернетка) — одразу з вечором: квиток друкує годину, «Коли» вже з відповіддю. */
    fun scheduled(now: Long = System.currentTimeMillis()) =
        if (starts.isNotEmpty()) this else copy(ends = "").startingAt(QuickEvent.defaultStart(now, timeZone))

    /** Опис для публікації: свій або, якщо його нема, типовий за шаблоном ([about]) — сервер без опису подію не прийме. */
    fun described(about: String) = if (description.isBlank()) copy(description = about) else this

    companion object {
        val DEFAULT_CATEGORY = EventCategory.SOCIAL
        val DEFAULT_CAPACITY = QuickEvent.DEFAULT_SEATS.toString()
        val DEFAULT_MIN_AGE = SafetyRules.MIN_SIGNUP_AGE.toString()
        /** Формат дат у чернетці: локальний час, не UTC. */
        val LOCAL_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
    }
}

data class EditorState(
    val editing: Boolean = false,
    /** Правка події з оплатою онлайн: підказка під ціною — про неї, а не «на місці». */
    val payOnline: Boolean = false,
    /** Правка: ця подія в кабінеті на сайті — «Повні налаштування — в кабінеті». Нова подія — null. */
    val cabinet: String? = null,
    /** «Ще» розгорнуто: опис, фото, вхід, чат і решта, чого проста зустріч не потребує. */
    val more: Boolean = false,
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
    /** «Опублікувати» натиснули з помилками: тепер вони видні під полями. */
    val showProblems: Boolean = false,
    /** Росте з кожною відмовою «Опублікувати»: екран веде до першого поля з помилкою й ставить у нього фокус. */
    val jump: Int = 0,
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
    val publishing: Boolean = false,
    /** Правка: форма, якою подія прийшла. Null — нова подія. */
    val unedited: EditorForm? = null
) {
    /** Правку змінено: «назад» спершу питає, чи скасувати зміни. */
    val changed get() = unedited != null && unedited != form
    val point get() = form.point
    val pointChosen get() = point != null

    /** Є що стерти: чернетка з текстом, адресою чи файлами. */
    val canStartOver get() = !editing &&
        (form.title.isNotBlank() || form.description.isNotBlank() || form.address.isNotBlank() || form.media.isNotEmpty())

    /** Скільки ще файлів можна додати. */
    val mediaRoom get() = app.poruch.domain.MediaRules.MAX_ITEMS - form.media.size - importing

    /** Що не так у формі. Порожній опис — не помилка: публікація ставить типовий ([EditorForm.described]). */
    val problems: List<DraftField>
        get() = QuickEvent.placeProblems(form.problems().filter { it != DraftField.DESCRIPTION || form.description.isNotBlank() })
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
    /** Чип шаблону: жанр, місця, тривалість і назва, якщо своєї ще нема. */
    data class PickTemplate(val template: MeetupTemplate, val title: String) : EditorIntent
    /** Чип дня: «Сьогодні», «Завтра», вихідний. */
    data class PickDay(val day: QuickDay) : EditorIntent
    /** «−» і «+» біля місць. */
    data class Seats(val delta: Int) : EditorIntent
    /** Розгорнути чи згорнути «Ще». */
    data object ToggleMore : EditorIntent
    /** Кабінет на сайті: підказка великої події чи «Повні налаштування» у правці. */
    data class OpenCabinet(val url: String) : EditorIntent
    /** [about] — типовий опис за шаблоном, якщо людина не написала свого. */
    data class Submit(val about: String) : EditorIntent
    data class ShowPicker(val request: PickerRequest?, val time: Boolean = false) : EditorIntent
    data class SetDateTime(val request: PickerRequest, val value: LocalDateTime) : EditorIntent
    /** Хрестик чи системне «назад». Правки наявної події спершу підтверджують. */
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
    data class Browse(val url: String) : EditorEffect
}
