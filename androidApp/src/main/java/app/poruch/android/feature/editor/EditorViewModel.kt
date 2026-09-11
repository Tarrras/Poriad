package app.poruch.android.feature.editor

import androidx.lifecycle.viewModelScope
import app.poruch.android.mvi.MviViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import app.poruch.domain.Event
import app.poruch.domain.PlaceResult
import app.poruch.shared.PoruchApp
import java.time.Instant
import java.time.ZoneId

/**
 * The three-step editor. It keeps the form, restores a draft through [DraftStore] so a closed app
 * does not lose typing, and only reaches the store once every field parses.
 */
class EditorViewModel(
    private val app: PoruchApp,
    private val drafts: DraftStore,
    private val editingId: String?
) : MviViewModel<EditorState, EditorIntent, EditorEffect>(EditorState(editing = editingId != null)) {

    private var original: Event? = null
    private var submitted = false

    /**
     * Хто зараз має право писати в поле адреси.
     *
     * Скасувати корутину замало: запит до мережі вже пішов, і його відповідь прийде в будь-якому
     * разі. Токен вирішує, чи вона ще комусь потрібна — інакше пізня відповідь затирала б те, що
     * людина набрала після неї.
     */
    private var addressToken = 0

    /** Останнє, що знайшлось під ціллю. Тримаємо разом із координатами, бо саме пара має збігтись. */
    private var aimed: Pair<Pair<Double, Double>, PlaceResult>? = null
    private var aimJob: Job? = null

    init {
        val shared = app.state.value
        val event = editingId?.let { id -> (shared.myEvents + shared.events).firstOrNull { it.id == id } }
        original = event
        reduce {
            val restored = event?.toForm() ?: drafts.load(shared.cityName)
            // Мапа відкривається на крапці, якщо вона вже є: чернетка з обраною адресою, показана
            // над центром міста, читається як втрачена адреса.
            val (latitude, longitude) = restored.point ?: (shared.cityLatitude to shared.cityLongitude)
            copy(form = restored, mapLatitude = latitude, mapLongitude = longitude)
        }
        observe(app) { latest ->
            // Editing an event opened from a deep link: its record may arrive after this screen did.
            val loaded = editingId?.let { id -> latest.selectedEvent?.takeIf { it.id == id } }
            if (loaded != null && original == null) {
                original = loaded
                val form = loaded.toForm() ?: return@observe copy(mutating = latest.mutating)
                return@observe copy(form = form, mapLatitude = loaded.latitude, mapLongitude = loaded.longitude, mutating = latest.mutating)
            }
            if (submitted && latest.completedEventId != null) {
                drafts.clear(); app.clearCompletedEvent(); send(EditorEffect.Close)
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
                // Адресу набирають — шукаємо. Решту полів це не стосується.
                if (state.value.form.address != before) suggestAddresses(state.value.form.address)
            }
            is EditorIntent.PickAddress -> {
                reduce {
                    copy(
                        form = form.copy(
                            address = intent.place.label,
                            // Місто їде за адресою: крапка могла виявитись і в іншому місті.
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
                // Six decimals is about a tenth of a metre — more digits are noise on screen.
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
                // Екран вибору вже спитав про цю крапку — питати вдруге означало б чекати двічі.
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

    /**
     * Пояс іде за місцем.
     *
     * Мапу тягають пальцем, тож запитів було б стільки ж, скільки кадрів — а геокодер ходить у
     * мережу. Тому питаємо, коли рух зупинився, і скасовуємо попереднє питання, якщо не встиг.
     */
    private var zoneJob: Job? = null
    private var addressJob: Job? = null

    /**
     * Підказки адрес.
     *
     * Чекаємо паузи в наборі: кожен запит іде в мережу, а половина слова однаково нічого не
     * знайде. Зсув беремо від того, що вже на мапі — та сама вулиця є в десятку міст.
     */
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

    /**
     * Крапку поставили пальцем — лишається сказати, що це за адреса.
     *
     * Поле й мапа показують одне й те саме, тож рухати його можна з обох боків: обрана підказка
     * веде крапку, поставлена крапка веде поле. Без цього номер будинку мовчки лишався від
     * попередньої адреси — тобто поле брехало про те, куди прийдуть люди.
     *
     * Затримка та сама, що й у підказок: крапку рідко ставлять з першого разу.
     */
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
                        // Підказки під полем стосувались того, що набирали до крапки.
                        addressSuggestions = emptyList()
                    )
                }
                persist()
            }
        }
    }

    /**
     * Що зараз під ціллю.
     *
     * Окремо від [describePoint], бо це інше питання: там крапку вже обрали й пишуть у форму,
     * тут її ще приміряють. Тому й токен окремий — відповіді не мають затирати одна одну.
     */
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

    /**
     * Редагувати можна лише те, що ми проводимо самі: сервер відмовляє в цьому тим самим
     * `assert_event_editable`, і без кімнати редактору просто нічим наповнити половину полів.
     */
    private fun Event.toForm(): EditorForm? {
        val room = gathering ?: return null
        return EditorForm(
            title = title, description = description, category = category, city = city, address = address,
            latitude = latitude.format(), longitude = longitude.format(), timeZone = timeZone,
            starts = startsAt.toLocal(timeZone), ends = endsAt.toLocal(timeZone), capacity = room.capacity.toString(),
            minAge = room.minAge.toString(), maxAge = room.maxAge?.toString().orEmpty(),
            approvalRequired = room.approvalRequired
        )
    }

    private fun String.toLocal(zone: String) = runCatching {
        Instant.parse(this).atZone(ZoneId.of(zone)).toLocalDateTime().format(EditorForm.LOCAL_FORMAT)
    }.getOrDefault("")

    private fun Double.format() = "%.6f".format(java.util.Locale.ROOT, this).trimEnd('0').trimEnd('.')

    private companion object {
        /** Стільки чекаємо, доки мапу перестануть тягати. Геокодер ходить у мережу. */
        const val ZONE_SETTLE_MS = 500L
        /** Те саме для набору адреси. */
        const val ADDRESS_SETTLE_MS = 350L
        /** Коротше за це запит нічого не звужує. */
        const val MIN_ADDRESS_QUERY = 3
        /**
         * Ціль на екрані вибору. Коротше за решту: тут людина дивиться саме на цей рядок і чекає
         * на нього, а мапа вже стоїть — камера повідомляє про зупинку, а не про кожен кадр.
         */
        const val AIM_SETTLE_MS = 200L
    }
}
