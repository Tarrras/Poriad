package app.poruch.android.feature.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.ScrollState
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.android.feature.mine.countdownOverline
import app.poruch.domain.ArtistRole
import app.poruch.domain.ContactRules
import app.poruch.domain.Event
import app.poruch.domain.EventIndexEntry
import app.poruch.domain.TitleRules
import app.poruch.domain.FollowRules
import app.poruch.domain.CompanionRules
import app.poruch.domain.Membership
import app.poruch.domain.EventSession
import app.poruch.domain.asIndexEntry
import app.poruch.domain.Gathering
import app.poruch.domain.EventRating
import app.poruch.domain.RatingRules
import app.poruch.domain.RatingTag
import app.poruch.domain.ReportReason
import app.poruch.domain.ShelterKind

@Composable
fun DetailScreen(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val event = state.event
    if (event == null) {
        Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
            PageHeader(stringResource(R.string.about_event), back = { onIntent(DetailIntent.Back) })
            if (state.loading) Box(Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center) {
                PoruchLoader()
            } else EmptyState(PoruchIcons.search, stringResource(R.string.details), stringResource(R.string.event_unavailable))
        }
        return
    }
    val scroll = rememberScrollState()
    Box(Modifier.fillMaxSize().background(colors.canvas)) {
        PullToRefresh(state.refreshing, { onIntent(DetailIntent.Refresh) }, Modifier.fillMaxSize(), underStatusBar = true) {
            // Під нижньою панеллю дії: її висота плюс системна смуга, якою б вона не була.
            // Дві кнопки в панелі («Шукаю компанію» і квиток) стоять другим рядом — панель вища.
            val bottom = if (state.canSeekCompany) 168.dp else 104.dp
            Column(Modifier.fillMaxSize().verticalScroll(scroll).navigationBarsPadding().padding(bottom = bottom)) {
                Hero(event, state, scroll, onIntent)
                // Аркуш із заокругленим верхом наїжджає на обкладинку: сторінка лягає на афішу, а не продовжує її.
                Column(
                    Modifier.offset(y = -HERO_OVERLAP).fillMaxWidth().background(colors.canvas, Radius.sheet)
                ) {
                    Column(
                        Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.xl),
                        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                    ) {
                        Restrictions(state)
                        state.companionOf?.let { parent ->
                            GroupedRows {
                                LinkRow(Icons.Outlined.Groups, stringResource(R.string.companion_parent, TitleRules.display(parent.title)), onClick = { onIntent(DetailIntent.OpenEvent(parent.id)) })
                            }
                        }
                        ExternalActions(state, onIntent)
                    }
                    // Поза колонкою з полями: смуга дат іде від краю до краю.
                    if (state.sessions.size > 1) Sessions(state, onIntent, Modifier.padding(top = Spacing.lg))
                    Column(
                        Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.lg),
                        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                    ) {
                        if (event.artists.isNotEmpty()) Lineup(event, onIntent)
                        Facts(event)
                        if (state.companions.isNotEmpty() && !state.cancelled) Companions(state, onIntent)
                        event.gathering?.let { People(state, it, onIntent) }
                        Venue(event, state.followingPlace, onIntent)
                        if (!state.cancelled && !state.ended) Safety(state, onIntent)
                        Description(event, onIntent)
                        if (state.othersHere.isNotEmpty()) OthersHere(state.othersHere, event.placeName, onIntent)
                        // Чат і посилання — для своїх: сервер віддає посилання лише організатору й підтвердженим.
                        if (state.hasChat || event.gathering?.hasContact == true) ContactSection(state, event, onIntent)
                        if (state.organizer && state.requests.isNotEmpty()) JoinRequests(state, onIntent)
                        if (state.canRate) RateEvent(state, onIntent)
                        if (state.organizer && state.ended && !state.cancelled) Ratings(state)
                        // Після кінця редагувати й скасовувати нічого: лишаються відгуки.
                        if (state.organizer && !state.cancelled && !state.ended) OrganizerActions(state, onIntent)
                        if (!state.organizer) SafetyActions(event, onIntent)
                    }
                }
            }
        }
        // Коли аркуш доїхав до годинника, текст інакше йде під нього: смуга статусу набирає колір полотна.
        // Не раніше: світла смуга над темною обкладинкою відрізала б її.
        val density = LocalDensity.current
        val statusTop = WindowInsets.statusBars.getTop(density)
        Box(
            Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars)
                .graphicsLayer {
                    val from = (HERO_HEIGHT - HERO_OVERLAP - SCRIM_FADE).toPx() - statusTop
                    alpha = ((scroll.value - from) / SCRIM_FADE.toPx()).coerceIn(0f, 1f)
                }
                .background(colors.canvas)
        )
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
    if (state.seekingCompany) CompanionSheet(event, state.mutating, onIntent)
    state.person?.let { person ->
        val request = state.organizer && state.requests.any { it.userId == person.userId }
        PersonSheet(
            person, isMe = person.userId == state.userId,
            onDismiss = { onIntent(DetailIntent.ClosePerson) },
            onBlock = { onIntent(DetailIntent.BlockPerson(person.userId)) },
            onReport = { onIntent(DetailIntent.ReportPerson(person.userId)) },
            follow = FollowAction(person.userId in state.followedOrganizers) {
                onIntent(DetailIntent.ToggleFollowPerson(person.userId, person.profile?.name.orEmpty()))
            }
        ) { sheet ->
            if (request) {
                Text(stringResource(R.string.person_request), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    SecondaryButton(
                        stringResource(R.string.decline), { sheet.close { onIntent(DetailIntent.DeclineRequest(person.userId)) } },
                        Modifier.weight(1f), enabled = !state.mutating
                    )
                    PrimaryButton(
                        stringResource(R.string.approve), { sheet.close { onIntent(DetailIntent.ApproveRequest(person.userId)) } },
                        Modifier.weight(1f), enabled = !state.mutating
                    )
                }
            }
        }
    }
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
                stringResource(
                    when (target) {
                        ReportTarget.EVENT -> R.string.report_event_title
                        ReportTarget.ORGANIZER -> R.string.report_user_title
                        ReportTarget.PERSON -> R.string.report_person_title
                    }
                ),
                style = PoruchType.serifTitle2, color = colors.ink
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
 * Обкладинка на весь верх екрана — та сама афіша, що й велика картка головної ([EventArt]): без фото
 * насичений градієнт категорії, а не бліда пастель. Назва й стан лежать на затемненні внизу: одна сцена,
 * а не фото з підписом. Низ на [HERO_OVERLAP] ховається під аркушем секцій.
 */
@Composable
private fun Hero(event: Event, state: DetailState, scroll: ScrollState, onIntent: (DetailIntent) -> Unit) {
    val room = state.room
    // Відлік лише для сьогоднішнього, як на картці плану головної.
    val today = runCatching {
        java.time.Instant.parse(event.startsAt).atZone(java.time.ZoneId.systemDefault()).toLocalDate() == java.time.LocalDate.now()
    }.getOrDefault(false)
    val overline = if (today) countdownOverline(event) else cardOverline(event, dateWords())
    Box(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(HERO_HEIGHT)) {
            EventArt(event, Modifier.fillMaxSize(), glyph = 260.dp, glyphDrop = 120.dp)
            // Обкладинка довільна, тож тонка тінь зверху тримає смугу статусу читабельною.
            Box(
                Modifier.fillMaxWidth().align(Alignment.TopCenter)
                    .windowInsetsTopHeight(WindowInsets.statusBars.add(WindowInsets(top = Spacing.lg)))
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.32f), Color.Transparent)))
            )
            Box(
                Modifier.matchParentSize().background(
                    Brush.verticalGradient(0.35f to Color.Transparent, 0.75f to Color.Black.copy(alpha = 0.55f), 1f to Color.Black.copy(alpha = 0.82f))
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
            Modifier.align(Alignment.BottomStart).padding(horizontal = Spacing.page).padding(bottom = HERO_OVERLAP + Spacing.xl)
                // Текст їде зі стрічкою, а смуга статусу з'являється лише з аркушем: назва гасне, поки не дійшла до годинника.
                .graphicsLayer {
                    // Читання в шарі, а не в композиції: прокрутка не перескладає обкладинку.
                    val faded = 1f - (scroll.value - HERO_TEXT_FADE_FROM.toPx()) / HERO_TEXT_FADE.toPx()
                    alpha = faded.coerceIn(0f, 1f) * if (state.cancelled) 0.7f else 1f
                },
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
            Text(overline, style = MaterialTheme.typography.labelSmall, color = Poruch.colors.accentOnPhoto, maxLines = 2)
            Text(event.displayTitle, style = PoruchType.serifDisplay, color = Color.White)
        }
    }
}

/** Хто виступає: імена тапаються й ведуть на екран артиста; ведучий підписаний. Повний склад, без «та ще N» картки. */
@Composable
private fun Lineup(event: Event, onIntent: (DetailIntent) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.lineup_title))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            event.artists.forEach { artist ->
                val host = artist.role == ArtistRole.HOST
                PoruchChip(
                    if (host) stringResource(R.string.artist_line_host, artist.name).replaceFirstChar { it.uppercase() } else artist.name,
                    selected = false, onClick = { onIntent(DetailIntent.OpenArtist(artist)) }
                )
            }
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
                // Імʼя й фото — вхід у картку: вирішувати, дивлячись на людину, а не на імʼя.
                Row(
                    Modifier.weight(1f).clip(Radius.sm).clickable { onIntent(DetailIntent.OpenPerson(person.userId)) },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                ) {
                    Avatar(person.name, person.avatarUrl, 36.dp)
                    Text(person.name, style = MaterialTheme.typography.titleSmall, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                GhostButton(stringResource(R.string.decline), { onIntent(DetailIntent.DeclineRequest(person.userId)) }, tone = colors.inkSecondary)
                PrimaryButton(stringResource(R.string.approve), { onIntent(DetailIntent.ApproveRequest(person.userId)) }, enabled = !state.mutating)
            }
        }
    }
}

/** Кнопка замість форми: сама оцінка — у [RatingSheet], як у «Моїх подіях». */
@Composable
private fun RateEvent(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val event = state.event ?: return
    var open by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.rate_title))
        val mine = state.myRating
        if (mine == null) PrimaryButton(stringResource(R.string.rate_action), { open = true }, Modifier.fillMaxWidth())
        else SecondaryButton(
            stringResource(R.string.my_score, mine.score) + " · " + stringResource(R.string.rate_change),
            { open = true }, Modifier.fillMaxWidth()
        )
    }
    // Оцінюють учасники: організатор свою подію не оцінює, тож перемикач лише для тих, у кого є організатор.
    val follow = event.organizerId?.takeIf { !state.organizer }
        ?.let { FollowRules.followOnRating(it in state.followedOrganizers, state.myRating != null) }
    if (open) RatingSheet(event, state.myRating, state.mutating, follow, { open = false }) { score, comment, tags, following ->
        onIntent(DetailIntent.Rate(score, comment, tags, following))
    }
}

/**
 * «Як пройшло?»: бал 1–5, що сподобалось, кілька слів організатору. Повторна відправка замінює
 * попередню. Спільна для деталей і «Моїх подій».
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun RatingSheet(
    event: Event, mine: EventRating?, mutating: Boolean,
    /** Початковий стан перемикача «Стежити за організатором»; null — перемикача нема. */
    followOrganizer: Boolean?,
    onDismiss: () -> Unit,
    onSend: (score: Int, comment: String, tags: List<RatingTag>, follow: Boolean?) -> Unit
) {
    val colors = Poruch.colors
    var score by remember(mine) { mutableStateOf(mine?.score ?: 0) }
    var tags by remember(mine) { mutableStateOf(mine?.tags.orEmpty().toSet()) }
    var comment by remember(mine) { mutableStateOf(mine?.comment.orEmpty()) }
    var follow by remember(mine, followOrganizer) { mutableStateOf(followOrganizer ?: false) }
    val offered = remember(event.category) { RatingRules.tagsFor(event.category) }
    PoruchSheet(onDismiss) { sheet ->
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.page).padding(bottom = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                EventImage(event, Modifier.size(52.dp).clip(Radius.xs))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(cardOverline(event, dateWords()), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
                    Text(event.displayTitle, style = PoruchType.serifTitle3, color = colors.ink, maxLines = 2)
                }
            }
            Text(stringResource(R.string.rate_title), style = PoruchType.serifTitle2, color = colors.ink)
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Row(Modifier.selectableGroup(), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    (1..5).forEach { value ->
                        val picked = value == score
                        val label = stringResource(R.string.rate_star, value)
                        Box(
                            Modifier.weight(1f).height(56.dp)
                                .background(if (picked) brandGradient() else SolidColor(LocalFieldSurface.current ?: colors.surface), Radius.sm)
                                .clip(Radius.sm)
                                .selectable(picked, role = Role.RadioButton) { score = value }
                                .semantics { contentDescription = label },
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                value.toString(), style = MaterialTheme.typography.titleMedium,
                                color = if (picked) colors.onBrand else colors.ink
                            )
                        }
                    }
                }
                Row {
                    Text(stringResource(R.string.rate_low), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
                    Text(stringResource(R.string.rate_high), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(stringResource(R.string.rate_liked).uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    offered.forEach { tag ->
                        PoruchChip(stringResource(tag.label), tag in tags, { tags = if (tag in tags) tags - tag else tags + tag })
                    }
                }
            }
            LabelledField(
                stringResource(R.string.rate_comment), comment, { comment = it.take(RatingRules.COMMENT_MAX) },
                placeholder = stringResource(R.string.rate_optional), singleLine = false, minLines = 3
            )
            if (followOrganizer != null) Row(
                Modifier.fillMaxWidth().cardSurface(Radius.md).padding(horizontal = Spacing.lg, vertical = Spacing.md),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(stringResource(R.string.rate_follow_title), style = MaterialTheme.typography.titleSmall, color = colors.ink)
                    Text(stringResource(R.string.rate_follow_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                }
                PoruchSwitch(follow, { follow = it })
            }
        }
        HairLine()
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.lg, bottom = Spacing.md).navigationBarsPadding().imePadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.xs)
        ) {
            PrimaryButton(
                stringResource(if (mine == null) R.string.rate_send else R.string.rate_update),
                // Порядок шторки, не порядок тапів: так і на сервері, і в тестах.
                { sheet.close { onSend(score, comment, offered.filter { it in tags }, follow.takeIf { followOrganizer != null }) } },
                Modifier.fillMaxWidth(), enabled = score > 0 && !mutating, loading = mutating
            )
            GhostButton(stringResource(R.string.rate_skip), { sheet.close() }, tone = colors.inkSecondary)
        }
    }
}

internal val RatingTag.label: Int
    get() = when (this) {
        RatingTag.ATMOSPHERE -> R.string.rate_tag_atmosphere
        RatingTag.ORGANIZATION -> R.string.rate_tag_organization
        RatingTag.PLACE -> R.string.rate_tag_place
        RatingTag.PEOPLE -> R.string.rate_tag_people
        RatingTag.ON_TIME -> R.string.rate_tag_on_time
        RatingTag.MUSIC -> R.string.rate_tag_music
        RatingTag.SOUND -> R.string.rate_tag_sound
        RatingTag.HUMOR -> R.string.rate_tag_humor
        RatingTag.HOST -> R.string.rate_tag_host
        RatingTag.PROGRAM -> R.string.rate_tag_program
        RatingTag.COACH -> R.string.rate_tag_coach
        RatingTag.WORKOUT -> R.string.rate_tag_workout
        RatingTag.ROUTE -> R.string.rate_tag_route
        RatingTag.VIEWS -> R.string.rate_tag_views
        RatingTag.PACE -> R.string.rate_tag_pace
        RatingTag.GUIDE -> R.string.rate_tag_guide
        RatingTag.STORIES -> R.string.rate_tag_stories
        RatingTag.FOOD -> R.string.rate_tag_food
        RatingTag.DRINKS -> R.string.rate_tag_drinks
        RatingTag.GAME_CHOICE -> R.string.rate_tag_game_choice
        RatingTag.RULES -> R.string.rate_tag_rules
        RatingTag.CONVERSATION -> R.string.rate_tag_conversation
        RatingTag.KIDS_LIKED -> R.string.rate_tag_kids_liked
        RatingTag.SAFETY -> R.string.rate_tag_safety
        RatingTag.SPEAKERS -> R.string.rate_tag_speakers
        RatingTag.USEFUL -> R.string.rate_tag_useful
        RatingTag.NETWORKING -> R.string.rate_tag_networking
    }

/** Відгуки для організатора: середнє, що сподобалось, коментарі — без імен. */
@OptIn(ExperimentalLayoutApi::class)
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
        val tags = RatingRules.tagCounts(state.ratings)
        if (tags.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            tags.forEach { StatusBadge("${stringResource(it.tag.label)} · ${it.count}") }
        }
        state.ratings.filter { !it.comment.isNullOrBlank() }.forEach { rating ->
            Column(Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Stars(rating.score, size = 16.dp)
                Text(rating.comment.orEmpty(), style = MaterialTheme.typography.bodyMedium, color = colors.ink)
            }
        }
    }
}

/** П'ять зірок у відгуку організатора. */
@Composable
private fun Stars(score: Int, size: androidx.compose.ui.unit.Dp) {
    val colors = Poruch.colors
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        (1..5).forEach { value ->
            Icon(
                if (value <= score) Icons.Filled.Star else Icons.Outlined.StarOutline, null, Modifier.size(size),
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

/**
 * Люди події: організатор і ті, хто йде. Рядок відкриває картку людини — так організатор і учасники
 * бачать одне одного. Ростер віддає лише організатору й учасникам, решта бачить тільки організатора.
 */
@Composable
private fun People(state: DetailState, room: Gathering, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    var expanded by remember { mutableStateOf(false) }
    val shown = if (expanded) state.attendees else state.attendees.take(ROSTER_COLLAPSED)
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.attendees_going))
        GroupedRows {
            PersonRow(
                room.organizerName.ifBlank { stringResource(R.string.organizer_short) },
                state.organizerAvatar,
                stringResource(R.string.organizer_short)
            ) { onIntent(DetailIntent.OpenPerson(room.organizerId)) }
            shown.forEach { person ->
                HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                PersonRow(person.name.ifBlank { stringResource(R.string.chat_member) }, person.avatarUrl) {
                    onIntent(DetailIntent.OpenPerson(person.userId))
                }
            }
            if (!expanded && state.attendees.size > ROSTER_COLLAPSED) {
                HairLine(Modifier.padding(start = Spacing.lg))
                Text(
                    stringResource(R.string.attendees_show_all) + " · " + state.attendees.size,
                    style = MaterialTheme.typography.labelLarge, color = colors.ink,
                    modifier = Modifier.fillMaxWidth().clickable { expanded = true }.padding(Spacing.lg)
                )
            }
        }
        // Гість і сторонній бачать лише число: імена — межа RLS.
        if (state.attendees.isEmpty() && room.attendeeCount > 0) Text(
            stringResource(R.string.attendees_short, room.attendeeCount, room.capacity),
            style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
        )
    }
}

/** Рядок людини: фото, імʼя, необовʼязковий підпис; весь рядок — кнопка на картку. */
@Composable
private fun PersonRow(name: String, avatarUrl: String?, caption: String? = null, onClick: () -> Unit) {
    val colors = Poruch.colors
    val description = stringResource(R.string.person_open, name)
    Row(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = description }
            .clickable(onClick = onClick).padding(horizontal = Spacing.lg, vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Avatar(name, avatarUrl, 40.dp)
        Column(Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.titleSmall, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            caption?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary) }
        }
        Icon(Icons.Outlined.ChevronRight, null, Modifier.size(20.dp), tint = colors.inkTertiary)
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
private fun Venue(event: Event, following: Boolean, onIntent: (DetailIntent) -> Unit) {
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
        // Заклад знає лише афіша: у спільнотної події місця нема, тож і стежити нема за чим.
        if (FollowRules.canFollowPlace(event)) Row(
            Modifier.fillMaxWidth().cardSurface(Radius.md).padding(horizontal = Spacing.lg, vertical = Spacing.md),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(event.placeLabel, style = MaterialTheme.typography.titleSmall, color = Poruch.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(stringResource(R.string.follow_place_hint), style = MaterialTheme.typography.bodySmall, color = Poruch.colors.inkSecondary)
            }
            FollowPill(following, { onIntent(DetailIntent.ToggleFollowPlace) }, onCard = true)
        }
    }
}

/**
 * Безпека: чи встигнеш до комендантської і куди йти під час тривоги. Правила Мінкульту з 11.09.2026
 * вимагають заздалегідь казати учасникам про найближче укриття. Нема даних міста — нема секції.
 */
@Composable
private fun Safety(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val shelters = state.safety?.shelters.orEmpty()
    val curfew = state.curfew
    if (shelters.isEmpty() && curfew == null) return
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.safety_title))
        Column(Modifier.cardSurface(Radius.md)) {
            if (curfew != null) Row(
                Modifier.fillMaxWidth().padding(horizontal = Spacing.lg, vertical = Spacing.md),
                horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
            ) {
                // Година й менше до комендантської — уже привід планувати дорогу, тож колір попередження.
                val tight = curfew.minutesLeft <= 60
                Icon(Icons.Outlined.NightsStay, null, Modifier.size(20.dp), tint = if (tight) colors.danger else colors.inkTertiary)
                Text(
                    if (curfew.minutesLeft == 0) stringResource(R.string.curfew_during, curfew.endsAt, curfew.curfew.starts)
                    else stringResource(R.string.curfew_left, curfew.endsAt, curfew.curfew.starts, durationWords(curfew.minutesLeft)),
                    style = MaterialTheme.typography.bodyMedium, color = if (tight) colors.danger else colors.inkSecondary
                )
            }
            shelters.forEachIndexed { index, shelter ->
                if (index > 0 || curfew != null) HairLine()
                Row(
                    Modifier.fillMaxWidth().pressable { onIntent(DetailIntent.OpenShelter(shelter)) }
                        .padding(horizontal = Spacing.lg, vertical = Spacing.md),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        if (shelter.kind == ShelterKind.METRO) Icons.Outlined.Subway else Icons.Outlined.Shield,
                        null, Modifier.size(20.dp), tint = colors.inkTertiary
                    )
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        Text(
                            stringResource(R.string.shelter_kind_distance, stringResource(shelter.kind.label()), shelter.distanceMeters),
                            style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary
                        )
                        Text(shelter.address, style = MaterialTheme.typography.titleSmall, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        val extras = listOfNotNull(
                            shelter.hours,
                            stringResource(R.string.shelter_accessible).takeIf { shelter.accessible }
                        )
                        if (extras.isNotEmpty()) Text(extras.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                    }
                    Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
                }
            }
        }
        // Ліцензія CC BY вимагає вказати джерело.
        if (shelters.isNotEmpty()) Text(stringResource(R.string.shelters_source), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
    }
}

private fun ShelterKind.label() = when (this) {
    ShelterKind.METRO -> R.string.shelter_metro
    ShelterKind.UNDERPASS -> R.string.shelter_underpass
    ShelterKind.PARKING -> R.string.shelter_parking
    ShelterKind.BASEMENT -> R.string.shelter_basement
}

@Composable
private fun durationWords(minutes: Int): String {
    val hours = minutes / 60
    val rest = minutes % 60
    return when {
        hours == 0 -> stringResource(R.string.duration_minutes, rest)
        rest == 0 -> stringResource(R.string.duration_hours, hours)
        else -> stringResource(R.string.duration_hours_minutes, hours, rest)
    }
}

/** Інші події на цій точці. Заголовок — місце (назва закладу, коли є), тому рядку досить дати й назви. */
@Composable
private fun OthersHere(others: List<EventIndexEntry>, placeName: String?, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val words = dateWords()
    // Згорнуто після опису: у великого закладу десятки подій, і розгорнутий список відсував би решту сторінки.
    var expanded by rememberSaveable { mutableStateOf(false) }
    val state = stringResource(if (expanded) R.string.expanded else R.string.collapsed)
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(role = Role.Button) { expanded = !expanded }
                .semantics(mergeDescendants = true) { stateDescription = state },
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                if (placeName != null) stringResource(R.string.others_here_at, placeName) else stringResource(R.string.others_here),
                style = PoruchType.serifTitle2, color = colors.ink, modifier = Modifier.weight(1f)
            )
            Text("${others.size}", style = MaterialTheme.typography.labelLarge, color = colors.inkSecondary)
            Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp).rotate(if (expanded) 270f else 90f), tint = colors.inkTertiary)
        }
        if (expanded) Column(Modifier.cardSurface(Radius.md)) {
            others.forEach { other ->
                val (day, hour) = sessionLabel(EventSession(other.id, other.startsAt, other.timeZone), words)
                Row(
                    Modifier.fillMaxWidth().pressable { onIntent(DetailIntent.OpenEvent(other.id)) }
                        .padding(horizontal = Spacing.lg, vertical = Spacing.md),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        Text("$day · $hour", style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
                        Text(
                            TitleRules.display(other.title), style = PoruchType.serifTitle3, color = colors.ink,
                            maxLines = 2, overflow = TextOverflow.Ellipsis
                        )
                    }
                    Icon(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
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
    // Час, місце й місткість супутника тримає сервер: лишається скасувати.
    val companion = state.companionOf != null
    if (!companion) PhotoPickerButton(state.mutating) { bytes, mime -> onIntent(DetailIntent.AttachPhoto(bytes, mime)) }
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        if (!companion) SecondaryButton(stringResource(R.string.edit), { onIntent(DetailIntent.Edit) }, Modifier.weight(1f), icon = Icons.Outlined.Edit)
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
    // Плаває над сторінкою, як таббар головної: дія під пальцем, а не смуга на всю ширину.
    Column(
        modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = Spacing.md, vertical = Spacing.sm)
            .cardSurface(Radius.xl, Elevation.overlay).padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
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
            if (state.action != DetailAction.NONE) PrimaryAction(state, onIntent)
        }
        // «Шукаю компанію» під квитком на всю ширину: поруч із ціною й квитком не влазить.
        if (state.canSeekCompany) SecondaryButton(
            stringResource(R.string.companion_seek), { onIntent(DetailIntent.SeekCompany(true)) },
            Modifier.fillMaxWidth(), enabled = !state.mutating, icon = Icons.Outlined.Groups
        )
    }
}

@Composable
private fun PrimaryAction(state: DetailState, onIntent: (DetailIntent) -> Unit, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    PrimaryButton(
        stringResource(state.action.label),
        { onIntent(DetailIntent.PrimaryAction) },
        modifier,
        enabled = state.action.isEnabled && !state.mutating, loading = state.mutating,
        tone = when (state.action) {
            DetailAction.LEAVE -> colors.success
            DetailAction.LEAVE_WAITLIST -> colors.accent
            else -> null
        }
    )
}

/**
 * Хто вже шукає компанію на цю афішу. Без імен: організатора видно на сторінці супутника, туди
 * й веде рядок. «Долучитися» — запит організатору прямо звідси.
 */
@Composable
private fun Companions(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val words = dateWords()
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.companions_title))
        Column(Modifier.cardSurface(Radius.md)) {
            state.companions.forEachIndexed { index, card ->
                if (index > 0) HairLine()
                val (day, hour) = sessionLabel(EventSession(card.id, card.meetAt, card.timeZone), words)
                Row(
                    Modifier.fillMaxWidth().pressable { onIntent(DetailIntent.OpenEvent(card.id)) }
                        .padding(horizontal = Spacing.lg, vertical = Spacing.md),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                        Text("$day · $hour", style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
                        Text(
                            card.meetNote ?: stringResource(R.string.venue), style = MaterialTheme.typography.titleSmall,
                            color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            stringResource(R.string.attendees_short, card.attendeeCount, card.capacity),
                            style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary
                        )
                    }
                    when {
                        card.mine -> StatusBadge(stringResource(R.string.companion_mine), BadgeTone.Brand)
                        card.membership == Membership.APPROVED -> StatusBadge(stringResource(R.string.going), BadgeTone.Success, Icons.Outlined.Check)
                        card.membership == Membership.REQUESTED -> StatusBadge(stringResource(R.string.request_pending), BadgeTone.Accent, PoruchIcons.clock)
                        card.isFull -> StatusBadge(stringResource(R.string.companion_full))
                        else -> SecondaryButton(
                            stringResource(R.string.companion_join), { onIntent(DetailIntent.JoinCompanion(card.id)) },
                            enabled = !state.mutating
                        )
                    }
                }
            }
        }
    }
}

/**
 * Коротка шторка замість повного редактора: лише час зустрічі, де зустрітись і скільки людей.
 * Назву, місце й кінець сервер бере з афіші.
 */
@Composable
private fun CompanionSheet(event: Event, mutating: Boolean, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val times = remember(event.startsAt) { CompanionRules.meetTimes(event.startsAt, kotlin.time.Clock.System.now()) }
    var at by remember(times) {
        mutableStateOf(times.indexOf(CompanionRules.defaultMeetAt(event.startsAt, kotlin.time.Clock.System.now())).coerceAtLeast(0))
    }
    var note by remember { mutableStateOf("") }
    var capacity by remember { mutableStateOf(CompanionRules.DEFAULT_CAPACITY) }
    val words = dateWords()
    PoruchSheet({ onIntent(DetailIntent.SeekCompany(false)) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section).imePadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Text(stringResource(R.string.companion_seek), style = PoruchType.serifTitle2, color = colors.ink)
            Text(event.displayTitle, style = PoruchType.serifTitle3, color = colors.inkSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(stringResource(R.string.companion_sheet_body), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            val meetAt = times.getOrNull(at)
            if (meetAt != null) {
                val lead = (times.size - 1 - at) * CompanionRules.STEP_MINUTES
                Stepper(
                    stringResource(R.string.companion_meet_time),
                    sessionLabel(EventSession(event.id, meetAt, event.timeZone), words).second,
                    if (lead == 0) stringResource(R.string.companion_at_start) else stringResource(R.string.companion_lead, durationWords(lead)),
                    stringResource(R.string.companion_earlier) to { at-- }, at > 0,
                    stringResource(R.string.companion_later) to { at++ }, at < times.lastIndex
                )
            }
            LabelledField(
                stringResource(R.string.companion_meet_note), note, { note = it.take(CompanionRules.NOTE_MAX) },
                placeholder = stringResource(R.string.companion_meet_note_hint)
            )
            Stepper(
                stringResource(R.string.companion_capacity), capacity.toString(), null,
                stringResource(R.string.companion_fewer) to { capacity-- }, capacity > CompanionRules.MIN_CAPACITY,
                stringResource(R.string.companion_more) to { capacity++ }, capacity < CompanionRules.MAX_CAPACITY
            )
            PrimaryButton(
                stringResource(R.string.companion_create),
                { if (meetAt != null) sheet.close { onIntent(DetailIntent.CreateCompanion(meetAt, note, capacity)) } },
                Modifier.fillMaxWidth(), enabled = meetAt != null && !mutating, loading = mutating, icon = Icons.Outlined.Share
            )
        }
    }
}

/** Значення з кнопками «−» і «+». Підписи кнопок — для TalkBack. */
@Composable
private fun Stepper(
    label: String, value: String, caption: String?,
    minus: Pair<String, () -> Unit>, minusEnabled: Boolean,
    plus: Pair<String, () -> Unit>, plusEnabled: Boolean
) {
    val colors = Poruch.colors
    Row(
        // Тло поля, а не картки: у шторці картка біла на білому.
        Modifier.fillMaxWidth().background(LocalFieldSurface.current ?: colors.surface, Radius.md)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
            Text(value, style = MaterialTheme.typography.titleLarge, color = colors.ink)
            caption?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary) }
        }
        StepButton(Icons.Outlined.Remove, minus.first, minusEnabled, minus.second)
        StepButton(Icons.Outlined.Add, plus.first, plusEnabled, plus.second)
    }
}

@Composable
private fun StepButton(icon: ImageVector, description: String, enabled: Boolean, onClick: () -> Unit) {
    val colors = Poruch.colors
    Box(
        Modifier.minimumInteractiveComponentSize().size(40.dp).clip(CircleShape).background(colors.surface)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(icon, description, Modifier.size(20.dp), tint = if (enabled) colors.ink else colors.inkTertiary) }
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
        Modifier.minimumInteractiveComponentSize().size(40.dp).background(Color.White.copy(alpha = 0.92f), CircleShape)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), CircleShape).clip(CircleShape).clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(icon, description, Modifier.size(18.dp), tint = Color(0xFF14130F)) }
}

/** Скільки учасників видно до «Показати всіх». */
private const val ROSTER_COLLAPSED = 3

/** Висота обкладинки й скільки її низу ховається під аркушем секцій. */
private val HERO_HEIGHT = 480.dp
private val HERO_OVERLAP = 28.dp
/** Звідки й за скільки гасне текст на обкладинці при прокрутці. */
private val HERO_TEXT_FADE_FROM = 100.dp
private val HERO_TEXT_FADE = 140.dp
/** За скільки проявляється смуга під статусом, поки аркуш під'їжджає до неї. */
private val SCRIM_FADE = 40.dp
