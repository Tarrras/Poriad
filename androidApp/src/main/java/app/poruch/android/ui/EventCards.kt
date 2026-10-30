package app.poruch.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.domain.Event
import app.poruch.domain.Listing
import app.poruch.domain.ListingState
import app.poruch.domain.ArtistKind
import app.poruch.domain.ArtistRole
import coil3.compose.AsyncImage

/** Обкладинка без фото — градієнт категорії з її гліфом. Фото отримує затемнення знизу під білі бейджі. */
@Composable
fun EventImage(event: Event, modifier: Modifier, glyphSize: Dp = 26.dp) {
    Box(
        modifier.background(categoryGradient(event.category)),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            categoryIcon(event.category),
            null,
            Modifier.size(glyphSize),
            tint = categoryInk(event.category)
        )
        event.imageUrl?.let {
            AsyncImage(
                model = it,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
            Box(
                Modifier
                    .matchParentSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(
                                Color.Black.copy(alpha = 0.28f),
                                Color.Transparent,
                                Color.Black.copy(alpha = 0.12f)
                            )
                        )
                    )
            )
        }
    }
}

/**
 * Стан події словами: скасовано, відкладено, перенесено, а для кімнати — «ви йдете», запит, черга, місця. Без підпису
 * джерела афіші.
 */
@Composable
fun eventState(event: Event, waitlisted: Boolean = false): Pair<String, BadgeTone>? {
    if (event.isCancelled) return stringResource(R.string.cancelled) to BadgeTone.Danger
    event.listing?.let { return listingStamp(it) }
    val room = event.gathering ?: return null
    // Місця й «ви йдете» після кінця нічого не кажуть: рядок покаже категорію.
    if (event.hasEnded(kotlin.time.Clock.System.now())) return null
    return when {
        room.joined -> stringResource(R.string.going) to BadgeTone.Success
        room.awaitingApproval -> stringResource(R.string.request_pending) to BadgeTone.Accent
        waitlisted -> stringResource(R.string.in_queue) to BadgeTone.Accent
        room.isFull -> stringResource(R.string.full) to BadgeTone.Neutral
        // Коротко, як на iOS: штамп на вузькому квитку не мусить налазити на «Зберегти».
        room.isScarce -> stringResource(R.string.seats_left_short, room.seatsLeft) to BadgeTone.Accent
        else -> null
    }
}

/**
 * Стан афіші з усіх продавців (docs/event-offers.md R8): відкладено — тривога, як скасування; перенесено — терміновість,
 * подія жива; «не знайшли в продажу» — без тривоги, бо ми не знаємо, що сталось. Скасовану бере [eventState].
 */
@Composable
fun listingStamp(listing: Listing): Pair<String, BadgeTone>? = when {
    listing.state == ListingState.POSTPONED -> stringResource(R.string.state_postponed) to BadgeTone.Danger
    listing.state == ListingState.UNKNOWN -> stringResource(R.string.state_unknown) to BadgeTone.Neutral
    listing.isMoved -> stringResource(R.string.state_moved) to BadgeTone.Accent
    else -> null
}

/** «~~пт 21.11, 19:00~~ → нд 23.11, 18:00» під штампом перенесеної афіші. */
@Composable
fun MovedLine(event: Event) {
    val (old, new) = movedDates(event) ?: return
    Text(
        buildAnnotatedString {
            withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { append(old) }
            append(" → $new")
        },
        style = MaterialTheme.typography.bodySmall, color = Poruch.colors.inkSecondary, maxLines = 1,
        overflow = TextOverflow.Ellipsis
    )
}

/** Рядок стану над карткою. Афіша завжди підписана джерелом (docs/event-ingestion.md §8); місця й черга лише в кімнати. */
@Composable
private fun eventStatus(event: Event, waitlisted: Boolean = false): Pair<String, BadgeTone>? =
    eventState(event, waitlisted)
        ?: event.listing?.let { stringResource(R.string.listing_badge, it.sellerNames) to BadgeTone.Neutral }

/** Рядок під назвою: учасники для кімнати, ціна для афіші. */
@Composable
private fun EventMeta(event: Event, short: Boolean = false) {
    val room = event.gathering
    val listing = event.listing
    when {
        room != null -> MetaLine(
            PoruchIcons.social,
            stringResource(
                if (short) R.string.attendees_short else R.string.attendees,
                room.attendeeCount,
                room.capacity
            )
        )

        listing != null -> MetaLine(PoruchIcons.ticket, listingPrice(listing))
    }
}

/**
 * Крапка категорії плюс її назва кольором категорії. [placeFirst] — місце першим, а категорія лише крапкою:
 * на постері назва закладу важливіша за жанр, який і так каже афіша; жанр лишається для TalkBack.
 */
@Composable
fun EventDescriptor(
    event: Event,
    modifier: Modifier = Modifier,
    withCity: Boolean = false,
    placeFirst: Boolean = false
) {
    val colors = Poruch.colors
    // Роздільник лише коли є текст праворуч. Назва закладу, коли є, замість адреси.
    // Місто першим: у видачі з різних міст воно важливіше за адресу й не зникає під трьома крапками.
    val place = if (withCity) placeWithCity(event) else event.placeLabel
    val category = stringResource(categoryLabel(event.category))
    Row(
        if (placeFirst) modifier.semantics(mergeDescendants = true) {
            contentDescription =
                listOf(category, place).filter { it.isNotBlank() }.joinToString(", ")
        }
        else modifier,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CategoryDot(event.category)
        if (placeFirst) Text(
            place.ifBlank { category },
            style = MaterialTheme.typography.bodySmall,
            color = colors.inkSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        ) else {
            Text(
                category,
                style = PoruchType.descriptor,
                color = categoryInk(event.category),
                maxLines = 1
            )
            place.takeIf { it.isNotBlank() }?.let { place ->
                Text(
                    "· $place",
                    style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary,
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

/** Квиток стрічки: фото врівень із краєм, назва й опис; на корінці — збереження й час. Минулий квиток пробито. */
@Composable
fun EventCard(
    event: Event,
    modifier: Modifier = Modifier,
    saved: Boolean = false,
    waitlisted: Boolean = false,
    /** Назвати місто в підписі: видача з різних міст. */
    withCity: Boolean = false,
    onSave: (() -> Unit)? = null,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val badge = eventStatus(event, waitlisted)
    Ticket(
        ticketStub(event),
        stub = {
            Column(Modifier.fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                if (onSave != null) SaveButton(saved, onSave, Modifier.padding(top = Spacing.sm))
                Spacer(Modifier.weight(1f).heightIn(min = Spacing.md))
                StubTime(event)
                Spacer(Modifier.weight(1f).heightIn(min = Spacing.md))
            }
        },
        modifier = modifier.fillMaxWidth()
            .ticketSemantics(ticketA11yLabel(event, badge?.first), onClick, saved, onSave),
        punched = event.hasEnded(kotlin.time.Clock.System.now()),
        onClick = onClick
    ) {
        Column {
            // Фото врівень із краєм квитка; без фото обкладинки нема — квиток і так кольоровий.
            if (event.hasCover) Box(Modifier.fillMaxWidth().height(180.dp)) {
                EventImage(event, Modifier.fillMaxSize())
                badge?.let { (text, tone) -> TicketStamp(text, tone, onFill = true, modifier = Modifier.padding(Spacing.md)) }
            }
            Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                if (!event.hasCover) badge?.let { (text, tone) -> TicketStamp(text, tone) }
                Text(
                    event.displayTitle, style = PoruchType.brandTitle3, color = colors.ink,
                    maxLines = 2, overflow = TextOverflow.Ellipsis
                )
                EventDescriptor(event, withCity = withCity)
                artistsLine(event)?.let { MetaLine(PoruchIcons.person, it) }
                // Місця зустрічі — на корінці.
                if (event.gathering == null) EventMeta(event)
            }
        }
    }
}

/** Компактний рядок списку: малий корінець з часом, назва, опис. */
@Composable
fun EventRow(
    event: Event,
    modifier: Modifier = Modifier,
    unread: Int = 0,
    waitlisted: Boolean = false,
    /** Рядок замість статусу й категорії: «Ваша оцінка ★ 5». */
    note: String? = null,
    /** Праворуч власна дія рядка замість шеврона. */
    trailing: (@Composable () -> Unit)? = null,
    /** Статус замість звичного: «2 запити на участь» у своїй події. */
    status: Pair<String, BadgeTone>? = null,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val badge = status ?: eventState(event, waitlisted)
    val source = event.listing?.takeIf { !it.isWithdrawn }?.let { stringResource(R.string.listing_badge, it.sellerNames) }
    val unreadLabel =
        if (unread > 0) stringResource(R.string.unread_messages_a11y, unread) else null
    Row(
        modifier
            .fillMaxWidth()
            .ticketSemantics(ticketA11yLabel(event, note ?: listOfNotNull(badge?.first, source).joinToString(", ")), onClick, status = unreadLabel)
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StubTile(event)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(
                event.displayTitle, style = PoruchType.brandTitle3, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            when {
                note != null -> Text(
                    note,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary,
                    maxLines = 1
                )

                // Жанр і місце — завжди; штамп — лише коли з квитком щось сталось. Джерело афіші — тихим підписом,
                // а не штампом: штамп «Афіша · Concert.ua» витісняв жанр і місце з усіх рядків афіші.
                else -> {
                    badge?.let { TicketStamp(it.first, it.second, modifier = Modifier.padding(top = 2.dp)) }
                    MovedLine(event)
                    EventDescriptor(event)
                    source?.let {
                        Text(it, style = MaterialTheme.typography.labelSmall, color = colors.inkTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
        // Непрочитане в чаті — той самий бейдж, що на вкладці: видно, куди він веде.
        if (unread > 0) CountBadge(unread)
        if (trailing != null) trailing()
        else Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
    }
}

/** Місто перед закладом чи адресою, якщо адреса вже з нього не починається. */
private fun placeWithCity(event: Event): String {
    val place = event.placeLabel
    return if (event.city.isBlank() || place == event.city || place.startsWith(event.city + ",")) place
    else listOf(event.city, place).filter { it.isNotBlank() }.joinToString(", ")
}

/** Відступ лінії між рядками видачі пошуку: від тексту, а не від краю. */
val ResultRowInset = Spacing.lg + 56.dp + Spacing.md

/**
 * Рядок видачі пошуку: малий корінець з часом, назва й «категорія · місце · ціна»; справа — штамп
 * стану кімнати. Кілька рядків збирає [GroupedRows]. Афіша підписана джерелом окремим рядком:
 * атрибуція на картці обов'язкова (docs/event-ingestion.md §8).
 */
@Composable
fun EventResultRow(
    event: Event,
    modifier: Modifier = Modifier,
    waitlisted: Boolean = false,
    /** Назвати місто в підписі: видача з різних міст. */
    withCity: Boolean = false,
    /** Відстань від людини («2 км»): першою в підписі, бо за нею впорядковано список. Null — без неї. */
    distance: String? = null,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val badge = resultBadge(event, waitlisted)
    val price = event.listing?.takeIf { it.isFree == true || it.priceMin != null }
        ?.let { listingPrice(it).replaceFirstChar { c -> c.lowercase() } }
    val subtitle = listOfNotNull(
        distance,
        stringResource(categoryLabel(event.category)),
        (if (withCity) placeWithCity(event) else event.placeLabel).takeIf { it.isNotBlank() },
        price
    ).joinToString(" · ")
    Row(
        modifier
            .fillMaxWidth()
            .ticketSemantics(listOfNotNull(ticketA11yLabel(event, badge?.first), distance).joinToString(", "), onClick)
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        StubTile(event, 56.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                event.displayTitle, style = PoruchType.brandTitle3, color = colors.ink,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            Text(
                subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            artistsLine(event)?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            event.listing?.let { listing ->
                Text(
                    stringResource(R.string.listing_badge, listing.sellerNames),
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.inkTertiary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        badge?.let { (text, tone) -> TicketStamp(text, tone) }
    }
}

/** Бейдж рядка видачі: лише те, що міняє рішення, — скасування, зняття, стан кімнати. Джерело афіші — окремим рядком. */
@Composable
private fun resultBadge(event: Event, waitlisted: Boolean): Pair<String, BadgeTone>? {
    if (event.isCancelled) return stringResource(R.string.cancelled) to BadgeTone.Danger
    event.listing?.let { return listingStamp(it) }
    val room = event.gathering ?: return null
    if (event.hasEnded(kotlin.time.Clock.System.now())) return null
    return when {
        room.joined -> stringResource(R.string.going) to BadgeTone.Success
        waitlisted -> stringResource(R.string.in_queue) to BadgeTone.Accent
        room.isFull -> stringResource(R.string.full) to BadgeTone.Neutral
        room.isScarce -> pluralStringResource(
            R.plurals.seats_short,
            room.seatsLeft,
            room.seatsLeft
        ) to BadgeTone.Accent

        else -> null
    }
}

/**
 * Склад для картки одним рядком: до трьох імен, ведучий окремо («· ведучий Дмитро»), решта «та ще N». Null — артистів нема.
 * Імена в картці не тапаються: вся картка вже кнопка, тапабельні чипи лише в деталях ([Lineup]).
 */
@Composable
fun artistsLine(event: Event): String? {
    val shown = event.cardArtists
    if (shown.isEmpty()) return null
    val performers = shown.filter { it.role != ArtistRole.HOST }.joinToString(", ") { it.name }
    val hosts = shown.filter { it.role == ArtistRole.HOST }.joinToString(", ") { it.name }
    val host = if (hosts.isEmpty()) null else stringResource(R.string.artist_line_host, hosts)
    val line = listOfNotNull(performers.takeIf { it.isNotEmpty() }, host).joinToString(" · ")
    return if (event.moreArtists > 0) stringResource(
        R.string.artist_line_more,
        line,
        event.moreArtists
    ) else line
}

/** Вид словом, лише коли він відомий і не людина: `person` без підпису. */
@Composable
fun artistKindLabel(kind: ArtistKind?): String? = when (kind) {
    ArtistKind.GROUP -> stringResource(R.string.artist_kind_group)
    ArtistKind.SHOW -> stringResource(R.string.artist_kind_show)
    ArtistKind.COMPANY -> stringResource(R.string.artist_kind_company)
    ArtistKind.PERSON, null -> null
}

/** Квиток каруселі над мапою: досить широкий для назви, досить низький, щоб мапу було видно. */
@Composable
fun EventMapCard(
    event: Event, modifier: Modifier = Modifier, focused: Boolean = false,
    saved: Boolean = false, onSave: (() -> Unit)? = null, onClick: () -> Unit
) {
    val colors = Poruch.colors
    val state = eventState(event)
    Ticket(
        ticketStub(event),
        stub = {
            // «Зберегти» на корінці, як на великому квитку: в основній частині назва важливіша.
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                if (onSave != null) SaveButton(saved, onSave)
                // Жанр словами — в основній частині: на корінці над «Зберегти» й часом йому не лишалось місця.
                StubTime(event, compact = onSave != null, showsGenre = false)
            }
        },
        modifier = modifier
            .ticketSemantics(ticketA11yLabel(event, state?.first), onClick, saved, onSave, selected = focused),
        stubLength = 80.dp, radius = Corner.lg, surface = colors.surfaceRaised, elevation = Elevation.raised,
        outline = if (focused) colors.ink else null, dashed = false, onClick = onClick
    ) {
        Row(
            Modifier.height(mapCardHeight()).padding(start = Spacing.md, end = Spacing.sm),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
            verticalAlignment = Alignment.CenterVertically
        ) {
            EventImage(event, Modifier.size(76.dp).clip(Radius.sm))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                // Назва поступається штампу: слот картки фіксований, і довга назва інакше виштовхує його за край.
                Text(
                    event.displayTitle,
                    style = PoruchType.brandTitle3,
                    color = colors.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                // Склад замість місця: на слоті картки місця для обох нема, а хто виступає каже більше.
                val artists = artistsLine(event)
                if (state != null) TicketStamp(state.first, state.second)
                else if (artists != null) MetaLine(PoruchIcons.person, artists)
                else EventDescriptor(event)
            }
        }
    }
}

/** Висота квитка в каруселі мапи: 112 dp, з великим шрифтом — до 1.6 раза, щоб назва й місце не обрізались. */
@Composable
fun mapCardHeight(): Dp = 112.dp * LocalDensity.current.fontScale.coerceIn(1f, 1.6f)
