import SwiftUI
import Shared

/// «Мої події» — три розрізи з секціями за часом (docs/my-events.md). Розклад рахує
/// `MyEventsRules` у спільному коді; тут лише малюємо.
struct MyEventsView: View, Equatable {
    static func == (lhs: MyEventsView, rhs: MyEventsView) -> Bool { true }
    /// Без підписки на весь `AppModel`: екран перемальовується зі своїм `MyEventsScreenState`.
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    private var view: MyEventsScreenState { model.myEventsScreen.state }
    @Environment(\.openMap) private var openMap
    /// Відкрити деталі. Шлях стосу тримає корінь (`RootView.minePath`).
    var openEvent: (String) -> Void
    var openChat: (String) -> Void
    @State private var tab = MyEventsTab.going
    /// Розріз уже обрано — людиною чи першою дошкою. Далі дошка його не перемикає.
    @State private var tabChosen = false
    /// Відхилений запит кілька секунд чекає: помилковий дотик повертають, а людині ще нічого не пішло.
    @State private var declining: JoinRequest?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var creating = false
    @State private var auth = false
    @State private var allPast = false
    /// Подія, яку оцінюють у шторці. Маршрут, бо `sheet(item:)` потребує identity.
    @State private var rating: EventRoute?

    private static let tabs: [MyEventsTab] = [.going, .organizing, .saved]
    private var signedIn: Bool { view.signedIn }
    private var board: MyEventsBoard? { view.board }

    /// Непрочитане за id події, з тієї самої стрічки, що й бейдж вкладки.
    private var unread: [String: Int] { view.unread.mapValues { $0.intValue } }

    /// Тап по «Створити» звідси: рахуємо, звідки він, і відкриваємо редактор.
    private func startCreating() {
        model.app.createStarted(from: "mine")
        creating = true
    }

    var body: some View {
        let board = board
        VStack(spacing: 0) {
            header(board)
            // Лише на вмісті: `refreshable` на всьому екрані діставався й ряду чипів, і той гойдався вертикально.
            content(board).refreshable { await model.reloadMyEvents() }
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: tab) { _, _ in allPast = false }
        // Гість лише зберігає (docs/guest-saves.md): розрізів у нього нема, рядки — закладки.
        .onChange(of: signedIn, initial: true) { _, signed in if !signed { tab = .saved } }
        // Відкриваємося там, де щось попереду: організатор без власних планів не бачить порожнє «Іду».
        // Рішення — з першою дошкою, де щось попереду: порожній знімок до завантаження інакше закріпив би «Іду».
        .onChange(of: board?.openingTab, initial: true) { _, opening in
            guard !tabChosen, let opening, let board, board.goingAhead + board.organizingAhead + board.savedAhead > 0 else { return }
            tabChosen = true
            tab = opening
        }
        .task(id: declining?.userId) {
            guard declining != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            commitDecline()
        }
        .onDisappear { commitDecline() }
        .sheet(isPresented: $creating) { EventEditor(event: nil, app: model.app, home: model.state) }
        .sheet(isPresented: $auth) { NavigationStack { AuthView() } }
        .sheet(item: $rating) { route in
            if let event = view.myEvents.first(where: { $0.id == route.id }) {
                RateSheet(event: event, mine: view.myScore(id: event.id).map {
                    EventRating(score: $0.int32Value, comment: nil, createdAt: "", mine: true, tags: [])
                })
            }
        }
    }

    // ---- Шапка

    private func header(_ board: MyEventsBoard?) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Copy.my_events).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                // Гостю підзаголовка нема: те саме каже порожній стан нижче.
                if signedIn {
                    Text(subtitle(board)).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.page)
            if signedIn {
                // Поточний розріз — значенням, не через `self`: вигляд `Equatable` без полів, тож замикання `ForEach`,
                // яке читає лише `self.tab`, SwiftUI вважає незмінним і чипи не перемальовує.
                let current = tab
                // Гортаються: на великому шрифті три чипи не вміщались і ставали «Орган…», «Збере…».
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        ForEach(Self.tabs, id: \.self) { entry in
                            Chip(label: title(entry), badge: badge(entry, board), selected: current == entry) {
                                tabChosen = true
                                tab = entry
                            }
                        }
                    }
                }
                .railContentPadding()
            }
        }
        .padding(.top, Space.xl).padding(.bottom, Space.md)
    }

    private func title(_ tab: MyEventsTab) -> String {
        switch tab {
        case .organizing: Copy.organizing
        case .saved: Copy.saved
        default: Copy.tab_going
        }
    }

    private func badge(_ tab: MyEventsTab, _ board: MyEventsBoard?) -> Int {
        guard let board else { return 0 }
        switch tab {
        case .going: return Int(board.goingBadge)
        case .organizing: return Int(board.organizingBadge)
        default: return 0
        }
    }

    /// Лічильники замість опису. Нуль — частину не показуємо; усе нуль — загальний підпис.
    private func subtitle(_ board: MyEventsBoard?) -> String {
        guard let board else { return Copy.my_events_subtitle }
        var parts: [String] = []
        switch tab {
        case .organizing:
            let ahead = Int(board.organizingAhead), requests = Int(board.requests)
            if ahead > 0 { parts.append(Copy.organizing_ahead(ahead)) }
            if requests > 0 { parts.append(Copy.join_requests(requests)) }
        case .saved:
            let ahead = Int(board.savedAhead), week = Int(board.savedThisWeek)
            if ahead > 0 { parts.append(Copy.saved_ahead(ahead)) }
            if week > 0 { parts.append(Copy.saved_this_week("\(week)")) }
        default:
            let ahead = Int(board.goingAhead), awaiting = Int(board.awaiting)
            if ahead > 0 { parts.append(Copy.going_ahead(ahead)) }
            if awaiting > 0 { parts.append(Copy.awaiting_reply(awaiting)) }
        }
        return parts.isEmpty ? Copy.my_events_subtitle : parts.joined(separator: " · ")
    }

    // ---- Вміст

    @ViewBuilder private func content(_ board: MyEventsBoard?) -> some View {
        if !signedIn, (board?.savedAhead ?? 0) == 0 {
            EmptyState(
                glyph: PoruchIcons.ticket, title: Copy.guest_empty,
                message: Copy.guest_saved_hint, actionLabel: Copy.login, action: { auth = true }
            )
            Spacer()
        } else if let board, !board.isEmpty(tab: tab) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if view.offline { OfflineNote() }
                    if !signedIn { guestNote }
                    // Попереду нічого, а минулі є: першою йде дія, а не три сірі минулі.
                    if board.nothingAhead(tab: tab) { aheadCard }
                    ForEach(board.sections(tab: tab), id: \.group) { section in
                        sectionView(section)
                    }
                    // Те саме, що порожній квиток на головній: свою зустріч друкуєш сам.
                    if tab == .organizing, !board.nothingAhead(tab: tab) {
                        CreateEventCard(title: Copy.home_create_title, subtitle: Copy.create_banner_subtitle) { startCreating() }
                    }
                }.padding(.horizontal, Space.page).padding(.vertical, Space.md)
            }
        } else if view.offline && view.myEvents.isEmpty {
            // Плану на телефоні ще нема, а мережі нема: «нічого не заплановано» було б неправдою.
            ScrollView {
                EmptyState(glyph: PoruchIcons.wifiOff, title: Copy.offline_title, message: Copy.offline_mine_hint,
                           animation: "Offline", actionLabel: Copy.try_again) { model.app.loadMyEvents() }
            }
        } else if view.loading && view.myEvents.isEmpty {
            PoruchLoader().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // У стрічці, щоб потяг мав за що зачепитись.
            ScrollView { emptyState }
        }
    }

    /// Порожній квиток з першою дією розрізу, над минулими.
    /// Закладки гостя живуть лише на телефоні: чесно кажемо, навіщо входити.
    private var guestNote: some View {
        Button { auth = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text(Copy.guest_saved_note).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(Copy.login).font(PoruchFont.button).foregroundStyle(Palette.ink)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var aheadCard: some View {
        if tab == .organizing {
            CreateEventCard(title: Copy.home_create_title, subtitle: Copy.home_create_subtitle) { startCreating() }
        } else {
            CreateEventCard(
                title: Copy.going_nothing_ahead_title, subtitle: Copy.going_nothing_ahead_text, glyph: PoruchIcons.map
            ) { openMap() }
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch tab {
        case .organizing:
            EmptyState(glyph: PoruchIcons.sparkle, title: Copy.organizing_empty_title,
                       message: Copy.organizing_empty_text,
                       actionLabel: Copy.create) { startCreating() }
        case .saved:
            EmptyState(glyph: PoruchIcons.bookmark, title: Copy.saved_empty_title,
                       message: Copy.saved_empty_text,
                       actionLabel: Copy.find_nearby) { openMap() }
        default:
            EmptyState(glyph: PoruchIcons.calendar, title: Copy.going_empty_title,
                       message: Copy.going_empty_text,
                       actionLabel: Copy.find_nearby) { openMap() }
        }
    }

    @ViewBuilder private func sectionView(_ section: MyEventsSection) -> some View {
        let events = section.events
        switch section.group {
        case .today:
            // Перша сьогоднішня — картка з маршрутом і чатом, решта — рядками.
            overline(Copy.today)
            if let first = events.first { GoingHero(event: first, unread: unread[first.id] ?? 0, open: open, chat: openChat) }
            rows(Array(events.dropFirst()))
        case .upcoming where tab == .organizing:
            overline(Copy.section_nearest)
            if let first = events.first {
                OrganizerPanel(event: first, unread: unread[first.id] ?? 0,
                               requests: view.requestsFor(id: first.id).filter { !isDeclining($0) },
                               declined: declining.flatMap { $0.eventId == first.id ? $0 : nil },
                               open: open, chat: openChat,
                               decline: startDecline, undo: { declining = nil })
            }
            if events.count > 1 {
                overline(Copy.next)
                rows(Array(events.dropFirst()))
            }
        case .past:
            let shown = allPast ? events : Array(events.prefix(Int(MyEventsRules.shared.PAST_PREVIEW)))
            overline(Copy.section_past)
            rows(shown)
            if events.count > shown.count {
                Button(Copy.show_all_past("\(events.count)")) { allPast = true }
                    .font(PoruchFont.label).foregroundStyle(Palette.ink).frame(minHeight: 44)
            }
        case .thisWeek:
            overline(Copy.section_this_week)
            rows(events)
        case .later:
            overline(Copy.companion_later)
            rows(events)
        default:
            overline(Copy.next)
            rows(events)
        }
    }

    private func overline(_ text: String) -> some View {
        Text(text.uppercased(with: Locale(identifier: "uk_UA"))).font(PoruchFont.overline).kerning(1.0)
            .foregroundStyle(Palette.inkTertiary).padding(.bottom, -Space.md)
    }

    @ViewBuilder private func rows(_ events: [Event]) -> some View {
        if !events.isEmpty {
            let unread = unread
            GroupedRows {
                ForEach(Array(events.enumerated()), id: \.element.id) { position, event in
                    row(event, unread: unread[event.id] ?? 0)
                    if position < events.count - 1 {
                        Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 60 + Space.md)
                    }
                }
            }
        }
    }

    /// Рядок і, праворуч, його власна дія: «Оцінити» для минулої, закладка — у збережених.
    private func row(_ event: Event, unread: Int) -> some View {
        let now = nowInstant()
        let score = view.myScore(id: event.id)?.intValue
        let rate = tab == .going && score == nil && RatingRules.shared.canRate(event: event, now: now)
        let bookmark = tab == .saved
        // Запит до не найближчої події інакше видно лише в бейджі чипа.
        let asks = tab == .organizing ? view.requestsFor(id: event.id).count : 0
        let status: (String, BadgeTone, PoruchGlyph?)? = asks > 0
            ? (Copy.join_requests(asks), .accent, PoruchIcons.personAdd) : nil
        // На великому шрифті «Оцінити» стає під рядок: поруч вона лишала назві «push j…».
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: Space.sm))
        return layout {
            Button { open(event.id) } label: {
                EventRow(event: event, unread: unread, waitlisted: view.isWaitlisted(id: event.id),
                         note: score.map { Copy.my_score("\($0)") }, chevron: !rate && !bookmark, status: status)
            }.buttonStyle(PressableStyle(pressedScale: 1))
            if rate {
                Button { rating = EventRoute(id: event.id) } label: {
                    // Тонова, а не чорнильна: три головні кнопки підряд сперечались за увагу. Без гліфа — інакше
                    // кнопка забирала пів рядка.
                    Text(Copy.rate_action).font(PoruchFont.label).foregroundStyle(Palette.ink)
                        .padding(.horizontal, Space.md).frame(minHeight: 36).background(Palette.brandContainer, in: buttonShape)
                        .frame(minHeight: 44)
                }
                .buttonStyle(PressableStyle()).fixedSize()
                .padding(.bottom, typeSize.isAccessibilitySize ? Space.md : 0)
            }
            if bookmark {
                SaveButton(saved: true) { model.app.toggleSaved(id: event.id) }
                    .accessibilityLabel(Copy.unsave)
            }
        }.padding(.horizontal, Space.lg)
    }

    private func open(_ id: String) { model.app.selectEvent(id: id); openEvent(id) }

    private func isDeclining(_ request: JoinRequest) -> Bool {
        declining.map { $0.eventId == request.eventId && $0.userId == request.userId } ?? false
    }

    /// Попередній відхилений іде одразу: «Повернути» — лише для останнього.
    private func startDecline(_ request: JoinRequest) {
        commitDecline()
        declining = request
    }

    private func commitDecline() {
        guard let request = declining else { return }
        declining = nil
        model.app.declineMember(eventId: request.eventId, userId: request.userId)
    }
}

/// Надрядок з відліком: «СЬОГОДНІ · 19:30 · ЧЕРЕЗ 3 ГОД». Після початку `cardOverline` сам каже «триває зараз».
func countdownOverline(_ event: Event) -> String {
    let base = cardOverline(event)
    guard !event.hasStarted(now: nowInstant()), let start = parseEventDate(event.startsAt) else { return base }
    let minutes = max(Int(start.timeIntervalSinceNow / 60), 1)
    // Далі за добу дата в надрядку каже більше, ніж «через 644 год».
    guard minutes < Int(MyEventsRules.shared.COUNTDOWN_MAX_MINUTES) else { return base }
    let left = minutes < 60 ? Copy.countdown_minutes("\(minutes)") : Copy.countdown_hours("\(minutes / 60)")
    return base + " · " + left.uppercased(with: Locale(identifier: "uk_UA"))
}

/// Відлік над назвою квитка панелі: «ТРИВАЄ ЗАРАЗ» чи «ЧЕРЕЗ 3 ГОД» у межах доби. День і час уже друкує корінець,
/// тож надрядок «ЧТ, 12 ЛИСТ. · 19:30» лише повторював би його.
private func panelCountdown(_ event: Event) -> String? {
    let ukrainian = Locale(identifier: "uk_UA")
    if event.isUnderway(now: nowInstant()) { return Copy.underway_now.uppercased(with: ukrainian) }
    guard let start = parseEventDate(event.startsAt), start > Date() else { return nil }
    let minutes = max(Int(start.timeIntervalSinceNow / 60), 1)
    guard minutes < Int(MyEventsRules.shared.COUNTDOWN_MAX_MINUTES) else { return nil }
    return (minutes < 60 ? Copy.countdown_minutes("\(minutes)") : Copy.countdown_hours("\(minutes / 60)")).uppercased(with: ukrainian)
}

/// Кнопка картки: як `SecondaryButton`, але з вужчими полями, щоб у ряд вміщалось три дії з підписом.
private struct CardButton: View {
    let title: String
    let glyph: PoruchGlyph
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                PoruchIcon(glyph: glyph, size: 18)
                Text(title).font(PoruchFont.button).lineLimit(2)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm).frame(minHeight: 48).frame(maxWidth: .infinity)
            .background(Palette.brandContainer, in: buttonShape)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Голова панелей «Сьогодні» й «Найближча»: квиток із корінцем, як у стрічці, — відлік, назва й опис на поверхні,
/// жанр, час і місця «0/2» на корінці. Мініатюра 60 лише важчала сірим градієнтом і випадала зі світу квитків.
private struct PanelTicket<Status: View>: View {
    let event: Event
    let open: (String) -> Void
    @ViewBuilder let status: () -> Status
    var body: some View {
        Button { open(event.id) } label: {
            Ticket(stubColor: ticketStub(event)) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if let countdown = panelCountdown(event) {
                        Text(countdown).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.accentText)
                    }
                    Text(event.displayTitle).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(3)
                    status()
                }
                .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
            } stub: {
                StubTime(event: event)
            }
        }
        .buttonStyle(PressableStyle())
        .ticketAccessibility(event, state: event.isCancelled ? Copy.cancelled_short : nil)
    }
}

/// Дії панелі в ряд; на великому шрифті — одна під одною, бо «Учасники» в третину ширини ставали «Уча…».
private struct PanelActions<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: () -> Content
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.sm)) : AnyLayout(HStackLayout(spacing: Space.sm))
        layout { content() }
    }
}

/// Сьогоднішній план: квиток з відліком і дві дії, по які сюди приходять перед виходом.
private struct GoingHero: View {
    let event: Event
    let unread: Int
    let open: (String) -> Void
    let chat: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            PanelTicket(event: event, open: open) {
                if event.isCancelled {
                    TicketStamp(text: Copy.cancelled_short, tone: .danger)
                } else if let badge = eventBadge(event), event.gathering?.joined != true {
                    StatusBadge(text: badge.0, tone: badge.1, glyph: badge.2)
                } else { EventDescriptor(event: event) }
            }
            PanelActions {
                CardButton(title: Copy.rate_tag_route, glyph: PoruchIcons.myLocation) { SystemActions.openInMaps(event) }
                // Чат бачать лише підтверджені: із запитом чи в черзі туди не пускає сервер.
                if event.gathering?.joined == true {
                    CardButton(title: unread > 0 ? Copy.chat_short_unread("\(unread)") : Copy.chat_short, glyph: PoruchIcons.chat) { chat(event.id) }
                }
            }
        }
    }
}

/// Найближча своя подія: квиток (місця — на корінці), перший запит із відповіддю на місці й дії організатора.
private struct OrganizerPanel: View {
    @EnvironmentObject var model: AppModel
    let event: Event
    let unread: Int
    let requests: [JoinRequest]
    /// Щойно відхилений запит: кілька секунд на його місці «Повернути».
    let declined: JoinRequest?
    let open: (String) -> Void
    let chat: (String) -> Void
    let decline: (JoinRequest) -> Void
    let undo: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            PanelTicket(event: event, open: open) {
                if event.isCancelled { TicketStamp(text: Copy.cancelled_short, tone: .danger) } else { EventDescriptor(event: event) }
            }
            if let declined { declinedRow(declined) }
            else if let request = requests.first { requestRow(request) }
            PanelActions {
                CardButton(title: Copy.participants, glyph: PoruchIcons.social) { open(event.id) }
                CardButton(title: unread > 0 ? Copy.chat_short_unread("\(unread)") : Copy.chat_short, glyph: PoruchIcons.chat) { chat(event.id) }
                ShareLink(item: SystemActions.shareText(for: event)) {
                    PoruchIcon(glyph: PoruchIcons.share, size: 18).foregroundStyle(Palette.ink)
                        .frame(width: 48, height: 48).background(Palette.brandContainer, in: Circle())
                }.accessibilityLabel(Copy.share)
                .simultaneousGesture(TapGesture().onEnded { model.app.eventShared() })
            }
        }
    }

    private func requestRow(_ request: JoinRequest) -> some View {
        HStack(spacing: Space.md) {
            Avatar(name: request.name, url: request.avatarUrl, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name.isEmpty ? Copy.chat_member : request.name).font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(1)
                Text(requests.count > 1 ? Copy.wants_to_join_more("\(requests.count - 1)") : Copy.wants_to_join)
                    .font(PoruchFont.caption).foregroundStyle(Palette.onAccentContainer).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { decline(request) } label: {
                PoruchIcon(glyph: PoruchIcons.close, size: 16).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40).background(Palette.surface, in: Circle()).tapTarget()
            }.buttonStyle(PressableStyle()).accessibilityLabel(Copy.decline_request_a11y("\(request.name)"))
            // Поля й тло — у мітці: поза міткою SwiftUI зараховує до дотику лише саме слово.
            Button { model.app.approveMember(eventId: event.id, userId: request.userId) } label: {
                Text(Copy.approve).font(PoruchFont.button).foregroundStyle(Palette.onBrand).lineLimit(1).fixedSize()
                    .padding(.horizontal, Space.lg).frame(height: 40)
                    .background(Palette.brand, in: buttonShape)
                    .tapTarget()
            }.buttonStyle(PressableStyle())
        }
        .disabled(model.state?.mutating == true)
        .padding(Space.md)
        .background(Palette.accentContainer, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
    }

    /// Відмова ще не пішла: тиха смужка з «Повернути» замість запиту. «Повернути» — зліва: справа в цьому рядку стоїть
    /// «Прийняти» наступного запиту, і запізнілий дотик після відліку приймав чужу людину.
    private func declinedRow(_ request: JoinRequest) -> some View {
        HStack(spacing: Space.md) {
            Button(Copy.undo, action: undo)
                .font(PoruchFont.button).foregroundStyle(Palette.ink).tapTarget()
            Text(Copy.request_declined(request.name.isEmpty ? Copy.chat_member : request.name))
                .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md).frame(minHeight: 52)
        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Стан «Моїх подій» складає спільний `MyEventsPresenter` — та сама згортка, що й на Android. Тут лише
/// спостережувана обгортка: `@Observable` стежить за `state` поштучно.
@MainActor @Observable final class MyEventsScreenModel {
    private(set) var state = MyEventsScreenState.companion.Empty
    private let presenter: MyEventsPresenter
    private var subscription: Subscription?

    init(app: PoruchApp) {
        presenter = MyEventsPresenter(app: app)
        subscription = presenter.observe { [weak self] state in self?.state = state }
    }
    // Без `deinit`: модель живе стільки, скільки `AppModel`.
}
