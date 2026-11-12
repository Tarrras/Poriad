package app.poruch.android.feature.detail

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import org.koin.compose.koinInject
import app.poruch.shared.PoruchApp
import app.poruch.android.feature.editor.BirthDateSheet
import app.poruch.domain.SafetyRules
import app.poruch.android.feature.wallet.WalletUi
import app.poruch.android.platform.TicketFiles
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import app.poruch.domain.ShareMode
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
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
import app.poruch.domain.Event
import app.poruch.domain.EventRules
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
import app.poruch.domain.ListingState
import app.poruch.shared.DetailAction
import app.poruch.shared.opensPaymentChat
import app.poruch.shared.questionsWithoutRequests
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import kotlinx.coroutines.delay

@Composable
fun DetailScreen(state: DetailState, onIntent: (DetailIntent) -> Unit, focusRequests: Boolean = false) {
    val colors = Poruch.colors
    val event = state.screen.event
    // «Додати квиток» з «Купили квиток?»: файл чи знімок, квиток — на цю подію (docs/ticket-wallet.md).
    val app = koinInject<PoruchApp>()
    val context = LocalContext.current
    val sessionId = state.screen.sessionId
    // Звідки «Додати квиток» для аналітики: картка «Купили квиток?» чи рядок «Вже маєте квиток?».
    var ticketSource by remember { mutableStateOf("bought") }
    val pickTicket = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        WalletUi.intake(context, app) { TicketFiles.load(it, uri, app, ticketSource, sessionId) }
    }
    val addTicket = { source: String -> ticketSource = source; pickTicket.launch(arrayOf("application/pdf", "image/*")) }
    if (event == null) {
        Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding()) {
            PageHeader(stringResource(R.string.about_event), back = { onIntent(DetailIntent.Back) })
            if (state.screen.loading) Box(Modifier.fillMaxWidth().padding(Spacing.section), contentAlignment = Alignment.Center) {
                PoruchLoader()
            // Без мережі — корінець на ниточці: подія відкриється сама, щойно мережа повернеться.
            } else if (state.screen.offline) OfflineState(
                stringResource(R.string.offline_event_hint),
                actionLabel = stringResource(R.string.try_again), onAction = { onIntent(DetailIntent.Refresh) }
            )
            // Сервер відповів порожньо або з помилкою: не глухий кут, а повтор, як на iOS.
            else EmptyState(
                PoruchIcons.calendarAlert, stringResource(R.string.err_event_unavailable), stringResource(R.string.event_unavailable_hint),
                actionLabel = stringResource(R.string.try_again), onAction = { onIntent(DetailIntent.Refresh) }
            )
        }
        return
    }
    val scroll = rememberScrollState()
    var barHeight by remember { mutableStateOf(0.dp) }
    val density = LocalDensity.current
    // «Хочу піти з компанією»: результат — у секції «Шукають компанію», нижче краю екрана. Після дотику сторінка
    // сама їде до неї й коротко підсвічує стан, а панель дії каже «Ви шукаєте компанію» з переходом до людей.
    val companyMine = state.screen.companyTeaser?.mine == true
    var companyTop by remember { mutableFloatStateOf(0f) }
    var requestsTop by remember { mutableFloatStateOf(0f) }
    val highlight = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val reduced = Poruch.reducedMotion
    val statusTop = WindowInsets.statusBars.getTop(density)
    /** Сторінка їде до секції, що починається на [top] (у координатах вікна), і коротко її обводить. */
    val focusAt: (Float) -> Unit = { top ->
        scope.launch {
            val target = (scroll.value + top - statusTop - with(density) { Spacing.lg.toPx() }).toInt().coerceIn(0, scroll.maxValue)
            if (reduced) scroll.scrollTo(target) else scroll.animateScrollTo(target, Motion.spring())
            highlight.snapTo(1f)
            delay(if (reduced) 1_500 else 700)
            if (reduced) highlight.snapTo(0f) else highlight.animateTo(0f, tween(600))
        }
    }
    val toCompany: () -> Unit = { focusAt(companyTop) }
    // «Запити · N» з головної: запити внизу, під описом і контактами — їдемо до них раз, коли вони прийшли й лягли.
    var requestsFocused by rememberSaveable { mutableStateOf(false) }
    val requestsReady = focusRequests && state.screen.organizer && state.screen.requests.isNotEmpty()
    LaunchedEffect(requestsReady) {
        if (!requestsReady || requestsFocused) return@LaunchedEffect
        requestsFocused = true
        delay(350)
        focusAt(requestsTop)
    }
    var wasMine by remember { mutableStateOf(companyMine) }
    LaunchedEffect(companyMine) {
        if (companyMine && !wasMine) toCompany()
        wasMine = companyMine
    }
    Box(Modifier.fillMaxSize().background(colors.canvas)) {
        PullToRefresh(state.refreshing, { onIntent(DetailIntent.Refresh) }, Modifier.fillMaxSize(), underStatusBar = true) {
            // Під нижньою панеллю дії — її виміряна висота разом із системною смугою: з великим шрифтом і другим рядом
            // («Шукаю компанію» під квитком) панель росте, і стала висота ховала під нею останню секцію.
            Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(bottom = barHeight + Spacing.md)) {
                Hero(event, state, scroll, onIntent)
                // Аркуш із заокругленим верхом наїжджає на обкладинку: сторінка лягає на афішу, а не продовжує її.
                Column(
                    Modifier.offset(y = -HERO_OVERLAP).fillMaxWidth().background(colors.canvas, Radius.sheet)
                ) {
                    Column(
                        Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.xl),
                        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                    ) {
                        state.screen.pendingMeet?.let { pending ->
                            state.screen.companionOf?.let { parent -> MeetDecision(state, event, parent, pending, onIntent) }
                        }
                        Restrictions(state)
                        state.screen.companionOf?.let { parent ->
                            GroupedRows {
                                LinkRow(PoruchIcons.social, stringResource(R.string.companion_parent, TitleRules.display(parent.title)), onClick = { onIntent(DetailIntent.OpenEvent(parent.id)) })
                            }
                        }
                        // Щось сталось — стан і продавці першими: по них сюди й прийшли.
                        state.screen.listing?.takeIf { it.needsAttention }?.let { TicketsBlock(state, it, onIntent, addTicket) }
                        ExternalActions(state, onIntent)
                    }
                    // Поза колонкою з полями: смуга дат іде від краю до краю.
                    if (state.screen.sessions.size > 1) Sessions(state, onIntent, Modifier.padding(top = Spacing.lg))
                    Column(
                        Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.lg),
                        verticalArrangement = Arrangement.spacedBy(Spacing.lg)
                    ) {
                        if (event.artists.isNotEmpty()) Lineup(event, onIntent)
                        RadarHint(state, onIntent)
                        Facts(event)
                        event.activePromo(kotlin.time.Clock.System.now())?.let { PromoRow(event, it) { onIntent(DetailIntent.PromoCopied) } }
                        val listing = state.screen.listing
                        if (listing == null) { if (state.screen.myTickets.isNotEmpty()) YourTickets(state.screen.myTickets) }
                        else if (!listing.needsAttention) TicketsBlock(state, listing, onIntent, addTicket)
                        if (state.screen.canWantCompany && !state.screen.cancelled) CompanySection(
                            state, onIntent, { highlight.value },
                            Modifier.onGloballyPositioned { companyTop = it.positionInRoot().y }
                        )
                        else if (state.screen.companions.isNotEmpty() && !state.screen.cancelled) Companions(state, onIntent)
                        // Організатору, коли там лише він, секції нема: «0 з 20» уже в «Місткості». Гостю лишається — рядок
                        // організатора там єдиний вхід до його картки й «Стежити».
                        event.gathering?.takeIf { !state.screen.organizer || it.attendeeCount > 0 || state.screen.attendees.isNotEmpty() }
                            ?.let { People(state, it, onIntent) }
                        if (state.screen.canAsk) AskOrganizer(state, onIntent)
                        Venue(event, state.screen.followingPlace, onIntent)
                        // Безпека й «Ще в цьому місці» — для тих, хто йде; організатору на своїй події вони зайві (власник, 11.11).
                        if (!state.screen.organizer && !state.screen.cancelled && !state.screen.ended) Safety(state, onIntent)
                        Description(event, onIntent)
                        if (!state.screen.organizer && state.screen.othersHere.isNotEmpty()) OthersHere(state.screen.othersHere, event.placeName, onIntent)
                        // Чат і посилання — для своїх: сервер віддає посилання лише організатору й підтвердженим.
                        if (state.screen.hasChat || event.gathering?.hasContact == true) ContactSection(state, event, onIntent)
                        if (state.screen.organizer && state.screen.requests.isNotEmpty()) JoinRequests(
                            state, onIntent, { highlight.value }, Modifier.onGloballyPositioned { requestsTop = it.positionInRoot().y }
                        )
                        if (state.screen.organizer && state.screen.questionsWithoutRequests.isNotEmpty()) Questions(state, onIntent)
                        if (state.screen.canRate) RateEvent(state, onIntent)
                        if (state.screen.organizer && state.screen.ended && !state.screen.cancelled) Ratings(state)
                        // Після кінця редагувати й скасовувати нічого: лишаються відгуки.
                        if (state.screen.organizer && !state.screen.cancelled && !state.screen.ended) OrganizerActions(state, onIntent)
                        if (!state.screen.organizer) SafetyActions(event, onIntent)
                    }
                }
            }
        }
        // Коли аркуш доїхав до годинника, текст інакше йде під нього: смуга статусу набирає колір полотна.
        // Не раніше: світла смуга над темною обкладинкою відрізала б її.
        val hero = heroHeight()
        Box(
            Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars)
                .graphicsLayer {
                    val from = (hero - HERO_OVERLAP - SCRIM_FADE).toPx() - statusTop
                    alpha = ((scroll.value - from) / SCRIM_FADE.toPx()).coerceIn(0f, 1f)
                }
                .background(colors.canvas)
        )
        StickyAction(
            state, event,
            Modifier.align(Alignment.BottomCenter).onSizeChanged { barHeight = with(density) { it.height.toDp() } },
            onIntent, toCompany
        )
        AnimatedVisibility(
            state.boughtPrompt, Modifier.align(Alignment.BottomCenter).padding(bottom = barHeight),
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()
        ) { BoughtCard(state.screen.saved, onIntent, onAddTicket = { addTicket("bought") }) }
        // Без відповіді за 10 с картка зникає сама: це питання, а не перешкода.
        if (state.boughtPrompt) LaunchedEffect(Unit) { delay(10_000); onIntent(DetailIntent.BoughtPromptAnswered(false)) }
        CoachMarks(
            listOf(CoachTip.COMPANION, CoachTip.INVITE),
            enabled = state.screen.canSeekCompany || (state.screen.canInvite && state.screen.signedIn)
        )
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
    if (state.confirmingContact) state.screen.contactUrl?.let { url ->
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
    if (state.seekingCompany) CompanionSheet(event, state.screen.mutating, onIntent)
    // `AGE_REQUIRED`: організатор обмежив вік, а в акаунта лише галочка (чи віку нема зовсім). Дата — тут, і запис іде
    // одразу після неї.
    if (state.confirmingPayTerms) PoruchConfirmSheet(
        title = stringResource(R.string.pay_terms_title),
        message = listOfNotNull(
            stringResource(R.string.pay_terms_body), stringResource(R.string.pay_terms_direct),
            refundText(state.screen.room?.refundPolicy), stringResource(R.string.pay_terms_doubt)
        ).joinToString("\n\n"),
        confirmLabel = stringResource(R.string.pay_terms_agree),
        dismissLabel = stringResource(R.string.cancel),
        onConfirm = { onIntent(DetailIntent.PayTermsAnswered(true)) },
        onDismiss = { onIntent(DetailIntent.PayTermsAnswered(false)) }
    )
    if (state.askingBirthDate) {
        val limited = state.screen.room?.let { it.minAge > SafetyRules.MIN_SIGNUP_AGE || it.maxAge != null } == true
        BirthDateSheet(
            null, { onIntent(DetailIntent.DeclareBirthDate(null)) },
            title = stringResource(if (limited) R.string.age_date_title else R.string.confirm_age_title),
            body = stringResource(if (limited) R.string.age_date_body else R.string.birth_date_hint),
            confirm = stringResource(R.string.age_date_continue)
        ) { onIntent(DetailIntent.DeclareBirthDate(it)) }
    }
    state.movingMeet?.let { from ->
        val parent = state.screen.companionOf
        val start = parent?.startsAt
        if (parent != null && start != null) MeetTimeSheet(event, parent, start, from, state.screen.mutating, onIntent)
    }
    state.screen.person?.let { person ->
        val request = state.screen.organizer && state.screen.requests.any { it.userId == person.userId }
        PersonSheet(
            person, isMe = person.userId == state.screen.userId,
            onDismiss = { onIntent(DetailIntent.ClosePerson) },
            onBlock = { onIntent(DetailIntent.BlockPerson(person.userId)) },
            onReport = { onIntent(DetailIntent.ReportPerson(person.userId)) },
            follow = FollowAction(person.userId in state.screen.followedOrganizers) {
                onIntent(DetailIntent.ToggleFollowPerson(person.userId, person.profile?.name.orEmpty()))
            }
        ) { sheet ->
            if (state.screen.canWriteTo(person.userId)) SecondaryButton(
                stringResource(R.string.person_write), { sheet.close { onIntent(DetailIntent.OpenQuestion(person.userId)) } },
                Modifier.fillMaxWidth()
            )
            if (request) {
                Text(stringResource(R.string.person_request), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    SecondaryButton(
                        stringResource(R.string.decline), { sheet.close { onIntent(DetailIntent.DeclineRequest(person.userId)) } },
                        Modifier.weight(1f), enabled = !state.screen.mutating
                    )
                    PrimaryButton(
                        stringResource(if (state.screen.payOnline) R.string.approve_paid else R.string.approve), { sheet.close { onIntent(DetailIntent.ApproveRequest(person.userId)) } },
                        Modifier.weight(1f), enabled = !state.screen.mutating
                    )
                }
            }
        }
    }
}

@Composable
internal fun StickyAction(
    state: DetailState, event: Event, modifier: Modifier, onIntent: (DetailIntent) -> Unit,
    /** Перехід до «Шукають компанію» з рядка «Ви шукаєте компанію». */
    onShowCompany: () -> Unit = {}
) {
    val colors = Poruch.colors
    // Від 1,3 ціна й «Купити квиток» — одне під одним, як на iOS і в `NextPlanCard`: поруч кнопка забирала ширину,
    // і «від 550 ₴» ставало стовпчиком літер саме в момент рішення.
    val stacked = LocalDensity.current.fontScale >= 1.3f
    // Панель дії — квиток у руці: місця чи ціна й дії на поверхні, а корінець із часом, днем і кольором жанру — справа.
    // Дата на екрані одна, тут; обкладинка її не повторює. Плаває над сторінкою: дія під пальцем, а не смуга на всю ширину.
    Ticket(
        ticketStub(event), stub = { StubTime(event) },
        modifier = modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = Spacing.md, vertical = Spacing.sm),
        radius = Corner.xl, surface = colors.surfaceRaised, elevation = Elevation.overlay
    ) {
        Column(
            Modifier.padding(horizontal = Spacing.lg, vertical = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            val hint = @Composable { modifier: Modifier ->
                Text(
                    stickyHint(state),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (event.isCalledOff) colors.danger else colors.inkSecondary,
                    maxLines = 3, overflow = TextOverflow.Ellipsis, modifier = modifier
                )
            }
            if (state.screen.canWantCompany || state.screen.canSeekCompany) {
                // Афіша: ціна й квиток в один рядок — квиток купують на чужому сайті, тож він другорядний.
                val buy = @Composable { modifier: Modifier ->
                    if (state.screen.action != DetailAction.NONE) SecondaryButton(
                        stringResource(state.screen.action.label), { onIntent(DetailIntent.PrimaryAction) }, modifier,
                        enabled = state.screen.action.isEnabled && !state.screen.mutating, compact = !stacked
                    )
                }
                if (stacked) Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    hint(Modifier.fillMaxWidth())
                    buy(Modifier.fillMaxWidth())
                } else Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                    hint(Modifier.weight(1f))
                    buy(Modifier)
                }
            } else {
                // Зустріч: пояснення («Організатор підтверджує кожного», «Лишилось 2 місця») — окремим рядком на всю
                // ширину, а дія під ним. Поруч із кнопкою воно обрізалось саме в момент рішення. Записаним стан каже
                // штамп перед ним, а кнопка під ним стає тоновою.
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                    JoinStamp(state.screen.action, state.screen.payOnline, state.stampPending) { onIntent(DetailIntent.StampShown) }
                    hint(Modifier.weight(1f))
                }
                // Кнопки може не бути: у знятої афіші й афіші без посилання нема куди вести.
                if (state.screen.action != DetailAction.NONE) PrimaryAction(state, onIntent, Modifier.fillMaxWidth())
            }
            // Серце продукту — люди: на афіші головна дія — «Хочу піти з компанією», на всю ширину під ціною й квитком.
            // Після наміру кнопка не зникає мовчки: на її місці стан «Ви шукаєте компанію» з переходом до людей.
            if (state.screen.canWantCompany) {
                if (state.screen.companyTeaser?.mine == true) CompanySearchingRow(onShowCompany)
                else PrimaryButton(
                    stringResource(R.string.company_want), { onIntent(DetailIntent.WantCompany) },
                    Modifier.fillMaxWidth().coachTarget(CoachTip.COMPANION), enabled = !state.screen.mutating,
                    icon = if (stacked) null else PoruchIcons.social
                )
            }
        }
    }
}

/** Стан замість кнопки, що зникла: «Ви шукаєте компанію» і перехід до тих, хто теж шукає. Тап — сторінка їде до них. */
@Composable
private fun CompanySearchingRow(onClick: () -> Unit) {
    val colors = Poruch.colors
    val action = stringResource(R.string.company_bar_people)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(Radius.md)
            .clickable(onClickLabel = action, role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { }
            .padding(vertical = Spacing.xs),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md), verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(36.dp).background(colors.successContainer, CircleShape), contentAlignment = Alignment.Center) {
            Icon(PoruchIcons.check, null, Modifier.size(18.dp), tint = colors.onSuccessContainer)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.company_searching), style = MaterialTheme.typography.titleSmall, color = colors.ink)
            Text(action, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
        Icon(PoruchIcons.chevronDown, null, Modifier.size(18.dp), tint = colors.inkTertiary)
    }
}

@Composable
internal fun PrimaryAction(state: DetailState, onIntent: (DetailIntent) -> Unit, modifier: Modifier = Modifier) {
    val action = state.screen.action
    when {
        state.screen.opensPaymentChat -> SecondaryButton(
            stringResource(R.string.pay_chat_open), { onIntent(DetailIntent.OpenQuestion()) }, modifier, icon = PoruchIcons.chat
        )
        // Організатору панель не каже «Ви організатор» неактивною кнопкою (це вже каже штамп на обкладинці), а дає
        // головне, що він тут робить, — поширити. Та сама дія, що була круглою; круглих у нього тепер три.
        action == DetailAction.ORGANIZER -> when {
            state.screen.shareMode == ShareMode.PROMOTE -> PrimaryButton(
                stringResource(R.string.share_promote), { onIntent(DetailIntent.ThreadsPost) }, modifier,
                enabled = state.detailed, icon = PoruchIcons.share
            )
            state.screen.canInvite -> PrimaryButton(
                stringResource(R.string.share_friend), { onIntent(DetailIntent.Share) }, modifier,
                loading = state.inviting, icon = PoruchIcons.personAdd
            )
            else -> PrimaryButton(stringResource(R.string.share), { onIntent(DetailIntent.Share) }, modifier, icon = PoruchIcons.share)
        }
        // Головну дію вже зроблено: стан несе штамп, кнопка лишається тоновою — вийти можна, але це не заклик.
        action in STAMPED -> SecondaryButton(
            stringResource(action.label), { onIntent(DetailIntent.PrimaryAction) }, modifier,
            enabled = action.isEnabled && !state.screen.mutating
        )
        else -> PrimaryButton(
            stringResource(action.label), { onIntent(DetailIntent.PrimaryAction) }, modifier,
            enabled = action.isEnabled && !state.screen.mutating, loading = state.screen.mutating
        )
    }
}

/** Записаний, запит надіслано, у черзі: стан, який каже штамп на панелі. */
private val STAMPED = setOf(DetailAction.LEAVE, DetailAction.REQUESTED, DetailAction.LEAVE_WAITLIST)
/**
 * Штамп участі на панелі дії — перший «вау» потоку (docs/design-wow-1.5.md, «Що перенести», п. 1): після запису падає з
 * розмаху, як касир штампує квиток, з тактильним ударом у мить удару. Б'є лише у відповідь на тап ([pending] з ViewModel):
 * панель, що перемкнулась сама (картка з кешу, потім повна подія), і повторний візит — штамп просто стоїть. Без анімацій —
 * стоїть одразу. Крива та сама, що на сайті: розгін ×2.4 −16°, удар ×0.92 на 45 %, відскок ×1.04, спокій ×1 −4°.
 * [onShown] гасить [pending], щойно панель перемкнулась.
 */
@Composable
private fun JoinStamp(action: DetailAction, payOnline: Boolean, pending: Boolean, onShown: () -> Unit) {
    LaunchedEffect(action) { if (pending && action in STAMPED) onShown() }
    val (word, tone) = when (action) {
        DetailAction.LEAVE -> R.string.going to BadgeTone.Success
        DetailAction.REQUESTED -> (if (payOnline) R.string.stamp_pay else R.string.stamp_request) to BadgeTone.Accent
        DetailAction.LEAVE_WAITLIST -> R.string.stamp_waitlist to BadgeTone.Accent
        else -> return
    }
    SlamStamp(stringResource(word), tone, key = action, play = pending)
}

/** Рядок під датою в нижній панелі: місця й черга для кімнати, ціна або причина відсутності кнопки для афіші. */
@Composable
internal fun stickyHint(state: DetailState): String {
    if (state.screen.cancelled) return stringResource(R.string.cancelled)
    state.screen.listing?.let { listing ->
        return when {
            listing.state == ListingState.POSTPONED -> stringResource(R.string.state_postponed_summary)
            listing.isWithdrawn -> stringResource(R.string.state_unknown)
            state.screen.sessionStarted -> stringResource(R.string.session_started_hint)
            listing.isOpenEntry -> stringResource(R.string.listing_open_entry)
            // Без посилання, але з ціною — вхід платять на місці: ціна каже більше, ніж «ми лише показуємо».
            listing.hasSource || listing.priceMin != null -> listingPrice(listing)
            else -> stringResource(R.string.listing_hint_no_link)
        }
    }
    val room = state.screen.room ?: return ""
    return when {
        state.screen.ended -> stringResource(R.string.event_ended)
        room.awaitingApproval -> stringResource(if (room.payOnline) R.string.pay_waiting_hint else R.string.request_pending_hint)
        // Гостю — що його чекає, не текст перемикача з редактора.
        room.approvalRequired && !room.joined && !state.screen.organizer -> stringResource(R.string.approval_guest_hint)
        room.isFull && !room.joined && !state.screen.organizer -> stringResource(R.string.waitlist_hint)
        else -> stringResource(R.string.seats, room.seatsLeft)
        // Платна — ціна першою, як на квитку в стрічці, і коли платять: «300 ₴, передоплата · Вільних місць: 20».
        // Після кінця вона нічого не каже.
    }.let { hint ->
        val payWhen = payWhenText(room).replaceFirstChar { it.lowercase() }
        room.price?.takeIf { !state.screen.ended }?.let { stringResource(R.string.price_value, EventRules.formatPrice(it)) + ", " + payWhen + " · " + hint } ?: hint
    }
}

internal val DetailAction.label: Int
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
