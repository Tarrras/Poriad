package app.poruch.android.feature.editor

import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
import app.poruch.android.platform.NotificationPermission
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import app.poruch.domain.Event
import app.poruch.domain.PlaceResult
import app.poruch.shared.PoruchApp
import java.time.Instant
import java.time.ZoneId

/** Редактор на три кроки. Тримає форму, відновлює чернетку з [DraftStore], у стор іде лише коли все розбирається. */
class EditorViewModel(
    private val app: PoruchApp,
    private val drafts: DraftStore,
    private val notifications: NotificationPermission,
    private val editingId: String?
) : MviViewModel<EditorState, EditorIntent, EditorEffect>(EditorState(editing = editingId != null)) {

    private var original: Event? = null
    private var submitted = false

    /** Токен запиту адреси: пізня відповідь не має затирати те, що набрали після неї. */
    private var addressToken = 0

    /** Останнє знайдене під ціллю, разом із координатами. */
    private var aimed: Pair<Pair<Double, Double>, PlaceResult>? = null
    private var aimJob: Job? = null

    init {
        val shared = app.state.value
        val event = editingId?.let { id -> (shared.library.myEvents + shared.map.events).firstOrNull { it.id == id } }
        original = event
        reduce {
            val restored = event?.toForm() ?: drafts.load(shared.city.name)
            // Мапа відкривається на крапці, якщо вона вже є.
            val (latitude, longitude) = restored.point ?: (shared.city.latitude to shared.city.longitude)
            copy(form = restored, mapLatitude = latitude, mapLongitude = longitude)
        }
        observe(app) { latest ->
            // Редагування з deep link: запис може приїхати після екрана.
            val loaded = editingId?.let { id -> latest.detail.event?.takeIf { it.id == id } }
            if (loaded != null && original == null) {
                original = loaded
                val form = loaded.toForm() ?: return@observe copy(mutating = latest.mutating)
                return@observe copy(form = form, mapLatitude = loaded.latitude, mapLongitude = loaded.longitude, mutating = latest.mutating)
            }
            if (submitted && latest.completedEventId != null) {
                submitted = false
                drafts.clear(); app.clearCompletedEvent()
                // Нова подія — момент спитати про сповіщення: без дозволу запити на участь не дзвонять.
                // Закриваємось після відповіді, бо запит живе в маршруті редактора.
                if (editingId == null && !latest.remindersEnabled && !notifications.granted()) send(EditorEffect.AskNotificationPermission)
                else send(EditorEffect.Close)
            }
            copy(mutating = latest.mutating)
        }
    }

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
            EditorIntent.Next -> reduce { if (canAdvance) copy(step = step.next()) else this }
            EditorIntent.Back -> reduce { copy(step = step.previous()) }
            is EditorIntent.ShowPicker -> reduce { copy(picker = intent.request) }
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
            is EditorIntent.NotificationPermissionAnswered -> {
                if (intent.granted) app.setRemindersEnabled(true)
                send(EditorEffect.Close)
            }
        }
    }

    private fun submit() {
        val draft = state.value.form.toDraft(original?.imageUrl) ?: return
        app.clearCompletedEvent()
        submitted = true
        val id = editingId
        if (id != null) app.updateEvent(id, draft) else app.createEvent(draft)
    }

    private fun persist() {
        if (editingId == null) drafts.save(state.value.form)
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
            app.searchAddress(query, near.mapLatitude, near.mapLongitude) { found ->
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
                reduce { copy(form = form.copy(timeZone = zone), timeZoneFromPlace = true) }
                persist()
            }
        }
    }

    /** Редагувати можна лише кімнату: сервер перевіряє те саме в `assert_event_editable`. */
    private fun Event.toForm(): EditorForm? {
        val room = gathering ?: return null
        return EditorForm(
            title = title, description = description, category = category, city = city, address = address,
            latitude = latitude.format(), longitude = longitude.format(), timeZone = timeZone,
            starts = startsAt.toLocal(timeZone), ends = endsAt.toLocal(timeZone), capacity = room.capacity.toString(),
            minAge = room.minAge.toString(), maxAge = room.maxAge?.toString().orEmpty(),
            approvalRequired = room.approvalRequired, contactUrl = room.contactUrl.orEmpty()
        )
    }

    private fun String.toLocal(zone: String) = runCatching {
        Instant.parse(this).atZone(ZoneId.of(zone)).toLocalDateTime().format(EditorForm.LOCAL_FORMAT)
    }.getOrDefault("")

    private fun Double.format() = "%.6f".format(java.util.Locale.ROOT, this).trimEnd('0').trimEnd('.')

    private companion object {
        /** Пауза після руху мапи перед запитом поясу. */
        const val ZONE_SETTLE_MS = 500L
        /** Пауза в наборі адреси. */
        const val ADDRESS_SETTLE_MS = 350L
        /** Коротший запит нічого не звужує. */
        const val MIN_ADDRESS_QUERY = 3
        /** Пауза для цілі на екрані вибору: коротша, бо людина чекає саме на цей рядок. */
        const val AIM_SETTLE_MS = 200L
    }
}
