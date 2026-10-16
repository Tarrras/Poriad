package app.poruch.android.feature.editor

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.MapController
import app.poruch.android.MapZoom
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.ContactRules
import app.poruch.domain.DraftField
import app.poruch.domain.EventRules
import app.poruch.domain.SafetyRules
import app.poruch.domain.TitleRules
import java.time.LocalDateTime

@Composable
fun EditorScreen(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    // Системний «назад» — крок назад, з першого кроку — закрити майстер тим самим шляхом, що й хрестик.
    BackHandler { onIntent(if (state.step != EditorStep.ABOUT) EditorIntent.Back else EditorIntent.Close) }
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding().imePadding()) {
        WizardHeader(state, onIntent)
        val scroll = rememberScrollState()
        // Новий крок починається згори: інакше заголовок питання лишався за краєм, прокрученим ще на минулому.
        LaunchedEffect(state.step) { scroll.scrollTo(0) }
        Column(
            Modifier.weight(1f).verticalScroll(scroll).padding(Spacing.page),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            // Квиток друкується згори, поки людина відповідає: той самий, що побачать у «Від людей».
            DraftTicket(state)
            // Кожен крок — одне питання великим заголовком, як в онбордингу.
            Column(Modifier.padding(bottom = Spacing.xs), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                // Номер кроку словами: смужки згори кажуть «скільки», а не «котрий». Без капсу: «КРОК 1 З 4»
                // у цьому шрифті читалось як «1 3 4».
                Text(
                    stringResource(R.string.onboarding_step, state.step.ordinal + 1, EditorStep.entries.size),
                    style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary, modifier = Modifier.decorative()
                )
                Text(
                    stringResource(state.step.headline), style = PoruchType.brandDisplay, color = colors.ink,
                    modifier = Modifier.semantics { heading() }
                )
                Text(stringResource(state.step.hint), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            }
            when (state.step) {
                EditorStep.ABOUT -> AboutStep(state, onIntent)
                EditorStep.PLACE -> PlaceStep(state, onIntent)
                EditorStep.SCHEDULE -> ScheduleStep(state, onIntent)
                EditorStep.PEOPLE -> PeopleStep(state, onIntent)
            }
        }
        Column(
            Modifier.fillMaxWidth().background(colors.surface).navigationBarsPadding().padding(Spacing.page),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            // Над кнопкою, бо поле з помилкою може бути за краєм або під клавіатурою.
            (state.failure?.text() ?: state.stepProblems.firstOrNull()?.takeIf { state.showProblems }?.rule())?.let {
                // Червоний рядок TalkBack сам не помітить: кажемо його, щойно він з'явився чи змінився.
                Text(
                    it, style = MaterialTheme.typography.bodyMedium, color = colors.danger,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }
                )
            }
            val back: @Composable (Modifier) -> Unit = { modifier ->
                if (state.step != EditorStep.ABOUT) SecondaryButton(stringResource(R.string.back), { onIntent(EditorIntent.Back) }, modifier)
            }
            // Активна й з помилками: тап показує, що виправити, замість мовчазної сірої кнопки.
            val primary: @Composable (Modifier) -> Unit = { modifier ->
                PrimaryButton(
                    stringResource(if (!state.step.isLast) R.string.next else if (state.editing) R.string.apply else R.string.publish),
                    { onIntent(if (state.step.isLast) EditorIntent.Submit else EditorIntent.Next) },
                    modifier, enabled = !state.mutating, loading = state.mutating
                )
            }
            // На великому шрифті дві кнопки поруч не вміщають напис — ставимо одна під одною.
            if (LocalDensity.current.fontScale > LARGE_FONT_SCALE) Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                back(Modifier.fillMaxWidth()); primary(Modifier.fillMaxWidth())
            } else Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
                back(Modifier.weight(1f)); primary(Modifier.weight(1f))
            }
        }
    }

    if (state.pickingPoint) PointPicker(state, onIntent)

    state.discarding?.let { what ->
        val changes = what == Discard.CHANGES
        PoruchConfirmSheet(
            title = stringResource(if (changes) R.string.editor_discard_title else R.string.editor_start_over_title),
            message = stringResource(if (changes) R.string.editor_discard_explain else R.string.editor_start_over_explain),
            confirmLabel = stringResource(if (changes) R.string.editor_discard else R.string.editor_delete_draft),
            dismissLabel = stringResource(R.string.editor_keep_editing),
            onConfirm = { onIntent(EditorIntent.ConfirmDiscard(what)) },
            onDismiss = { onIntent(EditorIntent.AskDiscard(null)) },
            tone = colors.danger
        )
    }

    state.picker?.let { request ->
        val startsAt = state.form.parse(state.form.starts)
        DateTimeSheet(
            initial = when (request) {
                PickerRequest.STARTS -> startsAt ?: LocalDateTime.now().plusDays(1).withMinute(0)
                PickerRequest.ENDS -> state.form.parse(state.form.ends) ?: startsAt?.plusHours(2) ?: LocalDateTime.now().plusDays(1).withMinute(0)
            },
            // Кінець не раніше початку.
            minimum = if (request == PickerRequest.ENDS) startsAt else null,
            onDismiss = { onIntent(EditorIntent.ShowPicker(null)) },
            onPicked = { onIntent(EditorIntent.SetDateTime(request, it)) }
        )
    }
}

private fun EditorForm.parse(value: String) =
    runCatching { LocalDateTime.parse(value, EditorForm.LOCAL_FORMAT) }.getOrNull()

/** Закрити, прогрес трьома сегментами і назва режиму. Той самий ряд, що в онбордингу. */
@Composable
private fun WizardHeader(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    // Шапка — хром: шрифт росте до 1.3, далі напис справа витісняв смужки прогресу в нуль. Те саме, що xxLarge на iOS.
    val density = LocalDensity.current
    androidx.compose.runtime.CompositionLocalProvider(
        LocalDensity provides androidx.compose.ui.unit.Density(density.density, density.fontScale.coerceAtMost(LARGE_FONT_SCALE))
    ) { WizardHeaderRow(state, onIntent) }
}

@Composable
private fun WizardHeaderRow(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    // «Крок 2 з 3: Місце» — і як назва індикатора, і як оголошення, коли крок змінився.
    val stepLabel = stringResource(R.string.onboarding_step, state.step.ordinal + 1, EditorStep.entries.size) +
        ": " + stringResource(state.step.label)
    Row(
        Modifier.fillMaxWidth().height(56.dp).padding(horizontal = Spacing.page),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        IconPill(PoruchIcons.close, stringResource(R.string.close), size = 40.dp, onClick = { onIntent(EditorIntent.Close) })
        Row(
            Modifier.weight(1f).clearAndSetSemantics { contentDescription = stepLabel; liveRegion = LiveRegionMode.Polite },
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            EditorStep.entries.forEach { entry ->
                val tint by animateColorAsState(
                    if (entry.ordinal <= state.step.ordinal) colors.brand else colors.brandContainer,
                    animationSpec = Motion.quick(Poruch.reducedMotion), label = "step"
                )
                Box(Modifier.weight(1f).height(4.dp).background(tint, Radius.pill))
            }
        }
        if (state.canStartOver) GhostButton(
            stringResource(R.string.editor_start_over), { onIntent(EditorIntent.AskDiscard(Discard.DRAFT)) },
            tone = colors.inkSecondary, enabled = !state.mutating
        ) else Text(
            stringResource(if (state.editing) R.string.editor_mode_edit else R.string.editor_mode_new),
            style = MaterialTheme.typography.labelLarge, color = colors.inkSecondary
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AboutStep(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val form = state.form
    val description = form.description.trim().length
    LabelledField(
        stringResource(R.string.title), form.title,
        { value -> onIntent(EditorIntent.Edit { copy(title = value.take(EventRules.titleLength.last)) }) },
        placeholder = stringResource(R.string.title_placeholder), error = state.problem(DraftField.TITLE),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Next)
    )
    LabelledField(
        stringResource(R.string.description), form.description,
        { value -> onIntent(EditorIntent.Edit { copy(description = value.take(EventRules.descriptionLength.last)) }) },
        placeholder = stringResource(R.string.description_placeholder), singleLine = false,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        hint = EventRules.descriptionLength.let { rule ->
            if (description < rule.first) stringResource(R.string.description_counter_min, description, rule.first)
            else stringResource(R.string.description_counter, description, rule.last)
        },
        error = state.problem(DraftField.DESCRIPTION)
    )
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(
            stringResource(R.string.category_single).uppercase(), style = MaterialTheme.typography.labelSmall,
            color = Poruch.colors.inkTertiary
        )
        // Ті самі плитки, що в шторці категорій пошуку: жанр обирають однаково скрізь. Усі одинадцять видно одразу.
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            categories.forEach { key ->
                CategoryTile(key, form.category == key) { onIntent(EditorIntent.Edit { copy(category = key) }) }
            }
        }
        state.problem(DraftField.CATEGORY)?.let { FieldError(it) }
    }
}

/** Правило поля, якщо людина вже натиснула «Далі», а воно не пройшло. */
@Composable
private fun EditorState.problem(field: DraftField): String? =
    if (showProblems && field in stepProblems) field.rule() else null

@Composable
private fun FieldError(text: String) =
    Text(text, style = MaterialTheme.typography.bodySmall, color = Poruch.colors.danger)

@Composable
private fun PlaceStep(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val form = state.form
    LabelledField(
        stringResource(R.string.city), form.city, { value -> onIntent(EditorIntent.Edit { copy(city = value) }) },
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next)
    )
    LabelledField(
        stringResource(R.string.address), form.address, { value -> onIntent(EditorIntent.Edit { copy(address = value) }) },
        placeholder = stringResource(R.string.address_placeholder),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        hint = stringResource(R.string.address_hint), error = state.problem(DraftField.ADDRESS)
    )
    // Підказки одразу під полем, як продовження набору.
    if (state.addressSuggestions.isNotEmpty()) Column(
        Modifier.fillMaxWidth().cardSurface(), verticalArrangement = Arrangement.spacedBy(0.dp)
    ) {
        state.addressSuggestions.forEachIndexed { index, place ->
            if (index > 0) HairLine()
            Row(
                Modifier.fillMaxWidth().clickable(role = Role.Button) { onIntent(EditorIntent.PickAddress(place)) }
                    .padding(Spacing.lg),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                Icon(PoruchIcons.pin, null, Modifier.size(18.dp), tint = colors.inkSecondary)
                Column(Modifier.weight(1f)) {
                    Text(place.label, style = MaterialTheme.typography.bodyLarge, color = colors.ink)
                    if (place.detail.isNotBlank()) Text(
                        place.detail, style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary,
                        maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
    Text(
        stringResource(if (state.pointChosen) R.string.address_point_set else R.string.address_or_map),
        style = MaterialTheme.typography.bodySmall,
        color = if (state.pointChosen) colors.success else colors.inkTertiary
    )
    state.problem(DraftField.LOCATION)?.let { FieldError(it) }
    // Мапа лише показує вибране: жести на 260 dp коштували б точності.
    Box(Modifier.fillMaxWidth().height(260.dp).clip(Radius.md)) {
        EventMap(
            emptyList(), state.mapLatitude, state.mapLongitude,
            chosenPoint = state.point, interactive = false,
            // Є крапка — показуємо будинок, а не місто.
            centerZoom = if (state.pointChosen) MapZoom.street else MapZoom.city
        )
    }
    SecondaryButton(
        stringResource(if (state.pointChosen) R.string.change_point else R.string.choose_point),
        { onIntent(EditorIntent.ShowPointPicker(true)) },
        Modifier.fillMaxWidth()
    )
}

/** Кругла кнопка масштабу поверх мапи. */
@Composable
private fun ZoomButton(icon: ImageVector, label: Int, onClick: () -> Unit) {
    val colors = Poruch.colors
    Box(
        Modifier.size(48.dp).background(colors.surface, androidx.compose.foundation.shape.CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, stringResource(label), Modifier.size(20.dp), tint = colors.ink)
    }
}

/** Повноекранна мапа з ціллю в центрі: рухається світ під нею, крапку не затуляє палець. */
@Composable
private fun PointPicker(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val start = state.point ?: (state.mapLatitude to state.mapLongitude)
    var center by remember { mutableStateOf(start) }
    val controller = remember { MapController() }
    Dialog(
        onDismissRequest = { onIntent(EditorIntent.ShowPointPicker(false)) },
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(Modifier.fillMaxSize().background(colors.canvas)) {
            EventMap(
                emptyList(), start.first, start.second,
                modifier = Modifier.fillMaxSize(),
                centerZoom = if (state.pointChosen) MapZoom.street else MapZoom.city,
                controller = controller,
                // Камера повідомляє про зупинку, а не про кожен кадр.
                onCenterChanged = { latitude, longitude ->
                    center = latitude to longitude
                    onIntent(EditorIntent.AimAt(latitude, longitude))
                }
            )
            // Ціль не приймає дотиків: мапа під нею має тягтися.
            Icon(
                PoruchIcons.pin, null,
                Modifier.align(Alignment.Center).size(36.dp).offset(y = (-18).dp),
                tint = colors.brand
            )
            Column(Modifier.fillMaxWidth().statusBarsPadding()) {
                // Модальний екран: «Скасувати» справа, а не стрілка «назад».
                PageHeader(
                    stringResource(R.string.choose_point_title),
                    trailing = {
                        GhostButton(stringResource(R.string.cancel), { onIntent(EditorIntent.ShowPointPicker(false)) }, tone = colors.inkSecondary)
                    }
                )
            }
            Column(
                Modifier.align(Alignment.CenterEnd).padding(Spacing.lg),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                ZoomButton(PoruchIcons.plus, R.string.zoom_in) { controller.zoomIn() }
                ZoomButton(PoruchIcons.minus, R.string.zoom_out) { controller.zoomOut() }
            }
            Column(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(colors.surface)
                    .navigationBarsPadding().padding(Spacing.page),
                verticalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                // Адреса тут головна, тож і виглядає як головна.
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                    Icon(PoruchIcons.pin, null, Modifier.size(18.dp), tint = colors.inkSecondary)
                    Column(Modifier.weight(1f)) {
                        Text(
                            state.aimAddress.ifBlank { stringResource(R.string.point_searching) },
                            style = MaterialTheme.typography.bodyLarge,
                            color = if (state.aimAddress.isBlank()) colors.inkTertiary else colors.ink,
                            maxLines = 2, overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            stringResource(R.string.choose_point_hint),
                            style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
                        )
                    }
                }
                PrimaryButton(
                    stringResource(R.string.apply),
                    { onIntent(EditorIntent.PickPoint(center.first, center.second)) },
                    Modifier.fillMaxWidth()
                )
            }
        }
    }
}

/**
 * Пояс події, коли година на телефоні була б іншою: тоді години вище йдуть за чужим годинником, і це треба сказати.
 * Свій час — норма, про нього мовчимо. Порівнюємо зсув на дату події, а не назви: Kiev і Kyiv — один годинник,
 * а літній і зимовий час різняться. Те саме, що `TimeZoneNote` на iOS.
 */
@Composable
private fun TimeZoneNote(zone: String, city: String, at: LocalDateTime?) {
    val colors = Poruch.colors
    val resolved = runCatching { java.time.ZoneId.of(zone) }.getOrNull() ?: return
    val instant = (at ?: LocalDateTime.now()).atZone(resolved).toInstant()
    val offset = resolved.rules.getOffset(instant)
    if (offset == java.time.ZoneId.systemDefault().rules.getOffset(instant)) return
    // «GMT+1», «GMT+5:30»: ZoneOffset пише «+05:30», а людина звіряє з годинником.
    val seconds = offset.totalSeconds
    val gmt = "GMT${if (seconds < 0) "−" else "+"}${kotlin.math.abs(seconds) / 3600}" +
        (kotlin.math.abs(seconds) % 3600 / 60).takeIf { it > 0 }?.let { ":%02d".format(it) }.orEmpty()
    Row(
        Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg).semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(PoruchIcons.clock, null, Modifier.size(20.dp), tint = colors.inkSecondary)
        Column(Modifier.weight(1f)) {
            Text(
                stringResource(R.string.timezone).uppercase(),
                style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary
            )
            Text(stringResource(R.string.timezone_local, city.ifBlank { zone }, gmt), style = MaterialTheme.typography.bodyLarge, color = colors.ink)
            Text(stringResource(R.string.timezone_differs), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        }
    }
}

@Composable
private fun ScheduleStep(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val form = state.form
    // «Сб, 17 жовт. · 19:00», як на iOS; у чернетці лишається машинний формат. Година — як на телефоні.
    val hour = if (android.text.format.DateFormat.is24HourFormat(androidx.compose.ui.platform.LocalContext.current)) "HH:mm" else "h:mm a"
    val words = remember(hour) { java.time.format.DateTimeFormatter.ofPattern("EEE, d MMM · $hour", java.util.Locale.forLanguageTag("uk")) }
    fun shown(value: String) = form.parse(value)?.format(words)?.replaceFirstChar { it.uppercase() }.orEmpty()
    DateTimeField(stringResource(R.string.starts), shown(form.starts), state.problem(DraftField.STARTS_AT)) {
        onIntent(EditorIntent.ShowPicker(PickerRequest.STARTS))
    }
    DateTimeField(stringResource(R.string.ends), shown(form.ends), state.problem(DraftField.ENDS_AT)) {
        onIntent(EditorIntent.ShowPicker(PickerRequest.ENDS))
    }
    TimeZoneNote(form.timeZone, form.city, form.parse(form.starts))
    state.problem(DraftField.TIME_ZONE)?.let { FieldError(it) }
}

/** Хто може прийти — окремий крок, а не хвіст «Коли»: місця, вік, погодження й чат — частина публікації. */
@Composable
private fun PeopleStep(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val form = state.form
    LabelledField(
        stringResource(R.string.capacity), form.capacity, { value -> onIntent(EditorIntent.Edit { copy(capacity = value.filter(Char::isDigit).take(5)) }) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next), error = state.problem(DraftField.CAPACITY)
    )
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
            LabelledField(
                stringResource(R.string.age_from), form.minAge,
                { value -> onIntent(EditorIntent.Edit { copy(minAge = value.filter(Char::isDigit).take(3)) }) },
                Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next)
            )
            LabelledField(
                stringResource(R.string.age_to), form.maxAge,
                { value -> onIntent(EditorIntent.Edit { copy(maxAge = value.filter(Char::isDigit).take(3)) }) },
                Modifier.weight(1f), placeholder = stringResource(R.string.age_to_placeholder),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next)
            )
        }
        Text(
            stringResource(R.string.age_limit_hint, SafetyRules.MIN_SIGNUP_AGE),
            style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
        )
        state.problem(DraftField.AGE_LIMITS)?.let { FieldError(it) }
        // Перемикає весь рядок: так TalkBack читає підпис разом зі станом, а ціль дотику — уся картка.
        Row(
            Modifier.fillMaxWidth().cardSurface()
                .toggleable(form.approvalRequired, role = Role.Switch) { value ->
                    onIntent(EditorIntent.Edit { copy(approvalRequired = value) })
                }
                .padding(Spacing.lg),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.approval_label), style = MaterialTheme.typography.titleSmall, color = colors.ink)
                Text(stringResource(R.string.approval_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
            }
            PoruchSwitch(form.approvalRequired, null)
        }
        // Чат — єдиний канал до учасників. Лише https: решту відкидає і чернетка, і сервер.
        LabelledField(
            stringResource(R.string.contact_label), form.contactUrl,
            { value -> onIntent(EditorIntent.Edit { copy(contactUrl = value.take(ContactRules.MAX_URL_LENGTH)) }) },
            placeholder = stringResource(R.string.contact_placeholder),
            hint = stringResource(R.string.contact_editor_hint),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done)
        )
        if (form.contactUrl.isNotBlank() && !ContactRules.isContactUrl(form.contactUrl)) FieldError(DraftField.CONTACT_URL.rule())
    }
    Text(stringResource(R.string.photo_after_publish), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
}

/** Поле дати виглядає як решта полів, але відкриває пікер замість клавіатури. */
@Composable
private fun DateTimeField(label: String, value: String, error: String?, onOpen: () -> Unit) {
    val colors = Poruch.colors
    val shown = value.ifBlank { stringResource(R.string.date_help) }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(
            label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary,
            modifier = Modifier.clearAndSetSemantics { }
        )
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp).background(colors.surface, Radius.sm)
                .clip(Radius.sm).clickable(role = Role.Button, onClick = onOpen)
                // Назва поля разом зі значенням і помилкою — одна зупинка TalkBack, як у текстових полів.
                .clearAndSetSemantics {
                    contentDescription = "$label: $shown"; role = Role.Button
                    onClick { onOpen(); true }
                    if (error != null) error(error)
                }
                .padding(horizontal = Spacing.lg),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(PoruchIcons.clock, null, Modifier.size(20.dp), tint = colors.inkSecondary)
            Text(
                shown, style = MaterialTheme.typography.bodyLarge,
                color = if (value.isBlank()) colors.inkTertiary else colors.ink, modifier = Modifier.weight(1f)
            )
            Icon(PoruchIcons.chevronRight, null, Modifier.size(20.dp), tint = colors.inkTertiary)
        }
        error?.let { FieldError(it) }
    }
}

/**
 * Квиток «Від людей», що друкується з форми: незаповнене — сірі смуги, як на порожньому квитку, заповнене проступає
 * текстом. Корінець одразу кольору жанру; година, день і місця — коли обрано початок. Для TalkBack він повтор форми,
 * тож прихований. Те саме, що `DraftTicket` на iOS.
 */
@Composable
private fun DraftTicket(state: EditorState) {
    val colors = Poruch.colors
    val form = state.form
    val title = form.title.trim()
    val place = form.address.trim()
    val words = dateWords()
    val start = remember(form.starts, form.timeZone) {
        runCatching { form.parse(form.starts)?.atZone(java.time.ZoneId.of(form.timeZone)) }.getOrNull()
    }
    val (big, small) = start?.let { draftStubParts(it, words) } ?: ("––:––" to "")
    val motion = Motion.quick<IntSize>(Poruch.reducedMotion)
    Ticket(
        categoryStub(form.category),
        stub = {
            val day = PoruchType.overline.copy(color = Color.White, letterSpacing = 0.6.sp)
            Row(
                Modifier.fillMaxWidth().padding(horizontal = Spacing.md),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(stringResource(categoryLabel(form.category)).uppercase(), style = day, maxLines = 1)
                    Text(big, style = PoruchType.numeral.copy(color = Color.White, fontFeatureSettings = "tnum"), maxLines = 1)
                }
                if (start != null) Column(Modifier.weight(1f), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(small, style = day, maxLines = 1)
                    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(PoruchIcons.social, null, Modifier.size(12.dp), tint = Color.White)
                        Text("${state.taken}/${form.capacity.ifBlank { "0" }}", style = day.copy(fontFeatureSettings = "tnum"))
                    }
                }
            }
        },
        // Вертикальний квиток бере висоту від місця виклику: у прокрутці її нема, і без Min основа сплющувалась у нуль.
        modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min).decorative(),
        vertical = true, stubLength = 64.dp
    ) {
        Column(
            Modifier.animateContentSize(motion).padding(start = Spacing.md, end = Spacing.md, top = Spacing.md, bottom = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            if (title.isEmpty()) { Blank(160.dp, 12.dp); Blank(96.dp, 12.dp) }
            else Text(TitleRules.display(title), style = PoruchType.brandTitle2, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            state.host?.let { host ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(host, null, 20.dp)
                    Text(stringResource(R.string.hosted_by, host), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 1)
                }
            }
            Spacer(Modifier.height(Spacing.sm))
            if (place.isEmpty()) Blank(120.dp, 6.dp) else MetaLine(PoruchIcons.pin, place)
        }
    }
}

/** Ще не надрукований рядок квитка. */
@Composable
private fun Blank(width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp) =
    Box(Modifier.padding(vertical = 3.dp).size(width, height).background(Poruch.colors.hairline, Radius.pill))

/** Звідки кнопки підвалу стають одна під одною: 1.3 — найбільший системний шрифт без «екстра». */
private const val LARGE_FONT_SCALE = 1.3f

private val EditorStep.headline: Int
    get() = when (this) {
        EditorStep.ABOUT -> R.string.editor_about_title
        EditorStep.PLACE -> R.string.editor_place_title
        EditorStep.SCHEDULE -> R.string.editor_schedule_title
        EditorStep.PEOPLE -> R.string.editor_people_title
    }

private val EditorStep.hint: Int
    get() = when (this) {
        EditorStep.ABOUT -> R.string.editor_about_hint
        EditorStep.PLACE -> R.string.editor_place_hint
        EditorStep.SCHEDULE -> R.string.editor_schedule_hint
        EditorStep.PEOPLE -> R.string.editor_people_hint
    }

private val EditorStep.label: Int
    get() = when (this) {
        EditorStep.ABOUT -> R.string.step_one
        EditorStep.PLACE -> R.string.step_two
        EditorStep.SCHEDULE -> R.string.step_three
        EditorStep.PEOPLE -> R.string.step_four
    }
