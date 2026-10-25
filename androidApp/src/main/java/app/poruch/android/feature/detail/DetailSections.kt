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
import app.poruch.domain.CheckedDay
import app.poruch.domain.CheckedLabel
import app.poruch.domain.CompanionParent
import app.poruch.domain.PendingMeet
import app.poruch.domain.Event
import app.poruch.domain.Listing
import app.poruch.domain.ListingState
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

// Секції екрана деталей: усе між обкладинкою й нижньою панеллю дії. Розрізано з DetailScreen.kt.

/**
 * Чат учасників. Кнопка веде не в браузер, а на попередження: посилання чуже, ми його не
 * перевіряли, і людина має це знати до того, як вийде із застосунку.
 */
@Composable
internal fun ContactSection(state: DetailState, event: Event, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.contact_section))
        if (state.screen.hasChat) {
            SecondaryButton(
                stringResource(R.string.chat_open), { onIntent(DetailIntent.OpenChat) },
                Modifier.fillMaxWidth(), icon = PoruchIcons.chat
            )
            Text(stringResource(R.string.chat_open_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        }
        if (event.gathering?.hasContact == true) {
            SecondaryButton(
                stringResource(R.string.contact_open), { onIntent(DetailIntent.ConfirmContact(true)) },
                Modifier.fillMaxWidth(), icon = PoruchIcons.link
            )
            Text(stringResource(R.string.contact_members_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        }
    }
}

/** Хто виступає: імена тапаються й ведуть на екран артиста; ведучий підписаний. Повний склад, без «та ще N» картки. */
@Composable
internal fun Lineup(event: Event, onIntent: (DetailIntent) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.lineup_title))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            event.artists.forEach { artist ->
                val host = artist.role == ArtistRole.HOST
                PoruchChip(
                    if (host) stringResource(R.string.artist_line_host, artist.name).replaceFirstChar { it.uppercase() } else artist.name,
                    selected = false, onClick = { onIntent(DetailIntent.OpenArtist(artist)) }, maxLines = 2
                )
            }
        }
    }
}

/** Для кого подія, на картці, а не через відмову сервера. В афіші обмежень віку нема. */
@Composable
internal fun Restrictions(state: DetailState) {
    val room = state.screen.room ?: return
    if (!room.hasAgeLimit && !room.approvalRequired) return
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
        if (room.hasAgeLimit) StatusBadge(ageLimitLabel(room), BadgeTone.Brand, PoruchIcons.person)
        if (room.approvalRequired) StatusBadge(stringResource(R.string.approval_badge), BadgeTone.Neutral, PoruchIcons.lock)
    }
}

/** Дати прокату. Лише коли сеансів більше одного. Скасований лишається на місці, позначеним. */
@Composable
internal fun Sessions(state: DetailState, onIntent: (DetailIntent) -> Unit, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    val words = dateWords()
    val rail = rememberLazyListState()
    // Обраний сеанс має бути видно одразу, навіть якщо він шостий.
    LaunchedEffect(Unit) {
        val at = state.screen.sessions.indexOfFirst { it.id == state.screen.sessionId }
        if (at > 0) rail.scrollToItem(at)
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.sessions_title), Modifier.padding(horizontal = Spacing.page))
        LazyRow(
            state = rail, modifier = Modifier.selectableGroup(),
            contentPadding = PaddingValues(horizontal = Spacing.page),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            items(state.screen.sessions, key = { it.id }) { session ->
                val selected = session.id == state.screen.sessionId
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
internal fun ageLimitLabel(room: Gathering): String = room.maxAge?.let {
    stringResource(R.string.age_badge_range, room.minAge, it)
} ?: stringResource(R.string.age_badge_from, room.minAge)

/** Запити на участь. На екрані деталей, бо організатор відповідає, дивлячись на свою подію. */
@Composable
internal fun JoinRequests(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.requests_section))
        state.screen.requests.forEach { person ->
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
                PrimaryButton(stringResource(R.string.approve), { onIntent(DetailIntent.ApproveRequest(person.userId)) }, enabled = !state.screen.mutating)
            }
        }
    }
}

/** Кнопка замість форми: сама оцінка — у [RatingSheet], як у «Моїх подіях». */
@Composable
internal fun RateEvent(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val event = state.screen.event ?: return
    var open by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.rate_title))
        val mine = state.screen.myRating
        if (mine == null) PrimaryButton(stringResource(R.string.rate_action), { open = true }, Modifier.fillMaxWidth())
        else SecondaryButton(
            stringResource(R.string.my_score, mine.score) + " · " + stringResource(R.string.rate_change),
            { open = true }, Modifier.fillMaxWidth()
        )
    }
    // Оцінюють учасники: організатор свою подію не оцінює, тож перемикач лише для тих, у кого є організатор.
    val follow = event.organizerId?.takeIf { !state.screen.organizer }
        ?.let { FollowRules.followOnRating(it in state.screen.followedOrganizers, state.screen.myRating != null) }
    if (open) RatingSheet(event, state.screen.myRating, state.screen.mutating, follow, { open = false }) { score, comment, tags, following ->
        onIntent(DetailIntent.Rate(score, comment, tags, following))
    }
}

/** Відгуки для організатора: середнє, що сподобалось, коментарі — без імен. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun Ratings(state: DetailState) {
    val colors = Poruch.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.ratings_title))
        val average = RatingRules.average(state.screen.ratings)
        if (average == null) {
            Text(stringResource(R.string.ratings_empty), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            return@Column
        }
        Text(
            stringResource(R.string.ratings_summary, average.toString().replace('.', ','), state.screen.ratings.size),
            style = MaterialTheme.typography.titleMedium, color = colors.ink
        )
        val tags = RatingRules.tagCounts(state.screen.ratings)
        if (tags.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            tags.forEach { StatusBadge("${stringResource(it.tag.label)} · ${it.count}") }
        }
        state.screen.ratings.filter { !it.comment.isNullOrBlank() }.forEach { rating ->
            Column(Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Stars(rating.score, size = 16.dp)
                Text(rating.comment.orEmpty(), style = MaterialTheme.typography.bodyMedium, color = colors.ink)
            }
        }
    }
}

/** П'ять зірок у відгуку організатора. */
@Composable
internal fun Stars(score: Int, size: androidx.compose.ui.unit.Dp) {
    val colors = Poruch.colors
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        (1..5).forEach { value ->
            Icon(
                if (value <= score) PoruchIcons.starFilled else PoruchIcons.star, null, Modifier.size(size),
                tint = if (value <= score) colors.brand else colors.inkTertiary
            )
        }
    }
}

/** Скарга й блокування внизу сторінки, не в меню: важка скарга — неподана скарга. */
@Composable
internal fun SafetyActions(event: Event, onIntent: (DetailIntent) -> Unit) {
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

/**
 * Квитки афіші (R8–R10): стан, коли з подією щось сталось, і продавці — кожен своїм рядком з ціною й посиланням.
 * Не в силі — «Якщо купили квиток» з усіма продавцями, де могли купити. Під ними «Перевірено…» і обіцянка «Зберегти».
 */
@Composable
internal fun Tickets(state: DetailState, listing: Listing, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val event = state.screen.event ?: return
    val refund = listing.isWithdrawn
    val sellers = if (refund) listing.sellers else listing.sellers.filter { it.live }
    val stamp = if (state.screen.cancelled) stringResource(R.string.cancelled_short) to BadgeTone.Danger else listingStamp(listing)
    Column(
        Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        stamp?.let { (text, tone) ->
            TicketStamp(text, tone)
            stateHint(event, listing)?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = colors.ink) }
        }
        listing.sellerReport?.let { report ->
            Text(
                stringResource(
                    if (report.reported == ListingState.POSTPONED) R.string.seller_reported_postponed else R.string.seller_reported_cancelled,
                    report.sourceName
                ),
                style = MaterialTheme.typography.bodyLarge, color = colors.ink
            )
        }
        if (sellers.isNotEmpty()) {
            Text(
                stringResource(if (refund) R.string.sellers_refund_title else R.string.listing_price_label).uppercase(),
                style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary
            )
            Column {
                sellers.forEachIndexed { index, offer ->
                    if (index > 0) HairLine()
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp)
                            .pressable(pressedScale = 1f) { onIntent(DetailIntent.OpenSeller(offer, if (refund) "refund" else "sellers")) }
                            .semantics(mergeDescendants = true) {},
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                    ) {
                        Text(offer.sourceName, style = MaterialTheme.typography.titleMedium, color = colors.ink, modifier = Modifier.weight(1f))
                        if (!refund) Text(offerPrice(offer), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                        Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
                    }
                }
            }
        }
        state.screen.checked?.let {
            Text(checkedText(it), style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary)
        }
        // Обіцянка «Зберегти» (R9): зберегти = стежити за змінами, з квитком чи без.
        if (!refund && !state.screen.ended) {
            HairLine()
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp)
                    .pressable(pressedScale = 1f) { onIntent(DetailIntent.ToggleSaved) }
                    .semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.md)
            ) {
                Icon(if (state.screen.saved) PoruchIcons.bookmarkFilled else PoruchIcons.bookmark, null, Modifier.size(22.dp), tint = colors.ink)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        stringResource(if (state.screen.saved) R.string.saved_short else R.string.save),
                        style = MaterialTheme.typography.titleMedium, color = colors.ink
                    )
                    Text(stringResource(R.string.save_promise), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                }
            }
        }
    }
}

/**
 * Афішу перенесли, збір чекає рішення (R7а). Організатор — три відповіді; учасник — що рішення за організатором.
 * Інша дата — «Скасувати збір» помітніше: вільного вечора може не бути.
 */
@Composable
internal fun MeetDecision(state: DetailState, event: Event, parent: CompanionParent, pending: PendingMeet, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val zone = event.timeZone
    val newStart = parent.startsAt?.let { meetWhen(it, null, zone) }.orEmpty()
    val proposed = meetWhen(pending.proposedAt, event.startsAt, zone)
    val otherDay = !sameDay(pending.proposedAt, event.startsAt, zone)
    val mutating = state.screen.mutating
    Column(Modifier.fillMaxWidth().cardSurface().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        TicketStamp(stringResource(R.string.state_moved), BadgeTone.Accent)
        if (state.screen.organizer) {
            Text(
                stringResource(R.string.meet_decision_ask, newStart, meetWhen(event.startsAt, event.startsAt, zone), proposed),
                style = MaterialTheme.typography.bodyLarge, color = colors.ink
            )
            PrimaryButton(
                stringResource(R.string.meet_move_to, proposed), { onIntent(DetailIntent.MoveMeet(pending.proposedAt)) },
                Modifier.fillMaxWidth(), enabled = !mutating, loading = mutating
            )
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
                SecondaryButton(
                    stringResource(R.string.meet_other_time), { onIntent(DetailIntent.ShowMeetTime(pending.proposedAt)) },
                    Modifier.weight(1f), enabled = !mutating
                )
                if (otherDay) SecondaryButton(
                    stringResource(R.string.meet_cancel), { onIntent(DetailIntent.ConfirmCancel(true)) },
                    Modifier.weight(1f), enabled = !mutating, tone = colors.danger
                )
            }
            if (!otherDay) GhostButton(stringResource(R.string.meet_cancel), { onIntent(DetailIntent.ConfirmCancel(true)) }, tone = colors.danger)
            Text(
                stringResource(R.string.meet_decision_deadline, meetWhen(pending.decideBy, kotlin.time.Clock.System.now().toString(), zone), proposed),
                style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
            )
        } else Text(stringResource(R.string.meet_decision_wait, newStart), style = MaterialTheme.typography.bodyLarge, color = colors.ink)
    }
}

/** Пояснення стану афіші над продавцями (R8). Null — «в силі» без переносу. */
@Composable
private fun stateHint(event: Event, listing: Listing): String? = when {
    event.isCancelled -> stringResource(R.string.state_cancelled_hint)
    listing.state == ListingState.POSTPONED -> stringResource(R.string.state_postponed_hint)
    listing.state == ListingState.UNKNOWN -> stringResource(R.string.state_unknown_hint)
    listing.isMoved -> stringResource(R.string.state_moved_hint, previousDate(event).orEmpty())
    else -> null
}

/** «Перевірено сьогодні о 09:00» — довіра до «в силі» (R8). */
@Composable
private fun checkedText(checked: CheckedLabel): String = when (checked.day) {
    CheckedDay.TODAY -> stringResource(R.string.checked_today, checked.time)
    CheckedDay.YESTERDAY -> stringResource(R.string.checked_yesterday, checked.time)
    CheckedDay.EARLIER -> stringResource(R.string.checked_date, checked.date)
}

/** «Купили? Стежитимемо за змінами» після повернення від продавця (R9): раз на подію, над панеллю дії. */
@Composable
internal fun BoughtCard(onIntent: (DetailIntent) -> Unit, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    Row(
        modifier.fillMaxWidth().padding(horizontal = Spacing.md)
            .cardSurface(Radius.lg, Elevation.overlay)
            .padding(start = Spacing.lg, end = Spacing.sm, top = Spacing.sm, bottom = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        Text(stringResource(R.string.bought_prompt), style = MaterialTheme.typography.bodyMedium, color = colors.ink, modifier = Modifier.weight(1f))
        PrimaryButton(stringResource(R.string.bought_prompt_save), { onIntent(DetailIntent.BoughtPromptAnswered(true)) }, tone = colors.ink)
        IconButton({ onIntent(DetailIntent.BoughtPromptAnswered(false)) }) {
            Icon(PoruchIcons.close, stringResource(R.string.close), Modifier.size(18.dp), tint = colors.inkSecondary)
        }
    }
}

/** Факти про подію в чотирьох рядках. Останні два різні для кімнати й афіші. */
/** Факти про подію сіткою два на два, як картка дня в Moonly: підпис над значенням, без гліфів. */
@Composable
internal fun Facts(event: Event) {
    val cells = buildList {
        add(stringResource(R.string.when_label) to eventTime(event, dateWords()))
        add(stringResource(R.string.where) to listOf(event.city, event.address).filter { it.isNotBlank() }.joinToString(" · "))
        event.gathering?.let { room ->
            add(stringResource(R.string.organizer_short) to room.organizerName.ifBlank { stringResource(R.string.organizer_short) })
            add(stringResource(R.string.capacity_label) to stringResource(R.string.attendees_short, room.attendeeCount, room.capacity))
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
internal fun FactCell(label: String, value: String, modifier: Modifier) {
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
internal fun People(state: DetailState, room: Gathering, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    var expanded by remember { mutableStateOf(false) }
    val shown = if (expanded) state.screen.attendees else state.screen.attendees.take(ROSTER_COLLAPSED)
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.attendees_going))
        GroupedRows {
            PersonRow(
                room.organizerName.ifBlank { stringResource(R.string.organizer_short) },
                state.screen.organizerAvatar,
                stringResource(R.string.organizer_short)
            ) { onIntent(DetailIntent.OpenPerson(room.organizerId)) }
            shown.forEach { person ->
                HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                PersonRow(person.name.ifBlank { stringResource(R.string.chat_member) }, person.avatarUrl) {
                    onIntent(DetailIntent.OpenPerson(person.userId))
                }
            }
            if (!expanded && state.screen.attendees.size > ROSTER_COLLAPSED) {
                HairLine(Modifier.padding(start = Spacing.lg))
                Text(
                    stringResource(R.string.attendees_show_all) + " · " + state.screen.attendees.size,
                    style = MaterialTheme.typography.labelLarge, color = colors.ink,
                    modifier = Modifier.fillMaxWidth().clickable { expanded = true }.padding(Spacing.lg)
                )
            }
        }
        // Гість і сторонній бачать лише число: імена — межа RLS.
        if (state.screen.attendees.isEmpty() && room.attendeeCount > 0) Text(
            stringResource(R.string.attendees_short, room.attendeeCount, room.capacity),
            style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary
        )
    }
}

/** Рядок людини: фото, імʼя, необовʼязковий підпис; весь рядок — кнопка на картку. */
@Composable
internal fun PersonRow(name: String, avatarUrl: String?, caption: String? = null, onClick: () -> Unit) {
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
        Icon(PoruchIcons.chevronRight, null, Modifier.size(20.dp), tint = colors.inkTertiary)
    }
}

/** Ряд круглих дій із підписами, як панель під картою дня в Moonly. */
@Composable
internal fun ExternalActions(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        RoundAction(PoruchIcons.calendar, stringResource(R.string.calendar_short), { onIntent(DetailIntent.AddToCalendar) }, Modifier.weight(1f), enabled = !state.screen.cancelled)
        RoundAction(PoruchIcons.directions, stringResource(R.string.open_in_maps), { onIntent(DetailIntent.OpenInMaps) }, Modifier.weight(1f))
        // Поділитися подією — і є покликати (docs/invites.md). Скасовану чи минулу — просто поділитися.
        // Підказка лише з входом: посилання гостя не несе імені, і пояснювати нема що.
        if (state.screen.canInvite) RoundAction(
            PoruchIcons.personAdd, stringResource(R.string.invite), { onIntent(DetailIntent.Share) },
            Modifier.weight(1f).coachTarget(CoachTip.INVITE.takeIf { state.screen.signedIn }), loading = state.inviting
        )
        else RoundAction(PoruchIcons.share, stringResource(R.string.share), { onIntent(DetailIntent.Share) }, Modifier.weight(1f))
        RoundAction(PoruchIcons.map, stringResource(R.string.on_map), { onIntent(DetailIntent.OpenMap) }, Modifier.weight(1f))
    }
}

/**
 * Місце події. Мініатюра без жестів, тап веде на велику мапу. Прозорий шар ловить дотик, бо
 * MapView з вимкненими жестами все одно поглинає його.
 */
@Composable
internal fun Venue(event: Event, following: Boolean, onIntent: (DetailIntent) -> Unit) {
    // Мапу вбудовуємо після другого кадру: MapView і стиль — найдорожче на екрані, і перехід чекав на них.
    var mapReady by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { withFrameNanos {}; withFrameNanos {}; mapReady = true }
    // Той самий список між перескладаннями: інакше міні-мапа регрупувала піни й переписувала GeoJSON на кожне.
    val pins = remember(event) { listOf(event.asIndexEntry()) }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(if (event.isCommunity) R.string.venue else R.string.venue_listing))
        Box(Modifier.fillMaxWidth().height(180.dp).cardSurface(Radius.md).padding(Spacing.xs).clip(Radius.sm)) {
            if (mapReady) EventMap(pins, event.latitude, event.longitude, selectedId = event.id, interactive = false)
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
internal fun Safety(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val shelters = state.screen.safety?.shelters.orEmpty()
    val curfew = state.screen.curfew
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
                Icon(PoruchIcons.moon, null, Modifier.size(20.dp), tint = if (tight) colors.danger else colors.inkTertiary)
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
                        if (shelter.kind == ShelterKind.METRO) PoruchIcons.subway else PoruchIcons.shield,
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
                    Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
                }
            }
        }
        // Ліцензія CC BY вимагає вказати джерело.
        if (shelters.isNotEmpty()) Text(stringResource(R.string.shelters_source), style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary)
    }
}

internal fun ShelterKind.label() = when (this) {
    ShelterKind.METRO -> R.string.shelter_metro
    ShelterKind.UNDERPASS -> R.string.shelter_underpass
    ShelterKind.PARKING -> R.string.shelter_parking
    ShelterKind.BASEMENT -> R.string.shelter_basement
}

@Composable
internal fun durationWords(minutes: Int): String {
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
internal fun OthersHere(others: List<EventIndexEntry>, placeName: String?, onIntent: (DetailIntent) -> Unit) {
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
                style = PoruchType.brandTitle2, color = colors.ink, modifier = Modifier.weight(1f)
            )
            Text("${others.size}", style = MaterialTheme.typography.labelLarge, color = colors.inkSecondary)
            Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp).rotate(if (expanded) 270f else 90f), tint = colors.inkTertiary)
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
                            TitleRules.display(other.title), style = PoruchType.brandTitle3, color = colors.ink,
                            maxLines = 2, overflow = TextOverflow.Ellipsis
                        )
                    }
                    Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
                }
            }
        }
    }
}

/** Свій опис повністю, чужий — уривком ([Event.displayDescription]) і з посиланням на джерело. */
@Composable
internal fun Description(event: Event, onIntent: (DetailIntent) -> Unit) {
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
internal fun OrganizerActions(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    HairLine()
    // Час, місце й місткість супутника тримає сервер; після початку сервер не приймає правок. Лишається скасувати.
    val editable = state.screen.companionOf == null && !state.screen.started
    if (editable) PhotoPickerButton(state.screen.mutating) { bytes, mime -> onIntent(DetailIntent.AttachPhoto(bytes, mime)) }
    // Збір: організатор міняє лише час (R7б).
    state.screen.event?.takeIf { state.screen.canMoveMeet }?.let { event ->
        SecondaryButton(
            stringResource(R.string.meet_change), { onIntent(DetailIntent.ShowMeetTime(event.startsAt)) },
            Modifier.fillMaxWidth(), enabled = !state.screen.mutating, icon = PoruchIcons.clock
        )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
        if (editable) SecondaryButton(stringResource(R.string.edit), { onIntent(DetailIntent.Edit) }, Modifier.weight(1f), icon = PoruchIcons.edit)
        SecondaryButton(
            stringResource(R.string.cancel_event), { onIntent(DetailIntent.ConfirmCancel(true)) },
            Modifier.weight(1f), enabled = !state.screen.mutating, tone = colors.danger
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

/**
 * Хто вже шукає компанію на цю афішу. Без імен: організатора видно на сторінці супутника, туди
 * й веде рядок. «Долучитися» — запит організатору прямо звідси.
 */
@Composable
internal fun Companions(state: DetailState, onIntent: (DetailIntent) -> Unit) {
    val colors = Poruch.colors
    val words = dateWords()
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        SectionHeader(stringResource(R.string.companions_title))
        Column(Modifier.cardSurface(Radius.md)) {
            state.screen.companions.forEachIndexed { index, card ->
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
                        card.membership == Membership.APPROVED -> StatusBadge(stringResource(R.string.going), BadgeTone.Success, PoruchIcons.check)
                        card.membership == Membership.REQUESTED -> StatusBadge(stringResource(R.string.request_pending), BadgeTone.Accent, PoruchIcons.clock)
                        card.isFull -> StatusBadge(stringResource(R.string.companion_full))
                        else -> SecondaryButton(
                            stringResource(R.string.companion_join), { onIntent(DetailIntent.JoinCompanion(card.id)) },
                            enabled = !state.screen.mutating
                        )
                    }
                }
            }
        }
    }
}

/** Скільки учасників видно до «Показати всіх». */
internal const val ROSTER_COLLAPSED = 3
