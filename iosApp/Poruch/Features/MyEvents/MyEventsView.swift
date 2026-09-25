import SwiftUI
import Shared

/// «Мої події» — три розрізи з секціями за часом (docs/my-events.md). Розклад рахує
/// `MyEventsRules` у спільному коді; тут лише малюємо.
struct MyEventsView: View {
    @EnvironmentObject var model: AppModel
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
    private var signedIn: Bool { model.state?.signedIn == true }
    private var board: MyEventsBoard? { model.state?.myEventsBoard(now: nowInstant()) }

    /// Непрочитане за id події, з тієї самої стрічки, що й бейдж вкладки.
    private var unread: [String: Int] {
        Dictionary((model.state?.chatUnread ?? []).map { ($0.eventId, Int($0.unread)) }, uniquingKeysWith: { a, _ in a })
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
        .task { model.app.loadMyEvents() }
        .onChange(of: tab) { _, _ in allPast = false }
        .sheet(isPresented: $creating) { EventEditor(event: nil, app: model.app, home: model.state) }
        .sheet(item: $rating) { route in
            if let event = model.state?.library.myEvents.first(where: { $0.id == route.id }) {
                RateSheet(event: event, score: model.state?.myScore(eventId: event.id)?.intValue)
            }
        }
    }

    // ---- Шапка

    private func header(_ board: MyEventsBoard?) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Мої події").font(PoruchFont.display).displayTracking().foregroundStyle(Palette.ink)
                Text(signedIn ? subtitle(board) : "Увійдіть, щоб бачити свої плани")
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
        case .organizing: "Організовую"
        case .saved: "Збережені"
        default: "Іду"
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
        guard let board else { return "Плани, власні зустрічі й збережене" }
        var parts: [String] = []
        switch tab {
        case .organizing:
            let ahead = Int(board.organizingAhead), requests = Int(board.requests)
            if ahead > 0 { parts.append("\(ahead) \(ukrainianPlural(ahead, "подія", "події", "подій")) попереду") }
            if requests > 0 { parts.append("\(requests) \(ukrainianPlural(requests, "запит", "запити", "запитів")) на участь") }
        case .saved:
            let ahead = Int(board.savedAhead), week = Int(board.savedThisWeek)
            if ahead > 0 { parts.append("\(ahead) \(ukrainianPlural(ahead, "збережена", "збережені", "збережених"))") }
            if week > 0 { parts.append("\(week) цього тижня") }
        default:
            let ahead = Int(board.goingAhead), awaiting = Int(board.awaiting)
            if ahead > 0 { parts.append("\(ahead) \(ukrainianPlural(ahead, "план", "плани", "планів")) попереду") }
            if awaiting > 0 { parts.append("\(awaiting) \(ukrainianPlural(awaiting, "чекає", "чекають", "чекають")) відповіді") }
        }
        return parts.isEmpty ? "Плани, власні зустрічі й збережене" : parts.joined(separator: " · ")
    }

    // ---- Вміст

    @ViewBuilder private func content(_ board: MyEventsBoard?) -> some View {
        if !signedIn {
            EmptyState(
                symbol: "lock", title: "Увійдіть, щоб бачити свої події",
                message: "Зберігайте цікаве, приєднуйтесь і створюйте власні зустрічі."
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
                            LinkRow(symbol: "sparkles", title: "Маєте ідею зустрічі?", subtitle: "Опублікуйте подію за три кроки") { creating = true }
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
            EmptyState(symbol: "sparkles", title: "Ви ще нічого не організували",
                       message: "Зберіть людей на настолки, пробіжку чи кіно — це три кроки.",
                       actionLabel: "Створити подію") { creating = true }
        case .saved:
            EmptyState(symbol: "bookmark", title: "Нічого не збережено",
                       message: "Торкніться закладки на картці події, щоб повернутися до неї пізніше.")
        default:
            EmptyState(symbol: "calendar", title: "Поки жодних планів",
                       message: "Приєднайтесь до зустрічі поруч — вона з’явиться тут із часом і маршрутом.",
                       actionLabel: "Знайти подію поруч") { openMap() }
        }
    }

    @ViewBuilder private func sectionView(_ section: MyEventsSection) -> some View {
        let events = section.events
        switch section.group {
        case .today:
            // Перша сьогоднішня — картка з маршрутом і чатом, решта — рядками.
            overline("Сьогодні")
            if let first = events.first { GoingHero(event: first, unread: unread[first.id] ?? 0, open: open, chat: openChat) }
            rows(Array(events.dropFirst()))
        case .upcoming where tab == .organizing:
            overline("Найближча")
            if let first = events.first {
                OrganizerPanel(event: first, unread: unread[first.id] ?? 0,
                               requests: (model.state?.library.pendingRequests ?? []).filter { $0.eventId == first.id },
                               open: open, chat: openChat)
            }
            if events.count > 1 {
                overline("Далі")
                rows(Array(events.dropFirst()))
            }
        case .past:
            let shown = allPast ? events : Array(events.prefix(Int(MyEventsRules.shared.PAST_PREVIEW)))
            overline("Минулі")
            rows(shown)
            if events.count > shown.count {
                Button("Показати всі · \(events.count)") { allPast = true }
                    .font(PoruchFont.label).foregroundStyle(Palette.ink).frame(minHeight: 44)
            }
        case .thisWeek:
            overline("Цього тижня")
            rows(events)
        case .later:
            overline("Пізніше")
            rows(events)
        default:
            overline("Далі")
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
        let score = model.state?.myScore(eventId: event.id)?.intValue
        let rate = tab == .going && score == nil && RatingRules.shared.canRate(event: event, now: now)
        let bookmark = tab == .saved
        // Запит до не найближчої події інакше видно лише в бейджі чипа.
        let asks = tab == .organizing ? (model.state?.library.pendingRequests ?? []).filter { $0.eventId == event.id }.count : 0
        let status: (String, BadgeTone, String?)? = asks > 0
            ? ("\(asks) \(ukrainianPlural(asks, "запит", "запити", "запитів")) на участь", .accent, "person.badge.plus") : nil
        return HStack(spacing: Space.sm) {
            Button { open(event.id) } label: {
                EventRow(event: event, unread: unread, waitlisted: model.state?.isWaitlisted(id: event.id) == true,
                         note: score.map { "Ваша оцінка ★ \($0)" }, chevron: !rate && !bookmark, status: status)
            }.buttonStyle(PressableStyle(pressedScale: 1))
            if rate {
                Button { rating = EventRoute(id: event.id) } label: {
                    // Без гліфа: з ним кнопка забирала пів рядка, і назва з місцем обрізались.
                    Text("Оцінити").font(PoruchFont.label).foregroundStyle(Palette.onBrand)
                        .padding(.horizontal, Space.md).frame(height: 36).background(Palette.brand, in: Capsule())
                        .frame(minHeight: 44)
                }.buttonStyle(PressableStyle()).fixedSize()
            }
            if bookmark {
                SaveButton(saved: true) { model.app.toggleSaved(id: event.id) }
                    .accessibilityLabel("Прибрати зі збережених")
            }
        }.padding(.horizontal, Space.lg)
    }

    private func open(_ id: String) { model.app.selectEvent(id: id); openEvent(id) }
}

/// Надрядок з відліком: «СЬОГОДНІ · 19:30 · ЧЕРЕЗ 3 ГОД». Після початку `cardOverline` сам каже «триває зараз».
private func countdownOverline(_ event: Event) -> String {
    let base = cardOverline(event)
    guard !event.hasStarted(now: nowInstant()), let start = parseEventDate(event.startsAt) else { return base }
    let minutes = max(Int(start.timeIntervalSinceNow / 60), 1)
    let left = minutes < 60 ? "через \(minutes) хв" : "через \(minutes / 60) год"
    return base + " · " + left.uppercased(with: Locale(identifier: "uk_UA"))
}

/// Кнопка картки: як `SecondaryButton`, але з вужчими полями, щоб у ряд вміщалось три дії з підписом.
private struct CardButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
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
                        Text(event.title).font(PoruchFont.title3).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        if let badge = eventBadge(event), event.gathering?.joined != true {
                            StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2)
                        } else { EventDescriptor(event: event) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(PressableStyle(pressedScale: 1))
            HStack(spacing: Space.sm) {
                CardButton(title: "Маршрут", symbol: "location") { SystemActions.openInMaps(event) }
                // Чат бачать лише підтверджені: із запитом чи в черзі туди не пускає сервер.
                if event.gathering?.joined == true {
                    CardButton(title: unread > 0 ? "Чат · \(unread)" : "Чат", symbol: "bubble.left.and.bubble.right") { chat(event.id) }
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
                        Text(event.title).font(PoruchFont.title3).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        if event.isCancelled { StatusBadge(text: "Скасовано", tone: .danger) } else { EventDescriptor(event: event) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(PressableStyle(pressedScale: 1))
            if let room = event.gathering, !event.isCancelled {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Text("\(room.attendeeCount)").font(PoruchFont.title2).foregroundStyle(Palette.ink).monospacedDigit()
                        Text("з \(room.capacity) місць").font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                    }
                    ProgressView(value: Double(room.attendeeCount), total: Double(max(room.capacity, 1)))
                        .tint(Palette.success)
                }
                .accessibilityElement(children: .combine)
            }
            if let request = requests.first { requestRow(request) }
            HStack(spacing: Space.sm) {
                CardButton(title: "Учасники", symbol: "person.2") { open(event.id) }
                CardButton(title: unread > 0 ? "Чат · \(unread)" : "Чат", symbol: "bubble.left.and.bubble.right") { chat(event.id) }
                ShareLink(item: SystemActions.shareText(for: event)) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 48, height: 48).background(Palette.surfaceMuted, in: Circle())
                }.accessibilityLabel("Поділитись")
            }
        }
        .padding(Space.lg).cardSurface()
    }

    private func requestRow(_ request: JoinRequest) -> some View {
        HStack(spacing: Space.md) {
            Avatar(name: request.name, url: request.avatarUrl, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name.isEmpty ? "Учасник" : request.name).font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(1)
                Text(requests.count > 1 ? "Хоче приєднатись · ще \(requests.count - 1)" : "Хоче приєднатись")
                    .font(PoruchFont.caption).foregroundStyle(Palette.onAccentContainer).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { model.app.declineMember(eventId: event.id, userId: request.userId) } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40).background(Palette.surface, in: Circle())
            }.buttonStyle(PressableStyle()).accessibilityLabel("Відхилити запит: \(request.name)")
            Button("Прийняти") { model.app.approveMember(eventId: event.id, userId: request.userId) }
                .font(PoruchFont.button).foregroundStyle(Palette.onBrand).lineLimit(1).fixedSize()
                .padding(.horizontal, Space.lg).frame(height: 40)
                .background(Palette.brand, in: Capsule())
        }
        .disabled(model.state?.mutating == true)
        .padding(Space.md)
        .background(Palette.accentContainer, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
    }
}

/// Оцінка зі списку: той самий `RateEventCard`, що на деталях, у шторці.
private struct RateSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let event: Event
    let score: Int?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(spacing: Space.md) {
                    EventThumbnail(event: event, maxDimension: 52).frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                        Text(event.title).font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(2)
                    }
                }
                RateEventCard(mine: score.map { EventRating(score: Int32($0), comment: nil, createdAt: "", mine: true) },
                              mutating: model.state?.mutating == true) { score, comment in
                    model.app.rateEvent(id: event.id, score: Int32(score), comment: comment)
                    dismiss()
                }
            }.padding(Space.page)
        }
        .background(Palette.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
