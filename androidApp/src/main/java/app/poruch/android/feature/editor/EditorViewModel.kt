package app.poruch.android.feature.editor

import app.poruch.android.mvi.MviViewModel
import app.poruch.domain.Event
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

    init {
        val shared = app.state.value
        val event = editingId?.let { id -> (shared.myEvents + shared.events).firstOrNull { it.id == id } }
        original = event
        reduce {
            copy(
                form = event?.toForm() ?: drafts.load(shared.cityName, shared.cityLatitude, shared.cityLongitude),
                mapLatitude = event?.latitude ?: shared.cityLatitude,
                mapLongitude = event?.longitude ?: shared.cityLongitude
            )
        }
        observe(app) { latest ->
            // Editing an event opened from a deep link: its record may arrive after this screen did.
            val loaded = editingId?.let { id -> latest.selectedEvent?.takeIf { it.id == id } }
            if (loaded != null && original == null) {
                original = loaded
                return@observe copy(form = loaded.toForm(), mapLatitude = loaded.latitude, mapLongitude = loaded.longitude, mutating = latest.mutating)
            }
            if (submitted && latest.completedEventId != null) {
                drafts.clear(); app.clearCompletedEvent(); send(EditorEffect.Close)
            }
            copy(mutating = latest.mutating)
        }
    }

    override fun onIntent(intent: EditorIntent) {
        when (intent) {
            is EditorIntent.Edit -> reduce { copy(form = intent.change(form)) }.also { persist() }
            is EditorIntent.PickPoint -> {
                // Six decimals is about a tenth of a metre — more digits are noise on screen.
                reduce { copy(form = form.copy(latitude = intent.latitude.format(), longitude = intent.longitude.format())) }
                persist()
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

    private fun Event.toForm() = EditorForm(
        title = title, description = description, category = category, city = city, address = address,
        latitude = latitude.format(), longitude = longitude.format(), timeZone = timeZone,
        starts = startsAt.toLocal(timeZone), ends = endsAt.toLocal(timeZone), capacity = capacity.toString()
    )

    private fun String.toLocal(zone: String) = runCatching {
        Instant.parse(this).atZone(ZoneId.of(zone)).toLocalDateTime().format(EditorForm.LOCAL_FORMAT)
    }.getOrDefault("")

    private fun Double.format() = "%.6f".format(java.util.Locale.ROOT, this).trimEnd('0').trimEnd('.')
}
