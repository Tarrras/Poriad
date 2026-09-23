import SwiftUI
import Shared

/// Маршрут чату в стеку: з деталей і з головної він відкривається як повний екран, а не шторка.
struct ChatRoute: Hashable {
    let id: String
}

/// Чат події: повний екран зі своєю шапкою, стрічкою повідомлень по днях і полем унизу.
/// Опитування веде спільний шар; тут відкрити, закрити й передати дії.
struct ChatView: View {
    let eventID: String
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var reporting: ChatMessage?
    @State private var deleting: ChatMessage?
    @State private var blocking: ChatMessage?
    @FocusState private var composing: Bool

    /// Подія з будь-якого списку стану: чат відкривають з деталей, з головної і з пушу.
    private var event: Event? {
        guard let state = model.state else { return nil }
        return ([state.detail.event].compactMap { $0 } + state.library.myEvents + state.map.events).first { $0.id == eventID }
    }
    private var chat: ChatState? { model.state?.chat.flatMap { $0.eventId == eventID ? $0 : nil } }
    private var userId: String? { model.state?.session.userId }
    private var organizer: Bool { event.flatMap { model.state?.organizes(event: $0) } ?? false }
    /// Той самий поріг, що на сервері: тиждень після кінця.
    private var readOnly: Bool {
        guard let event else { return false }
        if event.isCancelled { return true }
        guard let end = parseEventDate(event.endsAt) else { return false }
        return end.addingTimeInterval(7 * 24 * 3600) < Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            if readOnly { closedNote } else { composer }
        }
        .background(Palette.canvas)
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .task { model.app.openChat(eventId: eventID) }
        .onDisappear { model.app.closeChat() }
        .confirmationDialog("Видалити повідомлення?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Видалити", role: .destructive) { if let message = deleting { model.app.deleteMessage(messageId: message.id) } }
        } message: { Text("Його не побачить ніхто з учасників.") }
        .confirmationDialog(
            "Ви більше не побачите подій і повідомлень цієї людини, а вона — ваших. Скасувати можна у профілі.",
            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible
        ) {
            Button("Заблокувати", role: .destructive) { if let message = blocking { model.app.blockUser(userId: message.authorId) } }
        }
        // Текст, що не пішов, повертається в поле, якщо людина ще не почала нового.
        .onChange(of: chat?.failedDraft) { _, failed in
            guard failed != nil, let text = model.app.consumeFailedDraft() else { return }
            if draft.isEmpty { draft = text }
        }
        .sheet(item: $reporting) { message in
            ReportSheet(target: .message) { reason, details in
                model.app.reportMessage(messageId: message.id, reason: reason, details: details)
            }.presentationDetents([.medium, .large])
        }
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
    }

    // ---- Шапка

    private var header: some View {
        HStack(spacing: Space.md) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40).background(Palette.surface, in: Circle())
            }.buttonStyle(PressableStyle()).accessibilityLabel("Назад")
            VStack(alignment: .leading, spacing: 2) {
                Text(event?.title ?? "Чат").font(PoruchFont.title3).foregroundStyle(Palette.ink).lineLimit(1)
                Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary).frame(width: 40, height: 40)
                .background(Palette.surfaceMuted, in: Circle())
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.sm)
        .background(Palette.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private var subtitle: String {
        guard let room = event?.gathering else { return "Чат учасників" }
        // Організатор і підтверджені: саме вони бачать цей екран.
        let people = Int(room.attendeeCount) + 1
        return "\(people) \(plural(people, "учасник", "учасники", "учасників")) · організатор і підтверджені"
    }

    // ---- Стрічка

    @ViewBuilder private var content: some View {
        let chat = self.chat
        if chat?.available == false {
            EmptyState(symbol: "clock", title: "Чат ще недоступний", message: "Сервер ще не оновлено. Спробуйте пізніше.")
                .frame(maxHeight: .infinity)
        } else if chat == nil || (chat!.loading && chat!.messages.isEmpty) {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            feed(chat!.messages)
        }
    }

    private func feed(_ messages: [ChatMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    rules
                    if messages.isEmpty {
                        EmptyState(symbol: "bubble.left.and.bubble.right", title: "Поки тихо",
                                   message: "Напишіть першим: де зустрітись, що взяти, як упізнати одне одного.", compact: true)
                            .padding(.top, Space.section)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        if previous.map({ !sameDay($0.createdAt, message.createdAt) }) ?? true {
                            dayLabel(message.createdAt)
                        }
                        let continued = previous.map { sameThread($0, message) } ?? false
                        bubble(message, continued: continued)
                            .padding(.top, continued ? 3 : Space.md)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Space.page).padding(.bottom, Space.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            // Нове внизу: прокручуємо до нього, коли воно зʼявляється або коли відкрито клавіатуру.
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: composing) { _, focused in
                if focused { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
            }
        }
    }

    /// Правило платформи, один раз угорі стрічки: сторонній чужий текст, а не наш.
    private var rules: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: "hand.raised").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.inkTertiary).padding(.top, 1)
            Text("Повідомлення пишуть учасники. «Поряд» їх не перевіряє. На образи чи спам можна поскаржитись або заблокувати автора, затиснувши повідомлення.")
                .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
        }
        .padding(.vertical, Space.md)
    }

    private func dayLabel(_ iso: String) -> some View {
        Text(dayTitle(iso))
            .font(PoruchFont.overline).kerning(0.6).foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, Space.md).padding(.vertical, 5)
            .background(Palette.surfaceMuted, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.top, Space.lg)
    }

    private func bubble(_ message: ChatMessage, continued: Bool) -> some View {
        let mine = message.authorId == userId
        let name = message.authorName.isEmpty ? "Учасник" : message.authorName
        return HStack(alignment: .bottom, spacing: Space.sm) {
            if mine {
                Spacer(minLength: 56)
            } else if continued {
                Color.clear.frame(width: 28, height: 28)
            } else {
                AvatarStack(attendees: [Attendee(userId: message.authorId, name: name, avatarUrl: message.avatarUrl)], total: 1, size: 28)
            }
            VStack(alignment: .leading, spacing: 3) {
                if !mine && !continued {
                    Text(name).font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                }
                Text(message.body).font(PoruchFont.bodyText).foregroundStyle(mine ? Palette.onBrand : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    // Не вужче за час, щоб він не вилазив за ліве поле короткого «Так».
                    .frame(minWidth: 36, alignment: .leading)
                    .overlay(alignment: .bottomTrailing) {
                        // Час у кутку, під останнім рядком, як у месенджерах.
                        Text(clock(message.createdAt)).font(.caption2)
                            .foregroundStyle(mine ? Palette.onBrand.opacity(0.65) : Palette.inkTertiary)
                            .offset(y: 15)
                    }
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, Space.md).padding(.top, Space.sm).padding(.bottom, Space.sm)
            .background(mine ? Palette.brand : Palette.surface, in: BubbleShape(mine: mine, continued: continued))
            .overlay(BubbleShape(mine: mine, continued: continued).strokeBorder(mine ? .clear : Palette.hairline, lineWidth: 1))
            // Рамка обмежує ширину, а не задає її: своє тулиться до правого краю, чуже — до лівого.
            // Текст переноситься в межах пропозиції; пріоритет — щоб відступ забрав решту, а не половину.
            .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
            .layoutPriority(1)
            .contextMenu {
                Button { UIPasteboard.general.string = message.body } label: { Label("Скопіювати", systemImage: "doc.on.doc") }
                if !mine {
                    Button { reporting = message } label: { Label("Поскаржитись", systemImage: "flag") }
                    Button(role: .destructive) { blocking = message } label: { Label("Заблокувати автора", systemImage: "hand.raised") }
                }
                if organizer || mine {
                    Button(role: .destructive) { deleting = message } label: { Label("Видалити", systemImage: "trash") }
                }
            }
            if !mine { Spacer(minLength: 56) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? "Ви" : name), \(clock(message.createdAt)): \(message.body)")
        // Контекстне меню VoiceOver не відкриває: ті самі дії — через ротор.
        .accessibilityActions {
            Button("Скопіювати") { UIPasteboard.general.string = message.body }
            if !mine {
                Button("Поскаржитись") { reporting = message }
                Button("Заблокувати автора") { blocking = message }
            }
            if organizer || mine { Button("Видалити") { deleting = message } }
        }
    }

    // ---- Низ

    private var closedNote: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "lock").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.inkSecondary)
            Text("Чат закрито: подію скасовано або вона давно минула.")
                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity).padding(Space.lg)
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private var composer: some View {
        let sending = chat?.sending == true
        let canSend = ChatRules.shared.isBody(text: draft) && !sending
        return HStack(alignment: .bottom, spacing: Space.sm) {
            TextField("Написати учасникам…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($composing)
                .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).tint(Palette.ink)
                .padding(.horizontal, Space.lg).padding(.vertical, 11)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(composing ? Palette.ink.opacity(0.35) : Palette.hairline, lineWidth: 1))
            Button {
                let text = draft
                draft = ""
                model.app.sendMessage(text: text)
            } label: {
                Group {
                    if sending { ProgressView().tint(Palette.onBrand) }
                    else { Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)) }
                }
                .foregroundStyle(Palette.onBrand).frame(width: 44, height: 44)
                .background(canSend ? Palette.brand : Palette.inkTertiary, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
            .accessibilityLabel("Надіслати")
        }
        .padding(.horizontal, Space.page).padding(.top, Space.sm).padding(.bottom, Space.sm)
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

/// Бульбашка з «хвостиком»: кут біля співрозмовника гострий, у продовженні серії — усі округлі.
private struct BubbleShape: InsettableShape {
    let mine: Bool
    let continued: Bool
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> BubbleShape { var copy = self; copy.inset += amount; return copy }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let big: CGFloat = 18, small: CGFloat = continued ? 18 : 5
        let radii = RectangleCornerRadii(
            topLeading: big, bottomLeading: mine ? big : small,
            bottomTrailing: mine ? small : big, topTrailing: big
        )
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: r)
    }
}

private func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let mod10 = n % 10, mod100 = n % 100
    if mod10 == 1 && mod100 != 11 { return one }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
    return many
}

// ---- Час

private let clockFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "uk_UA")
    formatter.dateFormat = "HH:mm"
    return formatter
}()

private let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "uk_UA")
    formatter.dateFormat = "d MMMM"
    return formatter
}()

/// Час повідомлення в поясі пристрою: чат читають тут і зараз.
private func clock(_ iso: String) -> String {
    parseEventDate(iso).map { clockFormatter.string(from: $0) } ?? ""
}

private func dayTitle(_ iso: String) -> String {
    guard let date = parseEventDate(iso) else { return "" }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Сьогодні" }
    if calendar.isDateInYesterday(date) { return "Вчора" }
    return dayFormatter.string(from: date)
}

private func sameDay(_ a: String, _ b: String) -> Bool {
    guard let first = parseEventDate(a), let second = parseEventDate(b) else { return false }
    return Calendar.current.isDate(first, inSameDayAs: second)
}

/// Серія: той самий автор і менше ніж пʼять хвилин між повідомленнями.
private func sameThread(_ previous: ChatMessage, _ next: ChatMessage) -> Bool {
    guard previous.authorId == next.authorId,
          let first = parseEventDate(previous.createdAt), let second = parseEventDate(next.createdAt) else { return false }
    return second.timeIntervalSince(first) < 5 * 60
}

/// `sheet(item:)` потребує identity; в Kotlin-класу вона є, лише не оголошена.
extension ChatMessage: @retroactive Identifiable {}
