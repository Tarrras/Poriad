package app.poruch.android.feature.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.ContactRules
import app.poruch.domain.Event
import app.poruch.domain.asIndexEntry
import app.poruch.domain.Gathering
import app.poruch.domain.RatingRules
import app.poruch.domain.ReportReason
import coil3.compose.AsyncImage

@Composable
fun DetailScreen(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val event = state.event
    if (event == null) {
        Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
            PageHeader(stringResource(R.string.about_event), back = { onIntent(DetailIntent.Back) })
            if (state.loading) Box(Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.ink)
            } else EmptyState(PoruchIcons.search, stringResource(R.string.details), stringResource(R.string.event_unavailable))
        }
        return
    }
    Box(Modifier.fillMaxSize().background(colors.canvas)) {
        PullToRefresh(state.refreshing, { onIntent(DetailIntent.Refresh) }, Modifier.fillMaxSize(), underStatusBar = true) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 128.dp)) {
                Hero(event, state, onIntent)
                Column(
                    Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                ) {
                    Restrictions(state)
                    ExternalActions(state, onIntent)
                }
                // Поза колонкою з полями: смуга дат іде від краю до краю.
                if (state.sessions.size > 1) Sessions(state, onIntent, Modifier.padding(top = Spacing.lg))
                Column(
                    Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.lg),
                    verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                ) {
                    Facts(event)
                    if (state.attendees.isNotEmpty()) Roster(state, event)
                    Venue(event, onIntent)
                    Description(event, onIntent)
                    // Чат і посилання — для своїх: сервер віддає посилання лише організатору й підтвердженим.
                    if (state.hasChat || event.gathering?.hasContact == true) ContactSection(state, event, onIntent)
                    if (state.organizer && state.requests.isNotEmpty()) JoinRequests(state, onIntent)
                    if (state.canRate) RateEvent(state, onIntent)
                    if (state.organizer && state.ended && !state.cancelled) Ratings(state)
                    if (state.organizer && !state.cancelled) OrganizerActions(state, onIntent)
                    if (!state.organizer) SafetyActions(event, onIntent)
                }
            }
        }
        StickyAction(state, event, Modifier.align(Alignment.BottomCenter), onIntent)
    }
    if (state.confirmingBlock) PoruchConfirmSheet(
        title = stringResource(R.string.block_user_title),
        message = stringResource(R.string.block_user_body),
        confirmLabel = stringResource(R.string.block_confirm),
        dismissLabel = stringResource(R.string.close),
        onConfirm = { onIntent(DetailIntent.BlockOrganizer) },
        onDismiss = { onIntent(DetailIntent.ConfirmBlock(false)) },
        tone = colors.danger
    )
    if (state.confirmingContact) event.gathering?.contactUrl?.let { url ->
        PoruchConfirmSheet(
            title = stringResource(R.string.contact_confirm_title),
            message = stringResource(R.string.contact_confirm_body, ContactRules.host(url)),
            confirmLabel = stringResource(R.string.contact_confirm_open),
            dismissLabel = stringResource(R.string.close),
            onConfirm = { onIntent(DetailIntent.OpenContact) },
            onDismiss = { onIntent(DetailIntent.ConfirmContact(false)) }
        )
    }
    state.reporting?.let { target -> ReportSheet(target, onIntent) }
}

/**
 * Чат учасників. Кнопка веде не в браузер, а на попередження: посилання чуже, ми його не
 * перевіряли, і людина має це знати до того, як вийде із застосунку.
 */
@Composable
private fun ContactSection(state: DetailState, event: Event, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.contact_section))
        if (state.hasChat) {
            SecondaryButton(
                stringResource(R.string.chat_open), { onIntent(DetailIntent.OpenChat) },
                Modifier.fillMaxWidth(), icon = Icons.Outlined.ChatBubbleOutline
            )
            Text(stringResource(R.string.chat_open_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        }
        if (event.gathering?.hasContact == true) {
            SecondaryButton(
                stringResource(R.string.contact_open), { onIntent(DetailIntent.ConfirmContact(true)) },
                Modifier.fillMaxWidth(), icon = Icons.Outlined.Link
            )
            Text(stringResource(R.string.contact_members_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        }
    }
}

/** Скарга: іменована причина для сортування черги модерації плюс необов'язковий текст. */
@Composable
private fun ReportSheet(target: ReportTarget, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    var reason by remember { mutableStateOf(ReportReason.MINORS) }
    var details by remember { mutableStateOf("") }
    PoruchSheet({ onIntent(DetailIntent.ShowReport(null)) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(
                stringResource(if (target == ReportTarget.EVENT) R.string.report_event_title else R.string.report_user_title),
                style = MaterialTheme.typography.titleLarge, color = colors.ink
            )
            Text(stringResource(R.string.report_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                reportReasons.forEach { (value, label) ->
                    Row(
                        Modifier.fillMaxWidth().clip(Radius.sm)
                            .selectable(reason == value, role = Role.RadioButton) { reason = value }
                            .padding(vertical = Spacing.md, horizontal = Spacing.sm),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                    ) {
                        Box(
                            Modifier.size(20.dp).background(if (reason == value) colors.brand else colors.surfaceMuted, CircleShape),
                            contentAlignment = Alignment.Center
                        ) { if (reason == value) Icon(Icons.Outlined.Check, null, Modifier.size(12.dp), tint = colors.onBrand) }
                        Text(stringResource(label), style = MaterialTheme.typography.bodyLarge, color = colors.ink)
                    }
                }
            }
            LabelledField(
                stringResource(R.string.report_details), details, { details = it },
                singleLine = false, minLines = 3
            )
            PrimaryButton(
                stringResource(R.string.report_send),
                { sheet.close { onIntent(DetailIntent.SendReport(target, reason, details)) } },
                Modifier.fillMaxWidth()
            )
        }
    }
}

/**
 * Обкладинка на весь верх екрана, що згасає в полотно; назва й стан лежать на цьому згасанні,
 * як у картці дня Moonly: одна сцена, а не фото з підписом.
 */
@Composable
private fun Hero(event: Event, state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val room = state.room
    Box(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(400.dp).background(categoryGradient(event.category)), contentAlignment = Alignment.Center) {
            Icon(categoryIcon(event.category), null, Modifier.size(56.dp), tint = categoryInk(event.category))
            event.imageUrl?.let {
                AsyncImage(model = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            }
            // Обкладинка довільна, тож тонка тінь зверху тримає смугу статусу читабельною.
            Box(
                Modifier.fillMaxWidth().align(Alignment.TopCenter)
                    .windowInsetsTopHeight(WindowInsets.statusBars.add(WindowInsets(top = Spacing.lg)))
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.32f), Color.Transparent)))
            )
            Box(
                Modifier.fillMaxWidth().height(260.dp).align(Alignment.BottomCenter).background(
                    Brush.verticalGradient(0f to Color.Transparent, 0.55f to colors.canvas.copy(alpha = 0.85f), 1f to colors.canvas)
                )
            )
        }
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
            ScrimButton(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back)) { onIntent(DetailIntent.Back) }
            Spacer(Modifier.weight(1f))
            ScrimButton(
                if (state.saved) PoruchIcons.bookmarkFilled else PoruchIcons.bookmark,
                stringResource(if (state.saved) R.string.unsave else R.string.save)
            ) { onIntent(DetailIntent.ToggleSaved) }
        }
        Column(
            Modifier.align(Alignment.BottomStart).padding(horizontal = Spacing.page),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                StatusBadge(stringResource(categoryLabel(event.category)), BadgeTone.Brand)
                when {
                    state.cancelled -> StatusBadge(stringResource(R.string.cancelled), BadgeTone.Danger)
                    // Афіша завжди підписана джерелом: атрибуція обов'язкова.
                    state.listing?.isWithdrawn == true -> StatusBadge(stringResource(R.string.listing_withdrawn), BadgeTone.Neutral)
                    state.listing != null -> StatusBadge(stringResource(R.string.listing_badge, state.listing!!.sourceName), BadgeTone.Neutral)
                    state.organizer -> StatusBadge(stringResource(R.string.you_organize), BadgeTone.Neutral, PoruchIcons.sparkle)
                    // Після кінця лишається лише факт участі: черга й місця вже нічого не значать.
                    state.ended -> if (room?.joined == true) StatusBadge(stringResource(R.string.went), BadgeTone.Neutral, Icons.Outlined.Check)
                    room?.joined == true -> StatusBadge(stringResource(R.string.going), BadgeTone.Success, Icons.Outlined.Check)
                    state.waitlisted -> StatusBadge(stringResource(R.string.in_queue), BadgeTone.Accent, PoruchIcons.queue)
                    room?.awaitingApproval == true -> StatusBadge(stringResource(R.string.request_pending), BadgeTone.Accent, PoruchIcons.clock)
                    room?.isScarce == true && !state.cancelled ->
                        StatusBadge(stringResource(R.string.seats_left, room.seatsLeft), BadgeTone.Accent)
                }
            }
            Text(eventOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(event.title, style = MaterialTheme.typography.displaySmall, color = colors.ink)
        }
    }
}

/** Для кого подія, на картці, а не через відмову сервера. В афіші обмежень віку нема. */
@Composable
private fun Restrictions(state: DetailState) {
    val room = state.room ?: return
    if (!room.hasAgeLimit && !room.approvalRequired) return
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        if (room.hasAgeLimit) StatusBadge(ageLimitLabel(room), BadgeTone.Brand, PoruchIcons.person)
        if (room.approvalRequired) StatusBadge(stringResource(R.string.approval_badge), BadgeTone.Neutral, PoruchIcons.lock)
    }
}

/** Дати прокату. Лише коли сеансів більше одного. Скасований лишається на місці, позначеним. */
@Composable
private fun Sessions(state: DetailState, onIntent: (DetailIntent) -> Unit, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    val words = dateWords()
    val rail = rememberLazyListState()
    // Обраний сеанс має бути видно одразу, навіть якщо він шостий.
    LaunchedEffect(Unit) {
        val at = state.sessions.indexOfFirst { it.id == state.sessionId }
        if (at > 0) rail.scrollToItem(at)
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.sessions_title), Modifier.padding(horizontal = Spacing.page))
        LazyRow(
            state = rail, modifier = Modifier.selectableGroup(),
            contentPadding = PaddingValues(horizontal = Spacing.page),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            items(state.sessions, key = { it.id }) { session ->
                val selected = session.id == state.sessionId
                val (day, hour) = sessionLabel(session, words)
                val started = session.startInstant?.let { it <= kotlin.time.Clock.System.now() } == true
                val status = when {
                    session.cancelled -> stringResource(R.string.cancelled)
                    started -> stringResource(R.string.session_started)
                    else -> null
                }
                val onInk = colors.canvas
                Column(
                    Modifier.widthIn(min = 96.dp).clip(Radius.sm)
                        .background(if (selected) colors.ink else colors.surface)
                        .selectable(selected, role = Role.RadioButton) { onIntent(DetailIntent.PickSession(session.id)) }
                        .alpha(if (session.cancelled && !selected) 0.6f else 1f)
                        .padding(horizontal = Spacing.md, vertical = Spacing.sm),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        day, style = MaterialTheme.typography.labelMedium, maxLines = 1,
                        color = if (selected) onInk.copy(alpha = 0.8f) else colors.inkSecondary
                    )
                    Text(
                        hour, style = MaterialTheme.typography.titleSmall,
                        color = if (selected) onInk else colors.ink,
                        textDecoration = if (session.cancelled) TextDecoration.LineThrough else null
                    )
                    if (status != null) Text(
                        status, style = MaterialTheme.typography.labelSmall, maxLines = 1,
                        color = when {
                            session.cancelled -> colors.danger
                            selected -> onInk.copy(alpha = 0.8f)
                            else -> colors.inkTertiary
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun ageLimitLabel(room: Gathering): String = room.maxAge?.let {
    stringResource(R.string.age_badge_range, room.minAge, it)
} ?: stringResource(R.string.age_badge_from, room.minAge)

/** Запити на участь. На екрані деталей, бо організатор відповідає, дивлячись на свою подію. */
@Composable
private fun JoinRequests(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.requests_section))
        state.requests.forEach { person ->
            Row(
                Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                AvatarStack(listOf(person), total = 1, size = 36.dp)
                Text(person.name, style = MaterialTheme.typography.titleSmall, color = colors.ink, modifier = Modifier.weight(1f))
                GhostButton(stringResource(R.string.decline), { onIntent(DetailIntent.DeclineRequest(person.userId)) }, tone = colors.inkSecondary)
                PrimaryButton(stringResource(R.string.approve), { onIntent(DetailIntent.ApproveRequest(person.userId)) }, enabled = !state.mutating)
            }
        }
    }
}

/** Оцінка учасника: зірки й необов'язковий коментар. Повторна відправка замінює попередню. */
@Composable
private fun RateEvent(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val mine = state.myRating
    var score by remember(mine) { mutableStateOf(mine?.score ?: 0) }
    var comment by remember(mine) { mutableStateOf(mine?.comment.orEmpty()) }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.rate_title))
        Stars(score, onPick = { score = it })
        LabelledField(
            stringResource(R.string.rate_comment), comment, { comment = it.take(RatingRules.COMMENT_MAX) },
            singleLine = false, minLines = 3
        )
        Text(stringResource(R.string.rate_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        PrimaryButton(
            stringResource(if (mine == null) R.string.rate_send else R.string.rate_update),
            { onIntent(DetailIntent.Rate(score, comment)) }, Modifier.fillMaxWidth(),
            enabled = score > 0 && !state.mutating
        )
    }
}

/** Відгуки для організатора: середнє і коментарі, без імен. */
@Composable
private fun Ratings(state: DetailState) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.ratings_title))
        val average = RatingRules.average(state.ratings)
        if (average == null) {
            Text(stringResource(R.string.ratings_empty), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            return@Column
        }
        Text(
            stringResource(R.string.ratings_summary, average.toString().replace('.', ','), state.ratings.size),
            style = MaterialTheme.typography.titleMedium, color = colors.ink
        )
        state.ratings.filter { !it.comment.isNullOrBlank() }.forEach { rating ->
            Column(Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Stars(rating.score, size = 16.dp)
                Text(rating.comment.orEmpty(), style = MaterialTheme.typography.bodyMedium, color = colors.ink)
            }
        }
    }
}

/** П'ять зірок. З [onPick] — вибір, без нього — лише показ. */
@Composable
private fun Stars(score: Int, size: androidx.compose.ui.unit.Dp = 36.dp, onPick: ((Int) -> Unit)? = null) {
    val colors = Poruch.colors
    Row(horizontalArrangement = Arrangement.spacedBy(if (onPick == null) 2.dp else Spacing.xs)) {
        (1..5).forEach { value ->
            val label = stringResource(R.string.rate_star, value)
            Icon(
                if (value <= score) Icons.Filled.Star else Icons.Outlined.StarOutline,
                if (onPick == null) null else label,
                Modifier.then(
                    if (onPick == null) Modifier.size(size)
                    else Modifier.minimumInteractiveComponentSize().clip(CircleShape)
                        .selectable(value == score, role = Role.RadioButton) { onPick(value) }.padding(4.dp).size(size)
                ),
                tint = if (value <= score) colors.brand else colors.inkTertiary
            )
        }
    }
}

/** Скарга й блокування внизу сторінки, не в меню: важка скарга — неподана скарга. */
@Composable
private fun SafetyActions(event: Event, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    HairLine()
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        GhostButton(stringResource(R.string.report), { onIntent(DetailIntent.ShowReport(ReportTarget.EVENT)) }, tone = colors.inkSecondary)
        // Блокувати нема кого без людини; скарга на афішу лишається.
        if (event.organizerId != null) GhostButton(
            stringResource(R.string.block_user), { onIntent(DetailIntent.ConfirmBlock(true)) }, tone = colors.inkSecondary
        )
    }
}

/** Факти про подію в чотирьох рядках. Останні два різні для кімнати й афіші. */
/** Факти про подію сіткою два на два, як картка дня в Moonly: підпис над значенням, без гліфів. */
@Composable
private fun Facts(event: Event) {
    val cells = buildList {
        add(stringResource(R.string.when_label) to eventTime(event, dateWords()))
        add(stringResource(R.string.where) to listOf(event.city, event.address).filter { it.isNotBlank() }.joinToString(" · "))
        event.gathering?.let { room ->
            add(stringResource(R.string.organizer_short) to room.organizerName.ifBlank { stringResource(R.string.organizer_short) })
            add(stringResource(R.string.capacity_label) to stringResource(R.string.attendees_short, room.attendeeCount, room.capacity))
        }
        event.listing?.let { listing ->
            add(stringResource(R.string.listing_source_label) to listing.sourceName)
            add(stringResource(R.string.listing_price_label) to listingPrice(listing))
        }
    }
    Column(Modifier.fillMaxWidth().cardSurface().padding(Spacing.xl), verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        cells.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.lg)) {
                row.forEach { (label, value) -> FactCell(label, value, Modifier.weight(1f)) }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun FactCell(label: String, value: String, modifier: Modifier) {
    val colors = Poruch.colors
    Column(modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
        Text(value, style = MaterialTheme.typography.titleMedium, color = colors.ink)
    }
}

@Composable
private fun Roster(state: DetailState, event: Event) {
    val colors = Poruch.colors
    Row(
        Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        AvatarStack(state.attendees, total = event.gathering?.attendeeCount ?: state.attendees.size)
        Column {
            Text(stringResource(R.string.attendees_going).uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(
                state.attendees.joinToString(", ") { it.name }.take(ROSTER_PREVIEW),
                style = MaterialTheme.typography.bodyMedium, color = colors.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** Ряд круглих дій із підписами, як панель під картою дня в Moonly. */
@Composable
private fun ExternalActions(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        RoundAction(Icons.Outlined.EditCalendar, stringResource(R.string.calendar_short), { onIntent(DetailIntent.AddToCalendar) }, Modifier.weight(1f), enabled = !state.cancelled)
        RoundAction(Icons.Outlined.Directions, stringResource(R.string.open_in_maps), { onIntent(DetailIntent.OpenInMaps) }, Modifier.weight(1f))
        RoundAction(Icons.Outlined.Share, stringResource(R.string.share), { onIntent(DetailIntent.Share) }, Modifier.weight(1f))
        RoundAction(PoruchIcons.map, stringResource(R.string.on_map), { onIntent(DetailIntent.OpenMap) }, Modifier.weight(1f))
    }
}

/**
 * Місце події. Мініатюра без жестів, тап веде на велику мапу. Прозорий шар ловить дотик, бо
 * MapView з вимкненими жестами все одно поглинає його.
 */
@Composable
private fun Venue(event: Event, onIntent: (DetailIntent) -> Unit) {
    // Мапу вбудовуємо після другого кадру: MapView і стиль — найдорожче на екрані, і перехід чекав на них.
    var mapReady by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { withFrameNanos {}; withFrameNanos {}; mapReady = true }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(if (event.isCommunity) R.string.venue else R.string.venue_listing))
        Box(Modifier.fillMaxWidth().height(180.dp).cardSurface(Radius.md).padding(Spacing.xs).clip(Radius.sm)) {
            if (mapReady) EventMap(listOf(event.asIndexEntry()), event.latitude, event.longitude, selectedId = event.id, interactive = false)
            else Box(Modifier.fillMaxSize().background(Poruch.colors.surfaceMuted))
            Box(
                Modifier.matchParentSize().pressable { onIntent(DetailIntent.OpenMap) },
                contentAlignment = Alignment.BottomEnd
            ) {
                Box(Modifier.padding(Spacing.sm)) {
                    StatusBadge(stringResource(R.string.show_map), BadgeTone.Neutral, PoruchIcons.map)
                }
            }
        }
    }
}

/** Свій опис повністю, чужий — уривком ([Event.displayDescription]) і з посиланням на джерело. */
@Composable
private fun Description(event: Event, onIntent: (DetailIntent) -> Unit) {
    // Більшість афіш приходить без опису: заголовок над порожнечею гірший за відсутність секції.
    val text = event.displayDescription.trim()
    if (text.isEmpty() && event.listing?.hasSource != true) return
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        if (text.isNotEmpty()) {
            SectionHeader(stringResource(R.string.description_title))
            Text(text, style = PoruchType.lead, color = Poruch.colors.inkSecondary)
        }
        if (event.listing?.hasSource == true) GhostButton(
            stringResource(R.string.listing_read_more), { onIntent(DetailIntent.OpenSource) },
            tone = Poruch.colors.brand
        )
    }
}

@Composable
private fun OrganizerActions(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    HairLine()
    PhotoPickerButton(state.mutating) { bytes, mime -> onIntent(DetailIntent.AttachPhoto(bytes, mime)) }
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SecondaryButton(stringResource(R.string.edit), { onIntent(DetailIntent.Edit) }, Modifier.weight(1f), icon = Icons.Outlined.Edit)
        SecondaryButton(
            stringResource(R.string.cancel_event), { onIntent(DetailIntent.ConfirmCancel(true)) },
            Modifier.weight(1f), enabled = !state.mutating, tone = colors.danger
        )
    }
    if (state.confirmingCancel) PoruchConfirmSheet(
        title = stringResource(R.string.cancel_event),
        message = stringResource(R.string.cancel_explain),
        confirmLabel = stringResource(R.string.cancel_event),
        dismissLabel = stringResource(R.string.keep),
        onConfirm = { onIntent(DetailIntent.CancelEvent) },
        onDismiss = { onIntent(DetailIntent.ConfirmCancel(false)) },
        tone = colors.danger
    )
}

@Composable
private fun StickyAction(state: DetailState, event: Event, modifier: Modifier, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    Row(
        modifier.fillMaxWidth().background(colors.canvas).navigationBarsPadding().padding(Spacing.page),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                eventOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(
                stickyHint(state),
                style = MaterialTheme.typography.bodyMedium,
                color = if (state.cancelled) colors.danger else colors.inkSecondary,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
        }
        // Кнопки може не бути: у знятої афіші й афіші без посилання нема куди вести.
        if (state.action != DetailAction.NONE) PrimaryButton(
            stringResource(state.action.label),
            { onIntent(DetailIntent.PrimaryAction) },
            enabled = state.action.isEnabled && !state.mutating, loading = state.mutating,
            tone = when (state.action) {
                DetailAction.LEAVE -> colors.success
                DetailAction.LEAVE_WAITLIST -> colors.accent
                else -> null
            }
        )
    }
}

/** Рядок під датою в нижній панелі: місця й черга для кімнати, ціна або причина відсутності кнопки для афіші. */
@Composable
private fun stickyHint(state: DetailState): String {
    if (state.cancelled) return stringResource(R.string.cancelled)
    state.listing?.let { listing ->
        return when {
            listing.isWithdrawn -> stringResource(R.string.listing_withdrawn_hint)
            state.sessionStarted -> stringResource(R.string.session_started_hint)
            listing.hasSource -> listingPrice(listing)
            else -> stringResource(R.string.listing_hint_no_link)
        }
    }
    val room = state.room ?: return ""
    return when {
        state.ended -> stringResource(R.string.event_ended)
        room.awaitingApproval -> stringResource(R.string.request_pending_hint)
        // Гостю — що його чекає, не текст перемикача з редактора.
        room.approvalRequired && !room.joined && !state.organizer -> stringResource(R.string.approval_guest_hint)
        room.isFull && !room.joined && !state.organizer -> stringResource(R.string.waitlist_hint)
        else -> stringResource(R.string.seats, room.seatsLeft)
    }
}

private val DetailAction.label: Int
    get() = when (this) {
        DetailAction.JOIN -> R.string.join
        DetailAction.LEAVE -> R.string.leave
        DetailAction.JOIN_WAITLIST -> R.string.join_waitlist
        DetailAction.LEAVE_WAITLIST -> R.string.leave_waitlist
        DetailAction.REQUEST -> R.string.request_join
        DetailAction.REQUESTED -> R.string.request_pending
        DetailAction.ORGANIZER -> R.string.you_organize
        DetailAction.TICKETS -> R.string.listing_tickets
        DetailAction.CANCELLED, DetailAction.NONE -> R.string.cancelled
    }

@Composable
private fun ScrimButton(icon: ImageVector, description: String, onClick: () -> Unit) {
    // Фото довільне, тож кнопки на власному світлому скримі.
    Box(
        Modifier.size(40.dp).background(Color.White.copy(alpha = 0.92f), CircleShape)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), CircleShape).clip(CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(icon, description, Modifier.size(18.dp), tint = Color(0xFF14130F)) }
}

private const val ROSTER_PREVIEW = 80
