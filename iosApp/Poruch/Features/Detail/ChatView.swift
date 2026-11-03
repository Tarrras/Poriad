import SwiftUI
import PhotosUI
import Shared

/// Маршрут чату в стеку: з деталей і з головної він відкривається як повний екран, а не шторка.
struct ChatRoute: Hashable {
    let id: String
    /// «Запитати організатора»: розмова того, хто питає (його id). Nil — загальний чат події.
    var thread: String? = nil
}

/// Чат події: повний екран зі своєю шапкою, стрічкою повідомлень по днях і полем унизу.
/// Опитування веде спільний шар; тут відкрити, закрити й передати дії.
struct ChatView: View {
    let eventID: String
    /// Розмова з організатором: хто питає. Nil — загальний чат.
    var thread: String? = nil
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var reporting: ChatMessage?
    /// Картка автора відкрита з чату. Див. `personSheet`.
    @State private var showingPerson = false
    @State private var deleting: ChatMessage?
    @State private var blocking: ChatMessage?
    @FocusState private var composing: Bool
    /// Скріншот оплати з пікера (docs/organizer-events.md): лише в моїй розмові події з оплатою онлайн.
    @State private var proofItem: PhotosPickerItem?
    @State private var preparingProof = false
    @State private var proofProblem: String?
    /// Скріншот на весь екран: звірити суму й імʼя з банком.
    @State private var viewing: ProofImage?

    /// Подія з будь-якого списку стану: чат відкривають з деталей, з головної і з пушу.
    private var event: Event? {
        guard let state = model.state else { return nil }
        // Без конкатенації: два Kotlin-списки через міст на кожне читання (а читають з шапки, підзаголовка й кожної бульбашки).
        if let event = state.detail.event, event.id == eventID { return event }
        return state.library.myEvents.first { $0.id == eventID } ?? state.map.events.first { $0.id == eventID }
    }
    private var chat: ChatState? { model.state?.chat.flatMap { $0.eventId == eventID && $0.thread == thread ? $0 : nil } }
    private var userId: String? { model.state?.session.userId }
    private var canSendProof: Bool { model.state?.canSendProof() == true }
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
        .task {
            if let thread { model.app.openQuestion(eventId: eventID, askerId: thread) } else { model.app.openChat(eventId: eventID) }
        }
        .onDisappear { model.app.closeChat(eventId: eventID); model.app.closePerson() }
        .personSheet(model, isPresented: $showingPerson)
        .confirmationDialog(Copy.chat_delete_title, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(Copy.delete_account_confirm, role: .destructive) { if let message = deleting { model.app.deleteMessage(messageId: message.id) } }
        } message: { Text(Copy.chat_delete_body) }
        .confirmationDialog(
            Copy.block_user_body_chat,
            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible
        ) {
            Button(Copy.block_confirm, role: .destructive) { if let message = blocking { model.app.blockUser(userId: message.authorId) } }
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
        // Скріншот: JPEG без метаданих, довша сторона до PROOF_SIDE; текст поля — підписом.
        .onChange(of: proofItem) { _, item in
            guard let item else { return }
            preparingProof = true
            proofProblem = nil
            Task {
                switch await pickedJPEG(item, maxPixel: CGFloat(ChatRules.shared.PROOF_SIDE)) {
                case .success(let jpeg):
                    let text = draft
                    draft = ""
                    model.app.sendProof(jpeg: jpeg, text: text)
                case .failure(let problem):
                    proofProblem = problem.message
                }
                preparingProof = false
                proofItem = nil
            }
        }
        .fullScreenCover(item: $viewing) { proof in ProofViewer(image: proof.image) }
    }

    // ---- Шапка

    private var header: some View {
        HStack(spacing: Space.md) {
            Button { dismiss() } label: {
                PoruchIcon(glyph: PoruchIcons.chevronLeft, size: 19).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40).background(Palette.surface, in: Circle()).tapTarget()
            }.buttonStyle(PressableStyle()).accessibilityLabel(Copy.back)
            VStack(alignment: .leading, spacing: 2) {
                Text(event?.displayTitle ?? Copy.chat_short).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink).lineLimit(1)
                Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            PoruchIcon(glyph: PoruchIcons.chat, size: 18)
                .foregroundStyle(Palette.inkSecondary).frame(width: 40, height: 40)
                .background(Palette.surfaceMuted, in: Circle())
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.sm)
        .background(Palette.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private var subtitle: String {
        if let thread {
            // Організатор бачить, хто питає; той, хто питає, — що розмова лише на двох.
            guard organizer else { return Copy.question_subtitle }
            // З розмови, розмов, заявок чи учасників: організатор міг написати першим.
            return Copy.question_from(model.state?.askerName(eventId: eventID, thread: thread) ?? Copy.chat_member)
        }
        guard let room = event?.gathering else { return Copy.contact_label }
        // Організатор і підтверджені: саме вони бачать цей екран.
        let people = Int(room.attendeeCount) + 1
        return Copy.chat_members(people) + " · " + Copy.chat_members_hint
    }

    // ---- Стрічка

    @ViewBuilder private var content: some View {
        let chat = self.chat
        if chat?.available == false {
            EmptyState(glyph: PoruchIcons.clock, title: Copy.chat_unavailable_title, message: Copy.chat_unavailable_hint)
                .frame(maxHeight: .infinity)
        } else if let chat, chat.offline && chat.messages.isEmpty {
            // Без мережі — не вічний спінер: опитування саме підхопить її, щойно вона повернеться.
            OfflineState(message: Copy.offline_chat_hint).frame(maxHeight: .infinity)
        } else if chat == nil || (chat!.loading && chat!.messages.isEmpty) {
            PoruchLoader().frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        EmptyState(glyph: PoruchIcons.chat, title: thread == nil ? Copy.chat_empty_title : Copy.question_empty_title,
                                   message: thread == nil ? Copy.chat_empty_hint : Copy.question_empty_hint, compact: true)
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
            PoruchIcon(glyph: PoruchIcons.hand, size: 16).foregroundStyle(Palette.inkTertiary).padding(.top, 1)
            Text(Copy.chat_disclaimer)
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
        let name = message.authorName.isEmpty ? Copy.chat_member : message.authorName
        return HStack(alignment: .bottom, spacing: Space.sm) {
            if mine {
                Spacer(minLength: 56)
            } else if continued {
                Color.clear.frame(width: 28, height: 28)
            } else {
                Button { showingPerson = true; model.app.openPerson(userId: message.authorId) } label: {
                    Avatar(name: name, url: message.avatarUrl, size: 28)
                }.buttonStyle(.plain).accessibilityLabel(Copy.person_open("\(name)"))
            }
            VStack(alignment: .leading, spacing: 3) {
                if !mine && !continued {
                    Text(name).font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                }
                if let path = message.image {
                    ProofThumb(bytes: chat?.proofs[path], missing: chat?.missingProofs.contains(path) == true, mine: mine) { image in
                        viewing = ProofImage(id: path, image: image)
                    }
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
                // Реквізити від іншої сторони: «Поряд» за оплату не відповідає, скарга — тут же.
                if message.paymentDetails && !mine {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Copy.payment_warning).font(PoruchFont.caption).foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { reporting = message } label: { Text(Copy.chat_report).font(PoruchFont.caption.weight(.semibold)) }
                            .foregroundStyle(Palette.danger)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, Space.md).padding(.top, Space.sm).padding(.bottom, Space.sm)
            .background(mine ? Palette.brand : Palette.surface, in: BubbleShape(mine: mine, continued: continued))
            .overlay(BubbleShape(mine: mine, continued: continued).strokeBorder(mine ? .clear : Palette.hairline, lineWidth: 1))
            // Рамка обмежує ширину, а не задає її: своє тулиться до правого краю, чуже — до лівого.
            // Текст переноситься в межах пропозиції; пріоритет — щоб відступ забрав решту, а не половину.
            .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
            .layoutPriority(1)
            .contextMenu {
                Button { UIPasteboard.general.string = message.body } label: { Label(Copy.chat_copy, systemImage: "doc.on.doc") }
                if !mine {
                    Button { reporting = message } label: { Label(Copy.chat_report, systemImage: "flag") }
                    Button(role: .destructive) { blocking = message } label: { Label(Copy.chat_block, systemImage: "hand.raised") }
                }
                if organizer || mine {
                    Button(role: .destructive) { deleting = message } label: { Label(Copy.delete_account_confirm, systemImage: "trash") }
                }
            }
            if !mine { Spacer(minLength: 56) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? Copy.you : name), \(clock(message.createdAt)): \(message.body)")
        // Контекстне меню VoiceOver не відкриває: ті самі дії — через ротор.
        .accessibilityActions {
            Button(Copy.chat_copy) { UIPasteboard.general.string = message.body }
            if !mine {
                Button(Copy.chat_report) { reporting = message }
                Button(Copy.chat_block) { blocking = message }
            }
            if organizer || mine { Button(Copy.delete_account_confirm) { deleting = message } }
        }
    }

    // ---- Низ

    private var closedNote: some View {
        HStack(spacing: Space.sm) {
            PoruchIcon(glyph: PoruchIcons.lock, size: 17).foregroundStyle(Palette.inkSecondary)
            Text(Copy.chat_read_only)
                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity).padding(Space.lg)
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private var composer: some View {
        let sending = chat?.sending == true
        let canSend = ChatRules.shared.isBody(text: draft) && !sending
        return VStack(alignment: .leading, spacing: Space.sm) {
            if canSendProof {
                Text(proofProblem ?? Copy.proof_hint).font(PoruchFont.caption)
                    .foregroundStyle(proofProblem == nil ? Palette.inkSecondary : Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: Space.sm) {
                if canSendProof {
                    PhotosPicker(selection: $proofItem, matching: .images) {
                        Group {
                            if preparingProof { ProgressView().tint(Palette.ink) }
                            else { PoruchIcon(glyph: PoruchIcons.plus, size: 20) }
                        }
                        .foregroundStyle(Palette.ink).frame(width: 44, height: 44)
                        .background(Palette.surfaceMuted, in: Circle())
                    }
                    .disabled(sending || preparingProof)
                    .accessibilityLabel(Copy.proof_attach)
                }
                TextField(thread == nil ? Copy.chat_placeholder : organizer ? Copy.question_reply_placeholder : Copy.question_placeholder,
                          text: $draft, axis: .vertical)
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
                        else { PoruchIcon(glyph: PoruchIcons.arrowUp, size: 20) }
                    }
                    .foregroundStyle(Palette.onBrand).frame(width: 44, height: 44)
                    .background(canSend ? Palette.brand : Palette.inkTertiary, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .disabled(!canSend)
                .motion(value: canSend)
                .accessibilityLabel(Copy.rate_send)
            }
        }
        .padding(.horizontal, Space.page).padding(.top, Space.sm).padding(.bottom, Space.sm)
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

/// Скріншот оплати, відкритий на весь екран.
struct ProofImage: Identifiable {
    let id: String
    let image: UIImage
}

/// Скріншот у бульбашці: байти зі спільного шару (`ChatState.proofs`) → зменшене зображення поза головним потоком.
/// Поки вантажиться — тонова плашка, недоступний — підпис. Тап — на весь екран.
private struct ProofThumb: View {
    let bytes: KotlinByteArray?
    let missing: Bool
    let mine: Bool
    let open: (UIImage) -> Void
    @State private var image: UIImage?
    @State private var broken = false

    var body: some View {
        Group {
            if let image {
                Button { open(image) } label: {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(maxWidth: 240, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Copy.proof_open)
            } else if missing || broken {
                Text(Copy.proof_unavailable).font(PoruchFont.caption)
                    .foregroundStyle(mine ? Palette.onBrand.opacity(0.75) : Palette.inkSecondary)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceMuted)
                    .frame(width: 160, height: 120)
                    .overlay { ProgressView() }
            }
        }
        .task(id: bytes != nil) {
            guard image == nil, let bytes else { return }
            let data = Bytes_iosKt.dataOf(bytes: bytes)
            let decoded = await Task.detached(priority: .userInitiated) { ThumbnailCache.downsample(data, to: 1600) }.value
            if let decoded { image = decoded } else { broken = true }
        }
    }
}

/// Скріншот на весь екран: зображення цілком на чорному, «Закрити» вгорі.
private struct ProofViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Copy.proof_open)
            Button { dismiss() } label: {
                PoruchIcon(glyph: PoruchIcons.close, size: 18).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.2), in: Circle())
            }
            .padding(Space.lg)
            .accessibilityLabel(Copy.close)
        }
        .onTapGesture { dismiss() }
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
    if calendar.isDateInToday(date) { return Copy.today }
    if calendar.isDateInYesterday(date) { return Copy.chat_yesterday }
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
