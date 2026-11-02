package app.poruch.android.feature.editor

import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
import app.poruch.android.platform.NotificationPermission
import app.poruch.android.feature.known
import kotlinx.coroutines.Job
import kotlinx.coroutines.job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import app.poruch.domain.AnnouncementFill
import app.poruch.domain.AnnouncementRules
import app.poruch.domain.DraftField
import app.poruch.domain.DraftMedia
import app.poruch.domain.Event
import app.poruch.domain.EventCategory
import app.poruch.domain.EventDraft
import app.poruch.domain.EventRules
import app.poruch.domain.PlaceResult
import app.poruch.shared.AppNotice
import app.poruch.shared.PoruchApp
import java.time.Instant
import java.time.ZoneId

/**
 * Редактор на чотири кроки. Тримає форму, відновлює чернетку з [DraftStore], у стор іде лише коли все розбирається.
 * Відкритий і гостю: вхід — на «Опублікувати», після нього подія публікується сама ([AppState.publishAfterSignIn]).
 * [repeatOf] — нова подія з полями, фото й відео власної («Повторити»).
 */
class EditorViewModel(
    private val app: PoruchApp,
    private val drafts: DraftStore,
    private val files: DraftMediaFiles,
    private val notifications: NotificationPermission,
    private val editingId: String?,
    repeatOf: String? = null
) : MviViewModel<EditorState, EditorIntent, EditorEffect>(EditorState(editing = editingId != null)) {

    private var original: Event? = null
    private var submitted = false
    /** Вхід відкрито поверх редактора й чекає: гість натиснув «Опублікувати». */
    private var awaitingSignIn = false
    /**
     * Чернетка правки від спільного шару ([PoruchApp.editDraft]): поля, медіа й `mediaBase` — файли, з якими редактор
     * відкрився. Медіа шлемо лише змінені; що видаляти, звіряє спільний шар з сервером.
     */
    private var editDraft: EventDraft? = null
    /** Форма, з якою правка відкрилась: «Відкинути зміни?» і чи чіпали медіа. */
    private var originalForm: EditorForm? = null
    /** Стиснення обраних файлів: «Стерти» скасовує їх разом, а з екраном вони йдуть самі (дочірні до viewModelScope). */
    private var imports = Job(viewModelScope.coroutineContext.job)
    /** Нову подію почали з незакінченої чернетки: параметр `draft` воронки створення. */
    private var resumed = false

    /** Токен запиту адреси: пізня відповідь не має затирати те, що набрали після неї. */
    private var addressToken = 0

    /** Останнє знайдене під ціллю, разом із координатами. */
    private var aimed: Pair<Pair<Double, Double>, PlaceResult>? = null
    private var aimJob: Job? = null

    init {
        val shared = app.state.value
        // Повні медіа (`mediaLoaded`) — з відкритих деталей чи «Моїх подій»; картка мапи — запасна: тоді `mediaBase` нема, і
        // правка медіа лише додає до серверних.
        val event = editingId?.let { id ->
            val known = listOfNotNull(shared.detail.event) + shared.library.myEvents + shared.map.events
            known.firstOrNull { it.id == id && it.mediaLoaded } ?: known.firstOrNull { it.id == id }
        }
        original = event
        editDraft = event?.let(app::editDraft)
        originalForm = editDraft?.toForm()
        // Повтор не пишемо в чернетку, поки людина нічого не змінила: незакінчена нова лишається, якщо просто закрити.
        // Повна подія: «Мої події» дозавантажили деталі перед переходом ([withMedia]).
        val repeated = repeatOf?.let { id -> app.known(id) ?: shared.library.myEvents.firstOrNull { it.id == id } }
            ?.let(app::repeatDraft)?.toForm()
        reduce {
            val restored = originalForm ?: repeated ?: drafts.load(shared.city.name)
            // Мапа відкривається на крапці, якщо вона вже є.
            val (latitude, longitude) = restored.point ?: (shared.city.latitude to shared.city.longitude)
            copy(
                form = restored, mapLatitude = latitude, mapLongitude = longitude,
                host = (event?.gathering?.organizerName ?: shared.library.profile?.name)?.takeIf { it.isNotBlank() },
                taken = event?.gathering?.attendeeCount ?: 0
            )
        }
        resumed = repeated == null && state.value.canStartOver
        // «Анонс отримають N людей поруч»: лише для нової зустрічі — про правки сервер нікому не пише.
        if (editingId == null) viewModelScope.launch {
            state.map { it.point }.distinctUntilChanged().collectLatest { point ->
                reduce { copy(audience = null) }
                if (point == null) return@collectLatest
                delay(AUDIENCE_DEBOUNCE_MS)
                // Пізня відповідь для старої крапки не затирає нову.
                app.zoneAudience(point.first, point.second) { count -> reduce { if (this.point == point) copy(audience = count) else this } }
            }
        }
        track(EditorStep.ABOUT)
        observe(app) { latest ->
            // Редагування з deep link: запис може приїхати після екрана.
            val loaded = editingId?.let { id -> latest.detail.event?.takeIf { it.id == id } }
            if (loaded != null && original == null) {
                original = loaded
                editDraft = app.editDraft(loaded)
                val form = editDraft?.toForm() ?: return@observe copy(mutating = latest.mutating)
                originalForm = form
                return@observe copy(
                    form = form, mapLatitude = loaded.latitude, mapLongitude = loaded.longitude, mutating = latest.mutating,
                    host = loaded.gathering?.organizerName?.takeIf { it.isNotBlank() } ?: host,
                    taken = loaded.gathering?.attendeeCount ?: 0
                )
            }
            // Відмову показуємо над кнопкою, де людина щойно натиснула, а не банером згори. Поки зверху вхід, помилки — його
            // (хибний код, забагато спроб).
            val failed = (latest.notice as? AppNotice.Failed)?.error
            if (submitted && failed != null && !awaitingSignIn) {
                submitted = false; awaitingSignIn = false
                app.clearNotice()
                return@observe copy(mutating = latest.mutating, upload = null, failure = failed)
            }
            if (submitted && latest.completedEventId != null) {
                submitted = false; awaitingSignIn = false
                unsaved = false; saveJob?.cancel(); app.clearCompletedEvent()
                // Файли вже в події: чернетка нової йде разом зі своїми, правка — лише зі своїми новими.
                if (editingId == null) drafts.clear() else dropLocalFiles()
                // Нова подія — момент спитати про сповіщення: без дозволу запити на участь не дзвонять.
                // Закриваємось після відповіді, бо запит живе в маршруті редактора.
                if (editingId == null && latest.remindersEnabled && !notifications.granted()) send(EditorEffect.AskNotificationPermission)
                else finish()
            }
            // Гість: спільний шар перевірив чернетку й чекає на вхід, а то й на галочку віку — її сервер може попросити вже
            // після входу (`AGE_REQUIRED` на публікації). Тоді вхід відкриваємо знову, на кроці галочки.
            val needsSignIn = latest.publishAfterSignIn && (!latest.signedIn || latest.session.askBirthDate)
            if (submitted && needsSignIn && !awaitingSignIn) {
                awaitingSignIn = true
                send(EditorEffect.SignIn)
            } else if (awaitingSignIn && !needsSignIn) {
                awaitingSignIn = false
                // Закрили вхід без входу: лишаємось тут з чернеткою, публікація скасована.
                if (!latest.publishAfterSignIn) submitted = false
            }
            // Нова подія публікується: анімація поверх редактора, а не спінер на кнопці (1.6).
            copy(mutating = latest.mutating, upload = latest.mediaUpload, publishing = editingId == null && submitted && latest.mutating && !awaitingSignIn)
        }
    }

    /** Нову подію опубліковано — «Подію створено» замість редактора; правку — просто назад. */
    private fun finish() =
        send(if (editingId == null && app.state.value.published != null) EditorEffect.Published else EditorEffect.Close)

    override fun onIntent(intent: EditorIntent) {
        when (intent) {
            is EditorIntent.Edit -> {
                val before = state.value.form.address
                reduce { copy(form = intent.change(form)) }
                persist()
                // Пошук лише при зміні адреси.
                if (state.value.form.address != before) suggestAddresses(state.value.form.address)
            }
            is EditorIntent.PickAddress -> {
                reduce {
                    copy(
                        form = form.copy(
                            address = intent.place.label,
                            // Місто їде за адресою.
                            city = intent.place.city.ifBlank { form.city },
                            latitude = intent.place.latitude.format(),
                            longitude = intent.place.longitude.format()
                        ),
                        mapLatitude = intent.place.latitude,
                        mapLongitude = intent.place.longitude,
                        addressSuggestions = emptyList(),
                        pickingPoint = false
                    )
                }
                persist()
                resolveZone(intent.place.latitude, intent.place.longitude)
            }
            is EditorIntent.ShowPointPicker -> {
                aimed = null
                reduce { copy(pickingPoint = intent.open, aimAddress = "") }
            }
            is EditorIntent.AimAt -> describeAim(intent.latitude, intent.longitude)
            is EditorIntent.PickPoint -> {
                // Шість знаків — близько 10 см, більше на екрані шум.
                val known = aimed?.takeIf { it.first == (intent.latitude to intent.longitude) }?.second
                reduce {
                    copy(
                        form = form.copy(
                            latitude = intent.latitude.format(), longitude = intent.longitude.format(),
                            address = known?.label ?: form.address,
                            city = known?.city?.ifBlank { form.city } ?: form.city
                        ),
                        addressSuggestions = emptyList(),
                        pickingPoint = false
                    )
                }
                persist()
                resolveZone(intent.latitude, intent.longitude)
                // Екран вибору вже спитав про цю крапку.
                if (known == null) describePoint(intent.latitude, intent.longitude)
            }
            EditorIntent.Next -> {
                val problem = state.value.stepProblems.firstOrNull()
                if (problem != null) { blocked(problem); reduce { copy(showProblems = true) } }
                else { reduce { copy(step = step.next(), showProblems = false) }; track(state.value.step) }
            }
            EditorIntent.Back -> reduce { copy(step = step.previous(), showProblems = false, failure = null) }
            is EditorIntent.ShowPicker -> reduce { copy(picker = intent.request, pickerTime = intent.time) }
            is EditorIntent.SetDateTime -> {
                val text = intent.value.format(EditorForm.LOCAL_FORMAT)
                reduce {
                    copy(
                        picker = null,
                        form = when (intent.request) {
                            PickerRequest.STARTS -> form.copy(starts = text)
                            PickerRequest.ENDS -> form.copy(ends = text)
                        }
                    )
                }
                persist()
            }
            EditorIntent.Submit -> submit()
            EditorIntent.Close -> when {
                // Під час публікації не закриваємось: відповідь сервера нікому було б прийняти,
                // чернетка лишалась би, і наступне «+» публікувало б ту саму подію вдруге.
                state.value.mutating -> Unit
                editingId != null && edited() -> reduce { copy(discarding = Discard.CHANGES) }
                else -> send(EditorEffect.Close)
            }
            is EditorIntent.AskDiscard -> reduce { copy(discarding = intent.what) }
            is EditorIntent.ConfirmDiscard -> when (intent.what) {
                Discard.CHANGES -> send(EditorEffect.Close)
                Discard.DRAFT -> {
                    imports.cancel(); imports = Job(viewModelScope.coroutineContext.job)
                    unsaved = false; saveJob?.cancel(); drafts.clear(); resumed = false
                    val city = app.state.value.city
                    reduce {
                        EditorState(form = drafts.load(city.name), mapLatitude = city.latitude, mapLongitude = city.longitude, host = host)
                    }
                }
            }
            is EditorIntent.NotificationPermissionAnswered -> {
                if (intent.granted) app.setRemindersEnabled(true)
                finish()
            }
            is EditorIntent.PasteAnnounce -> {
                val text = intent.text?.trim().orEmpty()
                if (text.isEmpty()) reduce { copy(clipboardEmpty = true) }
                else { reduce { copy(announce = text.take(AnnouncementRules.TEXT_MAX), clipboardEmpty = false) }; fillFromAnnounce() }
            }
            EditorIntent.ReopenAnnounce -> reduce { copy(announced = null) }
            is EditorIntent.AddMedia -> addMedia(intent.uris)
            is EditorIntent.RemoveMedia -> {
                val removed = state.value.form.media.getOrNull(intent.index) ?: return
                reduce { copy(form = form.copy(media = form.media - removed), trimmed = trimmed - (removed as? DraftMedia.Local)?.key.orEmpty()) }
                (removed as? DraftMedia.Local)?.let { files.delete(it.key) }
                persist()
            }
            is EditorIntent.MoveMedia -> {
                val media = state.value.form.media.toMutableList()
                if (intent.from !in media.indices || intent.to !in media.indices) return
                media.add(intent.to, media.removeAt(intent.from))
                reduce { copy(form = form.copy(media = media)) }
                persist()
            }
        }
    }

    /** «Вставити»: функція розбирає анонс, і поля, яких у тексті нема, лишаються як були. Відповідь — і гостю. */
    private fun fillFromAnnounce() {
        val text = state.value.announce.trim()
        if (text.isEmpty() || state.value.announcing) return
        reduce { copy(announcing = true) }
        val before = state.value.form
        viewModelScope.launch {
            val fill = app.fillFromAnnouncement(text, before.city, before.timeZone)
            // Поки функція думала, людина вже публікує чи сама правила поля: пізня відповідь не затирає набране й не пише
            // опубліковану подію знову в чернетку. Файли, що дотиснулись тим часом, — не правка.
            if (submitted || state.value.form.copy(media = before.media) != before) {
                reduce { copy(announcing = false) }
                return@launch
            }
            reduce { copy(announcing = false, announced = fill, form = form.filledFrom(fill)) }
            persist()
            // Крапку ставить людина з підказок адрес, як і для набраної адреси: на кроці «Де» вони вже чекатимуть.
            fill.address?.let(::suggestAddresses)
        }
    }

    private fun EditorForm.filledFrom(fill: AnnouncementFill): EditorForm {
        val address = fill.address?.trim()?.takeIf { it.isNotEmpty() && it != address }
        return copy(
            title = fill.title?.take(EventRules.titleLength.last) ?: title,
            description = fill.description?.take(EventRules.descriptionLength.last) ?: description,
            category = fill.category?.takeIf { it != EventCategory.UNKNOWN } ?: category,
            starts = fill.startsAt?.toLocal(timeZone)?.takeIf { it.isNotEmpty() } ?: starts,
            ends = fill.endsAt?.toLocal(timeZone)?.takeIf { it.isNotEmpty() } ?: ends,
            address = address ?: this.address,
            // Стара крапка стояла біля іншої адреси.
            latitude = if (address != null) "" else latitude, longitude = if (address != null) "" else longitude,
            capacity = fill.capacity?.toString() ?: capacity,
            minAge = fill.minAge?.toString() ?: minAge,
            contactUrl = fill.contactUrl ?: contactUrl
        )
    }

    /** По одному: відео стискається довго, і два кодеки разом — забагато для телефона. */
    private fun addMedia(uris: List<android.net.Uri>) {
        val picked = uris.take(state.value.mediaRoom)
        if (picked.isEmpty()) return
        reduce { copy(importing = importing + picked.size, mediaFailed = false) }
        viewModelScope.launch(imports) {
            picked.forEach { uri ->
                val imported = files.import(uri)
                reduce {
                    val left = (importing - 1).coerceAtLeast(0)
                    if (imported == null) copy(importing = left, mediaFailed = true)
                    else copy(
                        importing = left, form = form.copy(media = form.media + imported.media),
                        trimmed = if (imported.trimmed) trimmed + imported.media.key else trimmed
                    )
                }
                imported?.let { app.mediaAdded(it.media.kind); persist() }
            }
        }
    }

    /** Нові файли правки потрібні лише до збереження: чернетки в правки нема. */
    private fun dropLocalFiles() = state.value.form.media.filterIsInstance<DraftMedia.Local>().forEach { files.delete(it.key) }

    private fun submit() {
        // Файл ще стискається: без нього подія вийшла б не з тими медіа, а він лишився б у закритому редакторі.
        if (state.value.importing > 0) return
        // Уся форма, а не крок: поки людина дивилась на неї, початок міг стати минулим.
        state.value.form.problems().firstOrNull()?.let { field ->
            blocked(field)
            return reduce { copy(step = EditorStep.entries.first { field in it.fields }, showProblems = true) }
        }
        val form = state.value.form
        // Правка без змін у файлах — null: сервер лишає медіа як є (старі клієнти так само).
        // Правка: медіа не чіпали — null, сервер лишає як є; інакше список разом з базою, з якою редактор відкрився.
        val base = editDraft
        val media = if (base == null) form.media else form.media.takeIf { it != originalForm?.media }
        val draft = form.toDraft(base?.imageUrl, media, base?.mediaBase) ?: return
        reduce { copy(failure = null) }
        app.clearCompletedEvent()
        submitted = true
        val id = editingId
        if (id != null) app.updateEvent(id, draft) else app.createEvent(draft)
    }

    /** Воронка створення (docs/analytics.md): лише нова подія, правка наявної — інша історія. */
    private fun track(reached: EditorStep) {
        if (editingId == null) app.createStep(reached.name.lowercase(), resumed, state.value.form.media.size)
    }

    private fun blocked(field: DraftField) {
        if (editingId == null) app.createBlocked(EditorStep.entries.first { field in it.fields }.name.lowercase(), field)
    }

    /** Запис чернетки після паузи в наборі: п'ятнадцять ключів на кожну літеру — зайве для диска. */
    private var saveJob: Job? = null
    /** Є правка, яку ще не записали. Не `saveJob.isActive`: `viewModelScope` скасовується раніше за [onCleared]. */
    private var unsaved = false

    private fun persist() {
        if (editingId != null) return
        unsaved = true
        saveJob?.cancel()
        saveJob = viewModelScope.launch { delay(SAVE_SETTLE_MS); drafts.save(state.value.form); unsaved = false }
    }

    /** Екран закрили посеред паузи: недописане зберігаємо зараз. Після публікації й «Стерти» прапорець уже знято. */
    override fun onCleared() {
        if (unsaved) drafts.save(state.value.form)
        if (editingId != null) dropLocalFiles()
        super.onCleared()
    }

    /** Пояс за місцем. Питаємо після зупинки руху: геокодер ходить у мережу. */
    private var zoneJob: Job? = null
    private var addressJob: Job? = null

    /** Підказки адрес після паузи в наборі, з пріоритетом біля того, що вже на мапі. */
    private fun suggestAddresses(query: String) {
        addressJob?.cancel()
        if (query.trim().length < MIN_ADDRESS_QUERY) {
            addressToken++
            reduce { copy(addressSuggestions = emptyList()) }
            return
        }
        val token = ++addressToken
        addressJob = viewModelScope.launch {
            delay(ADDRESS_SETTLE_MS)
            val near = state.value
            app.searchAddress(query, near.mapLatitude, near.mapLongitude, near.form.city) { found ->
                if (token != addressToken) return@searchAddress
                reduce { copy(addressSuggestions = found) }
            }
        }
    }

    /** Адреса поставленої крапки: поле й мапа показують одне, тож крапка веде поле, як підказка веде крапку. */
    private fun describePoint(latitude: Double, longitude: Double) {
        addressJob?.cancel()
        val token = ++addressToken
        addressJob = viewModelScope.launch {
            delay(ADDRESS_SETTLE_MS)
            app.resolveAddress(latitude, longitude) { place ->
                if (place == null || token != addressToken) return@resolveAddress
                reduce {
                    copy(
                        form = form.copy(address = place.label, city = place.city.ifBlank { form.city }),
                        // Старі підказки стосувались набору до крапки.
                        addressSuggestions = emptyList()
                    )
                }
                persist()
            }
        }
    }

    /** Що під ціллю. Окремо від [describePoint]: там крапку вже обрали, тут ще приміряють. */
    private fun describeAim(latitude: Double, longitude: Double) {
        aimJob?.cancel()
        reduce { copy(aimAddress = "") }
        aimJob = viewModelScope.launch {
            delay(AIM_SETTLE_MS)
            app.resolveAddress(latitude, longitude) { place ->
                if (place == null || !state.value.pickingPoint) return@resolveAddress
                aimed = (latitude to longitude) to place
                reduce { copy(aimAddress = place.label) }
            }
        }
    }

    private fun resolveZone(latitude: Double, longitude: Double) {
        zoneJob?.cancel()
        zoneJob = viewModelScope.launch {
            delay(ZONE_SETTLE_MS)
            app.resolveTimeZone(latitude, longitude) { zone ->
                if (zone == null) return@resolveTimeZone
                reduce { copy(form = form.copy(timeZone = zone)) }
                persist()
            }
        }
    }

    /** Правку змінено відносно форми, з якою вона відкрилась. */
    private fun edited() = originalForm != null && originalForm != state.value.form

    /** Чернетка правки ([PoruchApp.editDraft]) чи «Повторити» у формі; у повтору дати вже на тиждень пізніше. */
    private fun EventDraft.toForm() = EditorForm(
        title = title, description = description, category = category ?: EditorForm.DEFAULT_CATEGORY, city = city,
        address = address, latitude = latitude.format(), longitude = longitude.format(), timeZone = timeZone,
        starts = startsAt.toLocal(timeZone), ends = endsAt.toLocal(timeZone), capacity = capacity.toString(),
        minAge = minAge.toString(), maxAge = maxAge?.toString().orEmpty(), approvalRequired = approvalRequired,
        contactUrl = contactUrl.orEmpty(), media = media.orEmpty(), price = price?.toString().orEmpty()
    )

    private fun String.toLocal(zone: String) = runCatching {
        Instant.parse(this).atZone(ZoneId.of(zone)).toLocalDateTime().format(EditorForm.LOCAL_FORMAT)
    }.getOrDefault("")

    private fun Double.format() = "%.6f".format(java.util.Locale.ROOT, this).trimEnd('0').trimEnd('.')

    private companion object {
        /** Пауза після руху мапи перед запитом поясу. */
        const val ZONE_SETTLE_MS = 500L
        /** Пауза в наборі перед записом чернетки. */
        const val SAVE_SETTLE_MS = 400L
        /** Пауза в наборі адреси. */
        const val ADDRESS_SETTLE_MS = 350L
        /** Коротший запит нічого не звужує. */
        const val MIN_ADDRESS_QUERY = 3
        /** Пауза для цілі на екрані вибору: коротша, бо людина чекає саме на цей рядок. */
        const val AIM_SETTLE_MS = 200L
        /** Крапка ще може посунутись (підказка адреси, повторний вибір): питаємо, коли постоїть. */
        const val AUDIENCE_DEBOUNCE_MS = 400L
    }
}
