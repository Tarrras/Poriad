import SwiftUI
import Shared

/// Чат події: список знизу вгору, поле внизу. Опитування веде спільний шар; тут відкрити, закрити й передати дії.
struct ChatView: View {
    let event: Event
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    /// Повідомлення, для якого відкрито меню дій.
    @State private var selected: ChatMessage?
    @State private var reporting: ChatMessage?

    private var chat: ChatState? { model.state?.chat.flatMap { $0.eventId == event.id ? $0 : nil } }
    private var userId: String? { model.state?.userId }
    private var organizer: Bool { model.state?.organizes(event: event) == true }
    /// Той самий поріг, що на сервері: тиждень після кінця.
    private var readOnly: Bool {
        if event.isCancelled { return true }
        guard let end = parseEventDate(event.endsAt) else { return false }
        return end.addingTimeInterval(7 * 24 * 3600) < Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: event.title, back: { dismiss() })
            content
            // Правило платформи: сторонній чужий текст, а не наш.
            Text("Повідомлення пишуть учасники. «Поруч» їх не перевіряє; на образи чи спам можна поскаржитись довгим натисканням.")
                .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                .padding(.horizontal, Space.page).padding(.bottom, Space.xs)
            if readOnly {
                Text("Чат закрито: подію скасовано або вона давно минула.")
                    .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.page)
            } else {
                composer
            }
        }
        .background(Palette.canvas)
        .task { model.app.openChat(eventId: event.id) }
        .onDisappear { model.app.closeChat() }
        .confirmationDialog(selected?.body ?? "", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
            if let message = selected {
                if organizer || message.authorId == userId {
                    Button("Видалити повідомлення", role: .destructive) { model.app.deleteMessage(messageId: message.id) }
                }
                if message.authorId != userId {
                    Button("Поскаржитись на повідомлення") { reporting = message }
                }
            }
        }
        .sheet(item: $reporting) { message in
            ReportSheet(target: .message) { reason, details in
                model.app.reportMessage(messageId: message.id, reason: reason, details: details)
            }.presentationDetents([.medium, .large])
        }
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
    }

    @ViewBuilder private var content: some View {
        let chat = self.chat
        if chat?.available == false {
            EmptyState(symbol: "clock", title: "Чат ще недоступний", message: "Сервер ще не оновлено. Спробуйте пізніше.")
                .frame(maxHeight: .infinity)
        } else if chat == nil || (chat!.loading && chat!.messages.isEmpty) {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if chat!.messages.isEmpty {
            EmptyState(symbol: "bubble.left.and.bubble.right", title: "Поки тихо",
                       message: "Напишіть першим: де зустрітись, що взяти, як упізнати одне одного.")
                .frame(maxHeight: .infinity)
        } else {
            messages(chat!.messages)
        }
    }

    private func messages(_ messages: [ChatMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Space.sm) {
                    ForEach(messages, id: \.id) { message in bubble(message).id(message.id) }
                }
                .padding(.horizontal, Space.page).padding(.vertical, Space.md)
            }
            .defaultScrollAnchor(.bottom)
            // Нове внизу: прокручуємо до нього, коли воно зʼявляється.
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let mine = message.authorId == userId
        return HStack(alignment: .bottom, spacing: Space.sm) {
            if mine { Spacer(minLength: Space.section) }
            else { AvatarStack(attendees: [Attendee(userId: message.authorId, name: message.authorName, avatarUrl: message.avatarUrl)], total: 1, size: 28) }
            VStack(alignment: .leading, spacing: 2) {
                if !mine {
                    Text(message.authorName.isEmpty ? "Учасник" : message.authorName)
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                }
                Text(message.body).font(PoruchFont.bodyText).foregroundStyle(mine ? Palette.canvas : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(messageTime(message.createdAt)).font(PoruchFont.caption)
                    .foregroundStyle(mine ? Palette.canvas.opacity(0.7) : Palette.inkTertiary)
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
            .background(mine ? Palette.ink : Palette.surface, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
            // Рамка обмежує ширину, а не задає її: своє тулиться до правого краю рамки, чуже — до лівого.
            .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
            .onLongPressGesture { selected = message }
            if !mine { Spacer(minLength: Space.section) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var composer: some View {
        let sending = chat?.sending == true
        let canSend = ChatRules.shared.isBody(text: draft) && !sending
        return HStack(alignment: .bottom, spacing: Space.sm) {
            TextField("Написати…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).tint(Palette.ink)
                .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            Button {
                let text = draft
                draft = ""
                model.app.sendMessage(text: text)
            } label: {
                Group {
                    if sending { ProgressView().tint(Palette.onBrand) }
                    else { Image(systemName: "paperplane.fill").font(.system(size: 16, weight: .semibold)) }
                }
                .foregroundStyle(Palette.onBrand).frame(width: 44, height: 44)
                .background(canSend ? Palette.brand : Palette.inkTertiary, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Надіслати")
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.sm)
        .background(Palette.surface)
    }
}

private let messageTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "uk_UA")
    formatter.dateFormat = "d MMM, HH:mm"
    return formatter
}()

/// Час повідомлення в поясі пристрою: чат читають тут і зараз.
private func messageTime(_ iso: String) -> String {
    parseEventDate(iso).map { messageTimeFormatter.string(from: $0) } ?? ""
}

/// `sheet(item:)` потребує identity; в Kotlin-класу вона є, лише не оголошена.
extension ChatMessage: Identifiable {}
