package app.poruch.android.feature.wallet

import android.content.Context
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import app.poruch.android.R
import app.poruch.android.feature.editor.DateTimeSheet
import app.poruch.android.platform.TicketFiles
import app.poruch.android.platform.TicketImport
import app.poruch.android.platform.toast
import app.poruch.android.ui.*
import app.poruch.domain.EventLinks
import app.poruch.domain.StoreLinks
import app.poruch.domain.WalletTicket
import app.poruch.shared.PoruchApp
import android.graphics.Bitmap
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.koin.compose.koinInject

/**
 * Що показує корінь поверх будь-якої вкладки (docs/ticket-wallet.md): шторку квитка, що прийшов файлом, і квиток на
 * весь екран — з «Моїх подій» чи з нагадування «за годину».
 */
object WalletUi {
    var intake by mutableStateOf<TicketIntake?>(null)
    var shown by mutableStateOf<String?>(null)
    /** Квиток щойно додано: «Мої події» відкриваються на «Іду», де він лежить, і скидають прапорець. */
    var added by mutableStateOf(false)

    /**
     * Шторка — одразу, ще до розбору: людина бачить, що файл дійшов. Далі [load] скаже, що це: квиток, той самий квиток
     * удруге чи не квиток.
     */
    fun intake(context: Context, app: PoruchApp, scope: CoroutineScope, load: suspend () -> TicketImport?) {
        val reading = TicketIntake.Reading()
        intake = reading
        scope.launch {
            val ticket = load()
            // Шторку закрили, поки читали: копія нікому не потрібна.
            if (intake !== reading) { ticket?.let { TicketFiles.remove(context, it.file) }; return@launch }
            intake = when (val existing = ticket?.let { app.ticketWithFingerprint(it.fingerprint) }) {
                null -> ticket?.let { TicketIntake.Ready(it) } ?: TicketIntake.Failed
                else -> TicketIntake.Duplicate(existing.id).also { TicketFiles.remove(context, ticket.file) }
            }
        }
    }
}

/** Де шторка квитка: читаємо файл, розібраний квиток, той самий квиток удруге чи файл не відкрився. */
sealed interface TicketIntake {
    /** Клас, а не object: кожне читання своє, і результат старого не перепише нове. */
    class Reading : TicketIntake
    data class Ready(val ticket: TicketImport) : TicketIntake
    data class Duplicate(val id: String) : TicketIntake
    data object Failed : TicketIntake
}

private val UKRAINIAN = Locale.forLanguageTag("uk")

private fun WalletTicket.start(): java.time.ZonedDateTime? =
    runCatching { Instant.parse(startsAt).atZone(ZoneId.of(timeZone)) }.getOrNull()

/** «пт 30.10, 19:40» у поясі квитка. */
fun ticketWhen(ticket: WalletTicket): String =
    ticket.start()?.format(DateTimeFormatter.ofPattern("EE d.MM, HH:mm", UKRAINIAN)).orEmpty()

@Composable
private fun ticketSeats(ticket: WalletTicket): String? {
    val row = stringResource(R.string.wallet_seat, "%1\$s", "%2\$s")
    val only = stringResource(R.string.wallet_seat_only, "%1\$s")
    return ticket.seats.map { seat -> seat.row?.let { row.format(it, seat.seat) } ?: only.format(seat.seat) }
        .takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

// ---- Підтвердження

/**
 * Шторка від файлу до квитка, одна на всі стани: поки читаємо — так і кажемо; той самий квиток удруге — показуємо той,
 * що вже є. Закрили розібраний без «Додати» — файл стирається: квиток не потрапив до людини.
 */
@Composable
fun TicketIntakeSheet(app: PoruchApp, intake: TicketIntake, onAdded: () -> Unit, onDone: () -> Unit) {
    val colors = Poruch.colors
    val context = LocalContext.current
    var added by remember { mutableStateOf(false) }
    PoruchSheet({ if (!added) (intake as? TicketIntake.Ready)?.let { TicketFiles.remove(context, it.ticket.file) }; onDone() }) { sheet ->
        LaunchedEffect(intake) { if (intake !is TicketIntake.Reading) sheet.expand() }
        val title = if (intake is TicketIntake.Duplicate) R.string.wallet_duplicate_title else R.string.wallet_import_title
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
            verticalArrangement = Arrangement.spacedBy(Spacing.lg)
        ) {
            Text(stringResource(title), style = PoruchType.brandTitle1, color = colors.ink, modifier = Modifier.semantics { heading() })
            when (intake) {
                is TicketIntake.Reading -> Row(horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(20.dp), color = colors.ink, strokeWidth = 2.dp)
                    Text(stringResource(R.string.wallet_reading), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                }
                TicketIntake.Failed -> {
                    Text(stringResource(R.string.wallet_failed), style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary)
                    SecondaryButton(stringResource(R.string.close), { sheet.close(onDone) }, Modifier.fillMaxWidth())
                }
                is TicketIntake.Duplicate -> {
                    val state by app.state.collectAsState()
                    val show = { sheet.close { onDone(); WalletUi.shown = intake.id } }
                    state.tickets.firstOrNull { it.id == intake.id }?.let { WalletTicketCard(it, onClick = show) }
                    PrimaryButton(stringResource(R.string.wallet_show), show, Modifier.fillMaxWidth(), icon = PoruchIcons.ticket)
                }
                is TicketIntake.Ready -> TicketImportContent(app, intake.ticket) {
                    added = true
                    WalletUi.added = true
                    // Квиток — у «Моїх подіях»: туди й ведемо, щоб людина бачила, де він тепер.
                    sheet.close { onDone(); onAdded() }
                }
            }
        }
    }
}

/** Розібраний квиток: прев'ю, знайдена подія афіші або назва, місце й коли, заповнені розбором. Одна дія — «Додати квиток». */
@Composable
private fun TicketImportContent(app: PoruchApp, ticket: TicketImport, onAdded: () -> Unit) {
    val colors = Poruch.colors
    val state by app.state.collectAsState()
    val zone = ZoneId.systemDefault()
    var title by remember { mutableStateOf(ticket.draft.title.orEmpty()) }
    var place by remember { mutableStateOf(ticket.draft.place.orEmpty()) }
    var start by remember {
        mutableStateOf(app.ticketStartMillis(ticket.draft)?.let { LocalDateTime.ofInstant(Instant.ofEpochMilli(it), zone) })
    }
    var picking by remember { mutableStateOf<Boolean?>(null) }
    val matchId = remember { app.ticketMatch(ticket.draft) }
    LaunchedEffect(matchId) { if (matchId != null && state.cards[matchId] == null) app.loadCards(listOf(matchId)) }
    val matched = matchId?.let { state.cards[it] }
    var linked by remember { mutableStateOf(true) }
    val onListing = linked && matched != null
    val canSave = onListing || (title.isNotBlank() && start != null)

    Text(pluralStringResource(R.plurals.wallet_count, ticket.count, ticket.count), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
    ticket.preview?.let {
        // Висота — з пропорції растру, не більше 220: інакше `Image` брав би висоту з пікселів (смужка дрібнішала),
        // а `aspectRatio` при повній ширині вилазив за межу й наїжджав на поля (квиток A6 з QR).
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val height = minOf(maxWidth * it.height.toFloat() / it.width.coerceAtLeast(1), 220.dp)
            Image(it.asImageBitmap(), null, Modifier.fillMaxWidth().height(height).clip(Radius.md), contentScale = ContentScale.Fit)
        }
    }
    if (ticket.draft.parsed == "none") {
        Text(stringResource(R.string.wallet_unreadable), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
    }
    matched?.let { event ->
        // Рядок — один перемикач: TalkBack читає «Квиток на цю подію», назву й стан разом.
        Row(
            Modifier.fillMaxWidth().cardSurface(Radius.md).toggleable(linked, role = Role.Switch) { linked = it }.padding(Spacing.lg),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.wallet_match), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
                Text(event.displayTitle, style = MaterialTheme.typography.titleSmall, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(eventTime(event, dateWords()), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
            }
            PoruchSwitch(linked, null)
        }
    }
    if (!onListing) {
        LabelledField(stringResource(R.string.wallet_name), title, { title = it }, placeholder = stringResource(R.string.wallet_name_hint))
        LabelledField(stringResource(R.string.wallet_place), place, { place = it }, placeholder = stringResource(R.string.wallet_place_hint))
        DateTimeField(
            stringResource(R.string.wallet_when),
            start?.format(DateTimeFormatter.ofPattern("EE, d MMMM", UKRAINIAN))?.replaceFirstChar { it.uppercase() }.orEmpty(),
            start?.format(DateTimeFormatter.ofPattern("HH:mm")).orEmpty(),
            null, onDate = { picking = false }, onTime = { picking = true }
        )
    }
    PrimaryButton(stringResource(R.string.wallet_save), {
        val event = matched?.takeIf { onListing }
        val millis = event?.startInstant?.toEpochMilliseconds() ?: start?.atZone(zone)?.toInstant()?.toEpochMilli() ?: return@PrimaryButton
        app.addTicket(
            ticket.id, ticket.file, ticket.kind, event?.displayTitle ?: title, event?.placeLabel ?: place, millis,
            ticket.count, ticket.draft.seats, event?.id, ticket.source, ticket.draft.parsed, ticket.fingerprint
        )
        onAdded()
    }, Modifier.fillMaxWidth(), enabled = canSave, icon = PoruchIcons.ticket)
    picking?.let { time ->
        DateTimeSheet(
            start ?: LocalDateTime.now().withHour(19).withMinute(0), null,
            stringResource(R.string.wallet_when), time, onDismiss = { picking = null }
        ) { start = it; picking = null }
    }
}

// ---- Показ

/** Квиток на весь екран: сторінки гортаються, яскравість угору, поки на екрані QR. */
@Composable
fun TicketViewer(app: PoruchApp, ticketId: String, onClose: () -> Unit) {
    val colors = Poruch.colors
    val context = LocalContext.current
    val state by app.state.collectAsState()
    val ticket = state.tickets.firstOrNull { it.id == ticketId } ?: return
    val width = with(LocalDensity.current) { LocalConfiguration.current.screenWidthDp.dp.roundToPx() }
    var count by remember { mutableIntStateOf(0) }
    var deleting by remember { mutableStateOf(false) }
    LaunchedEffect(ticketId) {
        count = TicketFiles.pageCount(context, ticket)
        app.ticketShown(ticketId)
    }
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        // Яскравість — вікну шторки: поки квиток на екрані, сканер на вході читає QR і на мінімальній яскравості.
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        DisposableEffect(window) {
            window?.attributes = window?.attributes?.apply { screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL }
            onDispose { }
        }
        Column(
            Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().padding(horizontal = Spacing.page, vertical = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Spacing.md)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(ticket.title, style = PoruchType.brandTitle2, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(listOfNotNull(ticketWhen(ticket), ticket.place).filter { it.isNotBlank() }.joinToString(" · "),
                        style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                    ticketSeats(ticket)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary) }
                }
                val close = stringResource(R.string.close)
                Box(
                    Modifier.size(48.dp).clip(CircleShape).background(colors.surface).pressable(onClick = onClose)
                        .semantics { contentDescription = close },
                    contentAlignment = Alignment.Center
                ) { Icon(PoruchIcons.close, null, Modifier.size(20.dp), tint = colors.ink) }
            }
            val pager = rememberPagerState { count }
            HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth(), pageSpacing = Spacing.md) { index ->
                // Сторінка малюється, коли до неї догорнули: PDF на десять квитків не тримає десять растрів.
                var bitmap by remember(index) { mutableStateOf<Bitmap?>(null) }
                LaunchedEffect(index) { bitmap = TicketFiles.page(context, ticket, index, width) }
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    bitmap?.let {
                        Image(
                            it.asImageBitmap(), pluralStringResource(R.plurals.wallet_count, ticket.count, ticket.count),
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(Corner.md)).background(Color.White),
                            contentScale = ContentScale.Fit
                        )
                    } ?: CircularProgressIndicator(Modifier.size(24.dp), color = colors.ink, strokeWidth = 2.dp)
                }
            }
            if (count > 1) Row(Modifier.align(Alignment.CenterHorizontally), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                repeat(count) { i ->
                    Box(Modifier.size(8.dp).clip(CircleShape).background(if (i == pager.currentPage) colors.ink else colors.inkTertiary.copy(alpha = 0.5f)))
                }
            }
            // Квиток тому, з ким ідеш: лише сторінка, яку видно, і що-коли-де з посиланням (docs/ticket-wallet.md, хвиля 2).
            val sendText = stringResource(
                R.string.wallet_send_text, ticket.title, listOfNotNull(ticketWhen(ticket), ticket.place).filter { it.isNotBlank() }.joinToString(" · ")
            // Кіно без афіші — посилання на сайт: той, кому квиток, дізнається, звідки він.
            ) + "\n" + (ticket.eventId?.let { EventLinks.url(it) } ?: StoreLinks.SHARE)
            val scope = rememberCoroutineScope()
            SecondaryButton(stringResource(R.string.wallet_send), {
                scope.launch {
                    if (TicketFiles.share(context, ticket, pager.currentPage, sendText)) app.ticketSent(ticket.id)
                    else context.toast(R.string.wallet_failed)
                }
            }, Modifier.fillMaxWidth(), icon = PoruchIcons.share)
            GhostButton(stringResource(R.string.wallet_delete), { deleting = true }, Modifier.align(Alignment.CenterHorizontally), tone = colors.danger)
        }
        if (deleting) PoruchConfirmSheet(
            stringResource(R.string.wallet_delete_title), stringResource(R.string.wallet_delete_body),
            stringResource(R.string.wallet_delete), stringResource(R.string.cancel),
            onConfirm = {
                app.removeTicket(ticket.id)
                TicketFiles.remove(context, ticket.file)
                deleting = false
                onClose()
            },
            onDismiss = { deleting = false }, tone = colors.danger
        )
    }
}

// ---- «Мої події»

/**
 * Секція «Квитки» згори «Моїх подій»: що попереду, з датою й місцем. Нема — один рядок, що вчить «Поділитися». Минулі —
 * пробиті й згорнуті під рядком: квиток на згадку, а не в черзі з тими, що попереду.
 */
@Composable
fun TicketsSection(tickets: List<WalletTicket>, past: List<WalletTicket>, modifier: Modifier = Modifier) {
    val colors = Poruch.colors
    val app = koinInject<PoruchApp>()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        WalletUi.intake(context, app, scope) { TicketFiles.load(context, uri, app, "picker") }
    }
    var showsPast by rememberSaveable { mutableStateOf(false) }
    val add = { pick.launch(arrayOf("application/pdf", "image/*")) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        if (tickets.isEmpty()) {
            Box(Modifier.cardSurface(Radius.md)) {
                LinkRow(PoruchIcons.ticket, stringResource(R.string.wallet_add_title), stringResource(R.string.wallet_add_hint), onClick = add)
            }
        } else {
            SectionHeader(stringResource(R.string.wallet_title), actionLabel = stringResource(R.string.wallet_add), onAction = add)
            tickets.forEach { ticket -> WalletTicketCard(ticket) { WalletUi.shown = ticket.id } }
        }
        if (past.isNotEmpty()) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(showsPast, role = Role.Switch) { showsPast = it },
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(stringResource(R.string.wallet_past, past.size.toString()), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                Icon(PoruchIcons.chevronDown, null, Modifier.size(16.dp).rotate(if (showsPast) 180f else 0f), tint = colors.inkTertiary)
            }
            if (showsPast) past.forEach { ticket -> WalletTicketCard(ticket, punched = true) { WalletUi.shown = ticket.id } }
        }
    }
}

// ---- Головна

/** День події: квиток першим на головній — його відкривають на вході. І в гостя, і в кіно без афіші. */
@Composable
fun TodayTickets(tickets: List<WalletTicket>, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.wallet_today))
        tickets.forEach { ticket -> WalletTicketCard(ticket) { WalletUi.shown = ticket.id } }
    }
}

/**
 * Квиток з телефона квитком «Корінця»: назва, місце й місця на поверхні, час і день — на чорнильному корінці. Чорнило, а не
 * колір жанру: це вже не афіша, а квиток у руці, і в кіно жанру нема.
 */
@Composable
fun WalletTicketCard(ticket: WalletTicket, punched: Boolean = false, onClick: () -> Unit) {
    val colors = Poruch.colors
    val start = ticket.start()
    val label = listOfNotNull(ticket.title, ticketWhen(ticket), ticket.place, pluralStringResource(R.plurals.wallet_count, ticket.count, ticket.count))
        .filter { it.isNotBlank() }.joinToString(", ")
    Ticket(
        colors.ink,
        stub = {
            Column(Modifier.fillMaxHeight().padding(horizontal = Spacing.sm), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                // Як `StubTime`: цифри стискаються до 60 %, а не обрізаються краєм корінця.
                start?.let {
                    val numeral = PoruchType.numeral.copy(color = colors.onBrand)
                    val day = MaterialTheme.typography.labelSmall.copy(color = colors.onBrand)
                    BasicText(it.format(DateTimeFormatter.ofPattern("HH:mm")), style = numeral, maxLines = 1,
                        autoSize = TextAutoSize.StepBased(numeral.fontSize * 0.6f, numeral.fontSize))
                    BasicText(it.format(DateTimeFormatter.ofPattern("EE d.MM", UKRAINIAN)).uppercase(), style = day, maxLines = 1,
                        autoSize = TextAutoSize.StepBased(day.fontSize * 0.7f, day.fontSize))
                }
            }
        },
        modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = label },
        // Минулий: пробитий, як минулі події афіші.
        punched = punched,
        // На шторці (дубль) — тло її полів, інакше поверхня квитка зливається з шторкою.
        surface = LocalFieldSurface.current ?: colors.surface,
        onClick = onClick
    ) {
        Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Text(ticket.title, style = PoruchType.brandTitle3, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            ticket.place?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary, maxLines = 2) }
            Text(ticketSeats(ticket) ?: pluralStringResource(R.plurals.wallet_count, ticket.count, ticket.count),
                style = MaterialTheme.typography.bodySmall, color = colors.inkTertiary, maxLines = 2)
        }
    }
}
