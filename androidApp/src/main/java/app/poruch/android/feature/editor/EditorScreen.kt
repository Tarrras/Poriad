package app.poruch.android.feature.editor

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
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
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
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
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.MapController
import app.poruch.android.MapZoom
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.ContactRules
import app.poruch.domain.DraftField
import app.poruch.domain.EventRules
import app.poruch.domain.LegalLinks
import app.poruch.domain.MeetupTemplate
import app.poruch.domain.QuickDayKind
import app.poruch.domain.QuickEvent
import app.poruch.domain.SafetyRules
import app.poruch.domain.TitleRules
import java.time.LocalDateTime

@Composable
fun EditorScreen(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    // Типовий опис за шаблоном: ним публікація заповнює порожнє поле (сервер без опису подію не прийме).
    val about = stringResource(state.form.template.about)
    // «Назад» перехоплюємо, лише коли є що берегти: поки публікується (ковтаємо) і в зміненій правці (питаємо). Решту
    // закриває сам NavDisplay з передбачуваним «назад» — хрестик веде туди ж (чернетка нової зберігається й так).
    BackHandler(state.publishing || state.mutating || state.changed) { if (!state.publishing) onIntent(EditorIntent.Close) }
    EditorBody(state, about, onIntent)

    if (state.pickingPoint) PointPicker(state, onIntent)
    if (state.publishing) PublishingOverlay(state)

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
            // Шторка закриває поля, тож заголовок каже, яке з них міняють.
            title = stringResource(
                when (request) {
                    PickerRequest.STARTS -> if (state.pickerTime) R.string.start_time else R.string.start_date
                    PickerRequest.ENDS -> if (state.pickerTime) R.string.end_time else R.string.end_date
                }
            ),
            time = state.pickerTime,
            onDismiss = { onIntent(EditorIntent.ShowPicker(null)) },
            onPicked = { onIntent(EditorIntent.SetDateTime(request, it)) }
        )
    }
}

/**
 * Куди веде відмова «Опублікувати»: розділ першого поля з помилкою — у видиму частину, а назва чи адреса ще й
 * отримують фокус (клавіатура одразу там, де треба набирати). Решта полів — без фокусу, щоб клавіатура не закривала їх.
 */
@OptIn(ExperimentalFoundationApi::class)
private class EditorFocus {
    val title = FocusRequester()
    val address = FocusRequester()
    val what = BringIntoViewRequester()
    val time = BringIntoViewRequester()
    val place = BringIntoViewRequester()
    val people = BringIntoViewRequester()
    val more = BringIntoViewRequester()
}

/** Шапка, форма й кнопка публікації. Окремо від шторок і системного «назад»: так її малює прев'ю. */
@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
private fun EditorBody(state: EditorState, about: String, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val focus = remember { EditorFocus() }
    val focusManager = LocalFocusManager.current
    LaunchedEffect(state.jump) {
        val field = state.problems.firstOrNull()?.takeIf { state.jump > 0 } ?: return@LaunchedEffect
        when (field) {
            DraftField.TITLE -> { focus.what.bringIntoView(); focus.title.requestFocus() }
            DraftField.ADDRESS, DraftField.LOCATION -> { focus.place.bringIntoView(); focus.address.requestFocus() }
            DraftField.STARTS_AT -> { focusManager.clearFocus(); focus.time.bringIntoView() }
            DraftField.CAPACITY -> { focusManager.clearFocus(); focus.people.bringIntoView() }
            else -> { focusManager.clearFocus(); focus.more.bringIntoView() }
        }
    }
    // Адреса з фокусом і відкритою клавіатурою — розділ «Де» вгору цілком: інакше поле лягало на край клавіатури,
    // а рядок під ним і підказки, що з'являються під полем, опинялись під нею.
    var placeFocused by remember { mutableStateOf(false) }
    val imeVisible = WindowInsets.isImeVisible
    LaunchedEffect(imeVisible, placeFocused, state.addressSuggestions.size) {
        if (imeVisible && placeFocused) focus.place.bringIntoView()
    }
    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding().imePadding()) {
        EditorHeader(state, onIntent)
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(Spacing.page),
            verticalArrangement = Arrangement.spacedBy(Spacing.xxl)
        ) {
            // Квиток друкується згори, поки людина відповідає: той самий, що побачать у «Від людей».
            DraftTicket(state)
            // Готовий пост з Threads заповнює все одразу — тож над назвою, а не під «Ще». Лише для нової.
            if (!state.editing) AnnounceCard(state, onIntent)
            // Чотири питання на одному екрані — хвилина від «+» до посилання; решта під «Ще».
            Box(Modifier.bringIntoViewRequester(focus.what)) { WhatSection(state, onIntent, focus.title) }
            Box(Modifier.bringIntoViewRequester(focus.time)) { WhenSection(state, onIntent) }
            Box(Modifier.bringIntoViewRequester(focus.place)) { WhereSection(state, onIntent, focus.address) { placeFocused = it } }
            Box(Modifier.bringIntoViewRequester(focus.people)) { PeopleSection(state, onIntent) }
            Box(Modifier.bringIntoViewRequester(focus.more)) { MoreSection(state, about, onIntent) }
            // Правка: застосунок показує прості поля, а склад, серію й оплату онлайн веде кабінет — і не стирає їх.
            state.cabinet?.let { url -> CabinetLine(R.string.quick_full_settings) { onIntent(EditorIntent.OpenCabinet(url)) } }
        }
        // Поки відкрита клавіатура, кнопки нема: удвох вони лишали формі чверть екрана, а підказки адрес ховались під
        // кнопкою. «Готово» на клавіатурі ховає її — і кнопка повертається.
        if (!imeVisible) Column(
            Modifier.fillMaxWidth().background(colors.surface).navigationBarsPadding().padding(Spacing.page),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            // Файл ще стискається: «Опублікувати» чекає на нього.
            if (state.importing > 0) Text(
                stringResource(R.string.media_compressing), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary
            )
            // Публікація вантажить файли по черзі: без рядка спінер на кнопці висів би мовчки.
            state.upload?.let {
                Text(
                    stringResource(R.string.media_uploading, it.current, it.total), style = MaterialTheme.typography.bodyMedium,
                    color = colors.inkSecondary, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }
                )
            }
            // Над кнопкою, бо поле з помилкою може бути за краєм або під клавіатурою.
            (state.failure?.text() ?: state.problems.firstOrNull()?.takeIf { state.showProblems }?.rule())?.let {
                // Червоний рядок TalkBack сам не помітить: кажемо його, щойно він з'явився чи змінився.
                Text(
                    it, style = MaterialTheme.typography.bodyMedium, color = colors.danger,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }
                )
            }
            // Активна й з помилками: тап показує, що виправити, замість мовчазної сірої кнопки.
            PrimaryButton(
                stringResource(if (state.editing) R.string.apply else R.string.publish), { onIntent(EditorIntent.Submit(about)) },
                Modifier.fillMaxWidth(), enabled = !state.mutating && state.importing == 0, loading = state.mutating
            )
        }
    }
}

private fun EditorForm.parse(value: String) =
    runCatching { LocalDateTime.parse(value, EditorForm.LOCAL_FORMAT) }.getOrNull()

/** Закрити, назва режиму і «Почати заново». Шапка — хром: шрифт росте до 1.3, як xxLarge на iOS. */
@Composable
private fun EditorHeader(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val density = LocalDensity.current
    androidx.compose.runtime.CompositionLocalProvider(
        LocalDensity provides androidx.compose.ui.unit.Density(density.density, density.fontScale.coerceAtMost(LARGE_FONT_SCALE))
    ) {
        Row(
            Modifier.fillMaxWidth().height(56.dp).padding(horizontal = Spacing.page),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            IconPill(PoruchIcons.close, stringResource(R.string.close), size = 40.dp, onClick = { onIntent(EditorIntent.Close) })
            Text(
                stringResource(if (state.editing) R.string.editor_mode_edit else R.string.create_choice_own),
                Modifier.weight(1f).semantics { heading() }, style = PoruchType.brandTitle3, color = colors.ink, maxLines = 1
            )
            if (state.canStartOver) GhostButton(
                stringResource(R.string.editor_start_over), { onIntent(EditorIntent.AskDiscard(Discard.DRAFT)) },
                tone = colors.inkSecondary, enabled = !state.mutating
            )
        }
    }
}

/** Питання секції тим самим голосом, що назва на квитку, і відповідь під ним. */
@Composable
private fun Section(question: Int, content: @Composable ColumnScope.() -> Unit) =
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        Text(stringResource(question), style = PoruchType.brandTitle2, color = Poruch.colors.ink, modifier = Modifier.semantics { heading() })
        content()
    }

/** «Що»: назва й шаблони. Шаблон одним тапом ставить назву, жанр (колір корінця), місця й тривалість. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WhatSection(state: EditorState, onIntent: (EditorIntent) -> Unit, focus: FocusRequester? = null) = Section(R.string.editor_about_title) {
    val form = state.form
    LabelledField(
        stringResource(R.string.title), form.title,
        { value -> onIntent(EditorIntent.Edit { copy(title = value.take(EventRules.titleLength.last)) }) },
        placeholder = stringResource(R.string.quick_title_placeholder), error = state.problem(DraftField.TITLE),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
        focusRequester = focus
    )
    // У правці шаблонів нема: тап переписав би місця, жанр і кінець уже опублікованої події.
    if (!state.editing) {
        val previous = form.template?.let { stringResource(it.label) }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            MeetupTemplate.entries.forEach { template ->
                val label = stringResource(template.label)
                PoruchChip(label, form.template == template, {
                    onIntent(EditorIntent.PickTemplate(template, QuickEvent.title(form.title, previous, label)))
                }, dot = template.category)
            }
        }
    }
}

/** «Коли»: день одним тапом — сьогодні, завтра, найближчий вихідний чи інша дата — і година поруч. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WhenSection(state: EditorState, onIntent: (EditorIntent) -> Unit) = Section(R.string.editor_schedule_title) {
    val form = state.form
    val now = remember(form.starts) { System.currentTimeMillis() }
    val days = remember(now, form.timeZone) { QuickEvent.days(now, form.timeZone) }
    val picked = form.startMillis?.let { QuickEvent.dayOf(it, now, form.timeZone) }
    // «Пт, 20 лист.» і «19:00»: 24 години, як на корінці квитка над формою й скрізь у застосунку.
    val dates = remember { java.time.format.DateTimeFormatter.ofPattern("EEE, d MMM", java.util.Locale.forLanguageTag("uk")) }
    val hours = remember { java.time.format.DateTimeFormatter.ofPattern(HOUR_FORMAT) }
    val start = form.parse(form.starts)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        days.forEach { day ->
            val label = when (day.kind) {
                QuickDayKind.TODAY -> R.string.today
                QuickDayKind.TOMORROW -> R.string.tomorrow
                QuickDayKind.WEEKEND -> if (day.sunday) R.string.quick_sunday else R.string.quick_saturday
            }
            PoruchChip(stringResource(label), picked == day.kind, { onIntent(EditorIntent.PickDay(day)) })
        }
        // Інша дата — чип із самим днем, коли його обрано: «Пт, 20 лист.».
        PoruchChip(
            start?.takeIf { picked == null }?.format(dates)?.replaceFirstChar { it.uppercase() } ?: stringResource(R.string.quick_other_date),
            start != null && picked == null, { onIntent(EditorIntent.ShowPicker(PickerRequest.STARTS)) },
            icon = PoruchIcons.calendar, trailingIcon = PoruchIcons.chevronDown
        )
        PoruchChip(
            start?.format(hours) ?: stringResource(R.string.time), false, { onIntent(EditorIntent.ShowPicker(PickerRequest.STARTS, time = true)) },
            icon = PoruchIcons.clock, trailingIcon = PoruchIcons.chevronDown
        )
    }
    state.problem(DraftField.STARTS_AT)?.let { FieldError(it) }
}

/** «Де»: адреса з підказками або точка на мапі. Мапа — лише підтвердження вибраного, тож з'являється з крапкою. */
@Composable
private fun WhereSection(
    state: EditorState, onIntent: (EditorIntent) -> Unit, focus: FocusRequester? = null, onFocus: (Boolean) -> Unit = {}
) = Section(R.string.editor_place_title) {
    val colors = Poruch.colors
    val form = state.form
    val focusManager = LocalFocusManager.current
    LabelledField(
        stringResource(R.string.address), form.address, { value -> onIntent(EditorIntent.Edit { copy(address = value) }) },
        placeholder = stringResource(R.string.address_placeholder),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        error = state.problem(DraftField.ADDRESS), focusRequester = focus,
        modifier = Modifier.onFocusChanged { onFocus(it.hasFocus) }
    )
    // Підказки одразу під полем, як продовження набору.
    if (state.addressSuggestions.isNotEmpty()) Column(
        Modifier.fillMaxWidth().cardSurface(), verticalArrangement = Arrangement.spacedBy(0.dp)
    ) {
        state.addressSuggestions.forEachIndexed { index, place ->
            if (index > 0) HairLine()
            Row(
                // Адресу обрано — клавіатура більше не потрібна: вона закривала мапу з точкою й «Опублікувати».
                Modifier.fillMaxWidth().clickable(role = Role.Button) { focusManager.clearFocus(); onIntent(EditorIntent.PickAddress(place)) }
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
    // Мапа лише показує вибране: жести на такій висоті коштували б точності.
    if (state.pointChosen) Box(Modifier.fillMaxWidth().height(140.dp).clip(Radius.md)) {
        EventMap(emptyList(), state.mapLatitude, state.mapLongitude, chosenPoint = state.point, interactive = false, centerZoom = MapZoom.street)
    }
    // Один рядок про місце: що зробити, що вже є, або — після «Опублікувати» — чого бракує, на тому ж місці.
    state.problem(DraftField.LOCATION)?.let { FieldError(it) } ?: Text(
        stringResource(if (state.pointChosen) R.string.address_point_set else R.string.address_or_map),
        style = MaterialTheme.typography.bodySmall,
        color = if (state.pointChosen) colors.success else colors.inkTertiary
    )
    // «Мої місця»: скільки людей поруч почують про зустріч. Менше трьох — мовчимо; прихована — нікому не кажемо.
    state.audience?.takeUnless { form.linkOnly }?.let { count ->
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
            Icon(PoruchIcons.bell, null, Modifier.size(16.dp), tint = colors.inkSecondary)
            Text(
                pluralStringResource(R.plurals.editor_audience, count, count),
                style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary
            )
        }
    }
    SecondaryButton(
        stringResource(if (state.pointChosen) R.string.change_point else R.string.choose_point),
        { onIntent(EditorIntent.ShowPointPicker(true)) }, Modifier.fillMaxWidth(), icon = PoruchIcons.pin
    )
    // Тут, а не в «Ще»: про приватність адреси думають, коли її вводять («Настолки вдома»).
    SwitchCard(R.string.link_only_label, R.string.link_only_hint, form.linkOnly) { value ->
        onIntent(EditorIntent.Edit { copy(linkOnly = value) })
    }
}

/** Перемикач на всю картку: TalkBack читає підпис разом зі станом, а ціль дотику — уся картка. */
@Composable
private fun SwitchCard(label: Int, hint: Int, checked: Boolean, onChange: (Boolean) -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().cardSurface().toggleable(checked, role = Role.Switch, onValueChange = onChange).padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(label), style = MaterialTheme.typography.titleSmall, color = colors.ink)
            Text(stringResource(hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        PoruchSwitch(checked, null)
    }
}

/** «Скільки людей»: число великими цифрами, як на корінці, і «−» / «+» для дрібних поправок. Понад 30 — підказка про кабінет. */
@Composable
private fun PeopleSection(state: EditorState, onIntent: (EditorIntent) -> Unit) = Section(R.string.quick_people) {
    val colors = Poruch.colors
    val form = state.form
    val seats = stringResource(R.string.capacity)
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
        ZoomButton(PoruchIcons.minus, R.string.quick_seats_less) { onIntent(EditorIntent.Seats(-1)) }
        androidx.compose.foundation.text.BasicTextField(
            form.capacity, { value -> onIntent(EditorIntent.Edit { copy(capacity = value.filter(Char::isDigit).take(5)) }) },
            Modifier.width(112.dp).background(colors.surface, Radius.sm).padding(vertical = Spacing.md).semantics { contentDescription = seats },
            textStyle = PoruchType.numeral.copy(color = colors.ink, textAlign = androidx.compose.ui.text.style.TextAlign.Center, fontFeatureSettings = "tnum"),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done), singleLine = true,
            cursorBrush = androidx.compose.ui.graphics.SolidColor(colors.ink)
        )
        ZoomButton(PoruchIcons.plus, R.string.quick_seats_more) { onIntent(EditorIntent.Seats(1)) }
    }
    state.problem(DraftField.CAPACITY)?.let { FieldError(it) }
    // Підказка, не заборона: великій події зручніше в кабінеті, але й тут її можна опублікувати.
    if (QuickEvent.isLarge(form.capacity.toIntOrNull() ?: 0)) CabinetLine(R.string.quick_large_hint) {
        onIntent(EditorIntent.OpenCabinet(LegalLinks.CABINET))
    }
}

/** Тихий рядок із посиланням на кабінет: підказка великої події й «Повні налаштування» у правці. */
@Composable
private fun CabinetLine(text: Int, onClick: () -> Unit) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().background(colors.surfaceMuted, Radius.md).clip(Radius.md)
            // Увесь рядок — посилання; куди воно веде, TalkBack каже назвою дії.
            .clickable(onClickLabel = stringResource(R.string.quick_open_cabinet), role = Role.Button, onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Text(stringResource(text), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = colors.ink)
        Icon(PoruchIcons.arrowRight, null, Modifier.size(18.dp), tint = colors.inkSecondary)
    }
}

/**
 * «Ще» — згорнуто: опис, фото, «За підтвердженням», чат і вхід, а під ними те, що за планом лишиться тільки сайту
 * (кілька фото й відео, вік, коли платять) — поки тут, щоб правка події з сайту нічого не губила.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MoreSection(state: EditorState, about: String, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val form = state.form
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        Row(
            Modifier.fillMaxWidth().cardSurface(Radius.md).toggleable(state.more, role = Role.Button) { onIntent(EditorIntent.ToggleMore) }
                .padding(Spacing.lg),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.quick_more), style = MaterialTheme.typography.titleSmall, color = colors.ink)
                Text(stringResource(R.string.quick_more_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
            }
            Icon(if (state.more) PoruchIcons.chevronUp else PoruchIcons.chevronDown, null, Modifier.size(20.dp), tint = colors.inkSecondary)
        }
        if (!state.more) return@Column
        val description = form.description.trim().length
        LabelledField(
            stringResource(R.string.description), form.description,
            { value -> onIntent(EditorIntent.Edit { copy(description = value.take(EventRules.descriptionLength.last)) }) },
            placeholder = stringResource(R.string.description_placeholder), singleLine = false,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            hint = EventRules.descriptionLength.let { rule ->
                when {
                    description == 0 -> stringResource(R.string.quick_about_hint, about)
                    description < rule.first -> stringResource(R.string.description_counter_min, description, rule.first)
                    else -> stringResource(R.string.description_counter, description, rule.last)
                }
            },
            error = state.problem(DraftField.DESCRIPTION)
        )
        MediaSection(state, onIntent)
        SwitchCard(R.string.approval_label, R.string.approval_hint, form.approvalRequired) { value ->
            onIntent(EditorIntent.Edit { copy(approvalRequired = value) })
        }
        // Чат — єдиний канал до учасників. Лише https: решту відкидає і чернетка, і сервер.
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            LabelledField(
                stringResource(R.string.contact_label), form.contactUrl,
                { value -> onIntent(EditorIntent.Edit { copy(contactUrl = value.take(ContactRules.MAX_URL_LENGTH)) }) },
                placeholder = stringResource(R.string.contact_placeholder),
                hint = stringResource(R.string.contact_editor_hint),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done)
            )
            if (form.contactUrl.isNotBlank() && !ContactRules.isContactUrl(form.contactUrl)) FieldError(DraftField.CONTACT_URL.rule())
        }
        EntryFields(state, onIntent)
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(
                stringResource(R.string.category_single).uppercase(), style = MaterialTheme.typography.labelSmall,
                color = colors.inkTertiary
            )
            // Ті самі плитки, що в шторці категорій пошуку: жанр обирають однаково скрізь.
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                categories.forEach { key ->
                    CategoryTile(key, form.category == key) { onIntent(EditorIntent.Edit { copy(category = key) }) }
                }
            }
            state.problem(DraftField.CATEGORY)?.let { FieldError(it) }
        }
        // Кінець ставить шаблон (тривалість) і їде за початком; тут — коли треба інакше.
        val days = remember { java.time.format.DateTimeFormatter.ofPattern("EEE, d MMM", java.util.Locale.forLanguageTag("uk")) }
        val hours = remember { java.time.format.DateTimeFormatter.ofPattern(HOUR_FORMAT) }
        DateTimeField(
            stringResource(R.string.ends), form.parse(form.ends)?.format(days)?.replaceFirstChar { it.uppercase() }.orEmpty(),
            form.parse(form.ends)?.format(hours).orEmpty(), state.problem(DraftField.ENDS_AT),
            onDate = { onIntent(EditorIntent.ShowPicker(PickerRequest.ENDS)) },
            onTime = { onIntent(EditorIntent.ShowPicker(PickerRequest.ENDS, time = true)) }
        )
        TimeZoneNote(form.timeZone, form.city, form.parse(form.starts))
        state.problem(DraftField.TIME_ZONE)?.let { FieldError(it) }
        AgeFields(state, onIntent)
        // Місто їде за адресою з підказки чи крапкою; поле — коли геокодер помилився.
        LabelledField(
            stringResource(R.string.city), form.city, { value -> onIntent(EditorIntent.Edit { copy(city = value) }) },
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done)
        )
    }
}

/** Правило поля, якщо людина вже натиснула «Опублікувати», а воно не пройшло. */
@Composable
private fun EditorState.problem(field: DraftField): String? =
    if (showProblems && field in problems) field.rule() else null

@Composable
private fun FieldError(text: String) =
    Text(text, style = MaterialTheme.typography.bodySmall, color = Poruch.colors.danger)

/** Кругла кнопка масштабу поверх мапи. */
@Composable
internal fun ZoomButton(icon: ImageVector, label: Int, onClick: () -> Unit) {
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
    // Від краю до краю, як коло в «Моїх місцях»: мапа йде під системні смуги, а не стоїть вікном у сірій рамці.
    Dialog(
        onDismissRequest = { onIntent(EditorIntent.ShowPointPicker(false)) },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
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

/** Вхід: спершу безкоштовно чи платно (власник 05.11). Платно — ціна й коли платять; безкоштовно прибирає обидва. */
@Composable
private fun EntryFields(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val colors = Poruch.colors
    val form = state.form
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(stringResource(R.string.entry_label).uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
        SegmentedPill(
            listOf(stringResource(R.string.entry_free), stringResource(R.string.entry_paid)), if (form.paid) 1 else 0,
            { index -> onIntent(EditorIntent.Edit { if (index == 1) copy(paid = true) else copy(paid = false, price = "", prepay = false) }) }
        )
    }
    // Онлайн застосунок не вмикає (лише кабінет на сайті), а коли платять — обирає.
    if (form.paid) LabelledField(
        stringResource(R.string.price_label), form.price, { value -> onIntent(EditorIntent.Edit { copy(price = value.filter(Char::isDigit).take(6)) }) },
        placeholder = stringResource(R.string.price_placeholder),
        hint = if (state.payOnline) stringResource(R.string.price_hint_online) else null,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next),
        // Платно без ціни — після спроби опублікувати; поза межами — одразу.
        error = DraftField.PRICE.rule().takeIf { form.price.isNotEmpty() && form.price.toInt() !in EventRules.price } ?: state.problem(DraftField.PRICE)
    )
    // Коли платять: людина бачить це під ціною й на панелі. Онлайн-подію змінюють у кабінеті.
    if (form.paid && !state.payOnline) Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(stringResource(R.string.pay_when_label).uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
        SegmentedPill(
            listOf(stringResource(R.string.pay_when_meeting), stringResource(R.string.pay_when_prepay)), if (form.prepay) 1 else 0,
            { index -> onIntent(EditorIntent.Edit { copy(prepay = index == 1) }) }
        )
        Text(
            stringResource(if (form.prepay) R.string.pay_when_prepay_hint else R.string.pay_when_meeting_hint),
            style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary
        )
    }
}

/** Вікові межі: за планом — лише сайт, поки лишаються під «Ще». */
@Composable
private fun AgeFields(state: EditorState, onIntent: (EditorIntent) -> Unit) {
    val form = state.form
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
            style = MaterialTheme.typography.bodySmall, color = Poruch.colors.inkTertiary
        )
        state.problem(DraftField.AGE_LIMITS)?.let { FieldError(it) }
    }
}

/**
 * Квиток «Від людей», що друкується з форми: незаповнене — сірі смуги, як на порожньому квитку, заповнене проступає
 * текстом. Корінець одразу кольору жанру (його ставить шаблон), на ньому година, день і місця. Смужкою: повний квиток
 * забирав чверть екрана, а тут чотири питання мають стояти поруч. Для TalkBack він повтор форми, тож прихований.
 * Те саме, що `DraftTicket` на iOS.
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
    val day = PoruchType.overline.copy(color = Color.White, letterSpacing = 0.6.sp)
    Ticket(
        categoryStub(form.category),
        stub = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(big, style = PoruchType.numeralSmall.copy(color = Color.White, fontFeatureSettings = "tnum"), maxLines = 1)
                if (start != null) Text(small, style = day, maxLines = 1)
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(PoruchIcons.social, null, Modifier.size(12.dp), tint = Color.White)
                    Text("${state.taken}/${form.capacity.ifBlank { "0" }}", style = day.copy(fontFeatureSettings = "tnum"))
                }
            }
        },
        modifier = Modifier.fillMaxWidth().decorative()
    ) {
        Column(
            Modifier.animateContentSize(Motion.quick<IntSize>(Poruch.reducedMotion)).padding(Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            if (title.isEmpty()) Blank(140.dp, 10.dp)
            else Text(TitleRules.display(title), style = PoruchType.brandTitle3, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            state.host?.let { host ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(host, null, 20.dp)
                    Text(stringResource(R.string.hosted_by, host), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 1)
                }
            }
            if (place.isEmpty()) Blank(100.dp, 6.dp) else MetaLine(PoruchIcons.pin, place)
        }
    }
}

/** Ще не надрукований рядок квитка. */
@Composable
private fun Blank(width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp) =
    Box(Modifier.padding(vertical = 3.dp).size(width, height).background(Poruch.colors.hairline, Radius.pill))

/** Звідки кнопки підвалу стають одна під одною: 1.3 — найбільший системний шрифт без «екстра». */
private const val LARGE_FONT_SCALE = 1.3f

/** Година на чипах форми — 24 години, як `HOUR` у Format.kt; пікер часу лишається за налаштуванням телефона. */
private const val HOUR_FORMAT = "HH:mm"

private val MeetupTemplate.label: Int
    get() = when (this) {
        MeetupTemplate.CINEMA -> R.string.template_cinema
        MeetupTemplate.BOARD_GAMES -> R.string.template_board_games
        MeetupTemplate.WALK -> R.string.template_walk
        MeetupTemplate.COFFEE -> R.string.template_coffee
        MeetupTemplate.WORKSHOP -> R.string.template_workshop
        MeetupTemplate.SPORT -> R.string.sport
    }

/** Типовий опис: шаблону чи, без нього, загальний. */
private val MeetupTemplate?.about: Int
    get() = when (this) {
        MeetupTemplate.CINEMA -> R.string.quick_about_cinema
        MeetupTemplate.BOARD_GAMES -> R.string.quick_about_board_games
        MeetupTemplate.WALK -> R.string.quick_about_walk
        MeetupTemplate.COFFEE -> R.string.quick_about_coffee
        MeetupTemplate.WORKSHOP -> R.string.quick_about_workshop
        MeetupTemplate.SPORT -> R.string.quick_about_sport
        null -> R.string.quick_about_default
    }

@Preview(widthDp = 360, heightDp = 1100)
@Composable
private fun QuickFormPreview() = PoruchTheme(dark = false) {
    EditorBody(EditorState(form = EditorForm(city = "Київ").scheduled(), host = "Оля"), "", {})
}

@Preview(widthDp = 360, heightDp = 2300)
@Composable
private fun QuickFormMorePreview() = PoruchTheme(dark = false) {
    EditorBody(
        EditorState(
            form = EditorForm(city = "Київ", address = "Кав'ярня «Фуга», Рейтарська, 9").scheduled()
                .with(MeetupTemplate.BOARD_GAMES, "Настолки").copy(capacity = "40"),
            host = "Оля", more = true, cabinet = LegalLinks.cabinetEvent("e1"), editing = true
        ), stringResource(R.string.quick_about_board_games), {}
    )
}

@Preview(widthDp = 360, heightDp = 1100)
@Composable
private fun QuickFormDarkPreview() = PoruchTheme(dark = true) {
    EditorBody(EditorState(form = EditorForm(city = "Київ").scheduled().with(MeetupTemplate.COFFEE, "Кава"), host = "Оля", showProblems = true), "", {})
}
