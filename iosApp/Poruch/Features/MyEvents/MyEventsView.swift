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
    @State private var creating = false
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
        .sheet(isPresented: $creating) { EventEditor(event: nil, app: model.app, home: model.state) }
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
                Text(Copy.my_events).font(PoruchFont.serifDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                Text(signedIn ? subtitle(board) : Copy.guest_empty)
                    .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.page)
            if signedIn {
                HStack(spacing: Space.sm) {
                    ForEach(Self.tabs, id: \.self) { entry in
                        Chip(label: title(entry), badge: badge(entry, board), selected: tab == entry) { tab = entry }
                    }
                }.padding(.horizontal, Space.page)
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
        if !signedIn {
            EmptyState(
                glyph: PoruchIcons.lock, title: Copy.guest_empty,
                message: Copy.guest_description
            )
            Spacer()
        } else if let board, !board.isEmpty(tab: tab) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    ForEach(board.sections(tab: tab), id: \.group) { section in
                        sectionView(section)
                    }
                    if tab == .organizing {
                        GroupedRows {
                            LinkRow(glyph: PoruchIcons.sparkle, title: Copy.create_banner_title, subtitle: Copy.create_banner_subtitle) { startCreating() }
                        }
                    }
                }.padding(.horizontal, Space.page).padding(.vertical, Space.md)
            }
        } else {
            // У стрічці, щоб потяг мав за що зачепитись.
            ScrollView { emptyState }
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
                       message: Copy.saved_empty_text)
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
                               requests: view.requestsFor(id: first.id),
                               open: open, chat: openChat)
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
        return HStack(spacing: Space.sm) {
            Button { open(event.id) } label: {
                EventRow(event: event, unread: unread, waitlisted: view.isWaitlisted(id: event.id),
                         note: score.map { Copy.my_score("\($0)") }, chevron: !rate && !bookmark, status: status)
            }.buttonStyle(PressableStyle(pressedScale: 1))
            if rate {
                Button { rating = EventRoute(id: event.id) } label: {
                    // Без гліфа: з ним кнопка забирала пів рядка, і назва з місцем обрізались.
                    Text(Copy.rate_action).font(PoruchFont.label).foregroundStyle(Palette.onBrand)
                        .padding(.horizontal, Space.md).frame(height: 36).background(Palette.brand, in: Capsule())
                        .frame(minHeight: 44)
                }.buttonStyle(PressableStyle()).fixedSize()
            }
            if bookmark {
                SaveButton(saved: true) { model.app.toggleSaved(id: event.id) }
                    .accessibilityLabel(Copy.unsave)
            }
        }.padding(.horizontal, Space.lg)
    }

    private func open(_ id: String) { model.app.selectEvent(id: id); openEvent(id) }
}

/// Надрядок з відліком: «СЬОГОДНІ · 19:30 · ЧЕРЕЗ 3 ГОД». Після початку `cardOverline` сам каже «триває зараз».
func countdownOverline(_ event: Event) -> String {
    let base = cardOverline(event)
    guard !event.hasStarted(now: nowInstant()), let start = parseEventDate(event.startsAt) else { return base }
    let minutes = max(Int(start.timeIntervalSinceNow / 60), 1)
    let left = minutes < 60 ? Copy.countdown_minutes("\(minutes)") : Copy.countdown_hours("\(minutes / 60)")
    return base + " · " + left.uppercased(with: Locale(identifier: "uk_UA"))
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
                Text(title).font(PoruchFont.button).lineLimit(1)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Space.md).frame(height: 48).frame(maxWidth: .infinity)
            .background(Palette.brandContainer, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Сьогоднішній план: більша плитка, відлік і дві дії, по які сюди приходять перед виходом.
private struct GoingHero: View {
    let event: Event
    let unread: Int
    let open: (String) -> Void
    let chat: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Button { open(event.id) } label: {
                HStack(spacing: Space.md) {
                    // Розмір рядка: картку вирізняють відлік і дії, а велика плитка лише важчала сірим градієнтом.
                    EventThumbnail(event: event, maxDimension: 60)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(countdownOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.accent)
                        Text(event.displayTitle).font(PoruchFont.serifTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        if let badge = eventBadge(event), event.gathering?.joined != true {
                            StatusBadge(text: badge.0, tone: badge.1, glyph: badge.2)
                        } else { EventDescriptor(event: event) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(PressableStyle(pressedScale: 1))
            HStack(spacing: Space.sm) {
                CardButton(title: Copy.rate_tag_route, glyph: PoruchIcons.myLocation) { SystemActions.openInMaps(event) }
                // Чат бачать лише підтверджені: із запитом чи в черзі туди не пускає сервер.
                if event.gathering?.joined == true {
                    CardButton(title: unread > 0 ? Copy.chat_short_unread("\(unread)") : Copy.chat_short, glyph: PoruchIcons.chat) { chat(event.id) }
                }
            }
        }
        .padding(Space.lg).cardSurface()
        .opacity(event.isCancelled ? 0.6 : 1)
    }
}

/// Найближча своя подія: заповненість, перший запит із відповіддю на місці й дії організатора.
private struct OrganizerPanel: View {
    @EnvironmentObject var model: AppModel
    let event: Event
    let unread: Int
    let requests: [JoinRequest]
    let open: (String) -> Void
    let chat: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Button { open(event.id) } label: {
                HStack(spacing: Space.md) {
                    // Розмір рядка: картку вирізняють відлік і дії, а велика плитка лише важчала сірим градієнтом.
                    EventThumbnail(event: event, maxDimension: 60)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(countdownOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.accent)
                        Text(event.displayTitle).font(PoruchFont.serifTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        if event.isCancelled { StatusBadge(text: Copy.cancelled_short, tone: .danger) } else { EventDescriptor(event: event) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(PressableStyle(pressedScale: 1))
            if let room = event.gathering, !event.isCancelled {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Text("\(room.attendeeCount)").font(PoruchFont.title2).foregroundStyle(Palette.ink).monospacedDigit()
                        Text(Copy.seats_of("\(room.capacity)")).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                    }
                    ProgressView(value: Double(room.attendeeCount), total: Double(max(room.capacity, 1)))
                        .tint(Palette.success)
                }
                .accessibilityElement(children: .combine)
            }
            if let request = requests.first { requestRow(request) }
            HStack(spacing: Space.sm) {
                CardButton(title: Copy.participants, glyph: PoruchIcons.social) { open(event.id) }
                CardButton(title: unread > 0 ? Copy.chat_short_unread("\(unread)") : Copy.chat_short, glyph: PoruchIcons.chat) { chat(event.id) }
                ShareLink(item: SystemActions.shareText(for: event)) {
                    PoruchIcon(glyph: PoruchIcons.share, size: 18).foregroundStyle(Palette.ink)
                        .frame(width: 48, height: 48).background(Palette.surfaceMuted, in: Circle())
                }.accessibilityLabel(Copy.share)
                .simultaneousGesture(TapGesture().onEnded { model.app.eventShared() })
            }
        }
        .padding(Space.lg).cardSurface()
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
            Button { model.app.declineMember(eventId: event.id, userId: request.userId) } label: {
                PoruchIcon(glyph: PoruchIcons.close, size: 16).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40).background(Palette.surface, in: Circle())
            }.buttonStyle(PressableStyle()).accessibilityLabel(Copy.decline_request_a11y("\(request.name)"))
            Button(Copy.approve) { model.app.approveMember(eventId: event.id, userId: request.userId) }
                .font(PoruchFont.button).foregroundStyle(Palette.onBrand).lineLimit(1).fixedSize()
                .padding(.horizontal, Space.lg).frame(height: 40)
                .background(Palette.brand, in: Capsule())
        }
        .disabled(model.state?.mutating == true)
        .padding(Space.md)
        .background(Palette.accentContainer, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
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
