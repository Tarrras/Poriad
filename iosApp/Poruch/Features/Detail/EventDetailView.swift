import SwiftUI
import PhotosUI
import EventKit
import Shared

/// Маршрут деталей події: для шляху стосу й для шторки.
struct EventRoute: Hashable, Identifiable {
    let id: String
}

struct EventDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var actions: EventActionsModel
    @State private var editing = false
    @State private var auth = false
    @State private var cancelling = false
    @State private var reporting: ReportTarget?
    @State private var blocking = false
    /// Попередження перед виходом у чужий чат: спершу кажемо, куди й хто це додав.
    @State private var openingContact = false
    @State private var photo: PhotosPickerItem?
    /// Картка, з якою відкрили екран. Карусель будується від неї: скасованого вечора в індексі нема.
    @State private var anchor: Event?
    @State private var sessions: [EventSession] = []
    /// Зміщення стрічки, за яким їде обкладинка. Див. `reportsScrollOffset`.
    @State private var offset: CGFloat = 0
    /// Верхній відступ safe area саме цієї стрічки. У стосі це смуга статусу, у шторці — майже
    /// нуль; число з вікна (`measuredStatusBarInset`) у шторці завищене на висоту смуги, і
    /// обкладинка стирчала з-під місця, відведеного їй у стрічці. Початкове значення — для
    /// першого кадру в стосі; далі уточнює `onGeometryChange`.
    @State private var topInset: CGFloat = measuredStatusBarInset()
    @Environment(\.openMap) private var openMap

    /// Id відкритої події від того, хто відкриває, а не зі стану: див. `.task` нижче.
    let eventID: String

    init(app: PoruchApp, eventID: String) {
        self.eventID = eventID
        _actions = StateObject(wrappedValue: EventActionsModel(app: app))
    }

    var body: some View {
        let view = EventDetailPresentation(state: model.state, eventID: eventID, sessions: sessions)
        Group {
            if let event = view.event {
                detail(event, view)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            }
        }
        // Єдине місце, де перепитуємо місця й членство. За переданим id, а не за `model.state`:
        // знімок стану приходить асинхронно і в мить появи ще тримає попередню відкриту подію.
        .task { model.app.openEvent(id: eventID) }
        // Перша картка стає якорем; перебудова лише коли оновилась вона або прийшов новий індекс.
        .onChange(of: view.event, initial: true) { _, event in
            guard let event, anchor == nil || anchor?.id == event.id else { return }
            anchor = event
            sessions = model.app.sessionsOf(event: event)
        }
        .onChange(of: model.eventsRevision) {
            if let anchor { sessions = model.app.sessionsOf(event: anchor) }
        }
        .task(id: photo) { if let event = view.event { await actions.upload(photo, to: event) } }
        // У деталей власна нижня панель, таббар стояв би на ній.
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $auth) { NavigationStack { AuthView() } }
    }

    @ViewBuilder
    private func detail(_ event: Event, _ view: EventDetailPresentation) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    hero(event, view)
                    sections(event, view).padding(.horizontal, Space.page)
                }.padding(.bottom, 140)
                .reportsScrollOffset(in: detailScrollSpace, to: $offset)
            }
            .coordinateSpace(name: detailScrollSpace)
            .refreshable { await model.reloadEvent(id: eventID) }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
            // Єдиний шар обкладинки: від краю екрана, під смугою статусу. При потягу вниз
            // розтягується, при прокрутці їде вгору вдвічі повільніше за стрічку (паралакс);
            // сама стрічка лишається в safe area, щоб індикатор потягу було видно. Градієнт у
            // папір тут же, на картинці, а не в стрічці: інакше при паралаксі вони розходяться
            // і низ фото стирчить різким краєм.
            .background(alignment: .top) {
                EventThumbnail(event: event, glyphSize: 48, maxDimension: 420)
                    .frame(height: heroHeight + max(offset, 0)).frame(maxWidth: .infinity).clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: Palette.canvas.opacity(0.75), location: 0.6),
                                    .init(color: Palette.canvas, location: 1)],
                            startPoint: .top, endPoint: .bottom
                        ).frame(height: 150)
                    }
                    .offset(y: min(offset, 0) * heroParallax)
                    .ignoresSafeArea(edges: .top)
            }
            stickyBar(event, view)
        }
        .background(Palette.canvas)
        .modifier(DetailSheets(event: event, view: view, editing: $editing, actions: actions))
        .modifier(DetailDialogs(event: event, view: view, openingContact: $openingContact, cancelling: $cancelling, blocking: $blocking, reporting: $reporting, actions: actions))
    }

    /// Секції під обкладинкою. Окремою функцією: в одному виразі компілятор не встигав вивести тип.
    @ViewBuilder
    private func sections(_ event: Event, _ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            headline(event, view)
            if sessions.count > 1 { sessionRail(event) }
            facts(event)
            if !view.attendees.isEmpty { roster(event, view) }
            externalActions(event, view)
            venue(event)
            description(event)
            if view.hasChat || view.contactURL != nil { contact(view) }
            if view.organizer && !view.requests.isEmpty { joinRequests(event, view) }
            if view.organizer && !view.cancelled { organizerActions(view) }
            if !view.organizer { safetyActions(view) }
        }
    }

    /// Свій опис повністю, чужий уривком: межу проводить домен (`displayDescription`).
    @ViewBuilder
    private func description(_ event: Event) -> some View {
        // Більшість афіш без опису: заголовок над порожнечею гірший за відсутність секції.
        if !event.displayDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SectionHeader(title: "Опис")
            Text(event.displayDescription).font(PoruchFont.lead).foregroundStyle(Palette.inkSecondary).lineSpacing(5)
        }
        if let url = sourceURL(event) {
            Link("Читати повністю на джерелі", destination: url)
                .font(PoruchFont.button).foregroundStyle(Palette.brand)
        }
    }
}

/// Аркуші деталей: редактор, календар. Винесено з `detail`, щоб вираз лишався компільованим.
private struct DetailSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    let event: Event
    let view: EventDetailPresentation
    @Binding var editing: Bool
    @ObservedObject var actions: EventActionsModel

    func body(content: Content) -> some View {
        content
        .sheet(isPresented: $editing) { EventEditor(event: event, app: model.app, home: model.state) }
        .sheet(item: Binding(
            get: { actions.calendarStore.map(CalendarSession.init) },
            set: { if $0 == nil { actions.calendarStore = nil } }
        )) { session in
            CalendarEditor(event: event, store: session.store)
        }
        .alert("Календар", isPresented: $actions.calendarDenied) {
            Button("Добре") { actions.calendarDenied = false }
        } message: { Text("Дозвольте доступ до календаря в налаштуваннях iOS.") }
    }
}

/// Діалоги деталей: посилання, скасування, блокування, скарга.
private struct DetailDialogs: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let event: Event
    let view: EventDetailPresentation
    @Binding var openingContact: Bool
    @Binding var cancelling: Bool
    @Binding var blocking: Bool
    @Binding var reporting: ReportTarget?
    @ObservedObject var actions: EventActionsModel

    func body(content: Content) -> some View {
        content
        .confirmationDialog(
            "Ви переходите на \(view.contactURL.map { ContactRules.shared.host(url: $0.absoluteString) } ?? "сторонній сайт"). Це посилання додав організатор події. «Поруч» не перевіряє його і не відповідає за вміст сторінки чи чату за ним. Не переходьте, якщо не довіряєте організатору.",
            isPresented: $openingContact, titleVisibility: .visible
        ) {
            Button("Перейти") { if let url = view.contactURL { UIApplication.shared.open(url) } }
        }
        .confirmationDialog("Скасувати цю подію? Учасники бачитимуть її скасованою.", isPresented: $cancelling, titleVisibility: .visible) {
            Button("Скасувати подію", role: .destructive) { actions.cancel(event) }
        }
        .confirmationDialog(
            "Ви більше не побачите подій цієї людини, а вона — ваших. Скасувати можна у профілі.",
            isPresented: $blocking, titleVisibility: .visible
        ) {
            Button("Заблокувати", role: .destructive) {
                // В афіші організатора нема, блокувати нема кого.
                if let organizerId = event.organizerId {
                    model.app.blockUser(userId: organizerId)
                }
                dismiss()
            }
        }
        .sheet(item: $reporting) { target in
            ReportSheet(target: target) { reason, details in
                switch target {
                case .event: model.app.reportEvent(eventId: event.id, reason: reason, details: details)
                case .organizer:
                    if let organizerId = event.organizerId {
                        model.app.reportUser(userId: organizerId, reason: reason, details: details)
                    }
                // Скарга на повідомлення відкривається з чату, не звідси.
                case .message: break
                }
            }.presentationDetents([.medium, .large])
        }
    }
}

/// Висота обкладинки від краю екрана.
private let heroHeight: CGFloat = 300
/// Частка швидкості стрічки, з якою обкладинка їде вгору. Менше одиниці — паралакс.
private let heroParallax: CGFloat = 0.5
/// Ім'я системи координат стрічки для `reportsScrollOffset`.
private let detailScrollSpace = "detail"

extension EventDetailView {
    /// Місце обкладинки у стрічці: саму картинку малює тло під нею (див. `detail`). Стрічка
    /// починається під верхнім відступом, тож тут лише решта висоти. Кнопки згори, бейджі внизу,
    /// на фото, де вже темніє градієнт: тому вони в стилі «на фото».
    private func hero(_ event: Event, _ view: EventDetailPresentation) -> some View {
        Color.clear
            .frame(height: max(heroHeight - topInset, 0)).frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) { badges(event, view).padding(.horizontal, Space.page) }
            .overlay(alignment: .top) {
                HStack(spacing: Space.sm) {
                    ScrimButton(symbol: "chevron.left", label: "Назад") { dismiss() }
                    Spacer()
                    ShareLink(item: SystemActions.shareText(for: event)) { ScrimGlyph(symbol: "square.and.arrow.up") }
                        .accessibilityLabel("Поділитися")
                    ScrimButton(
                        symbol: view.saved ? "bookmark.fill" : "bookmark",
                        label: view.saved ? "Прибрати зі збережених" : "Зберегти подію"
                    ) { if !actions.toggleSaved(event, signedIn: view.signedIn) { auth = true } }
                }.padding(Space.page)
            }
    }

    /// Категорія і стан: на обкладинці, тому в стилі «на фото».
    private func badges(_ event: Event, _ view: EventDetailPresentation) -> some View {
        HStack(spacing: Space.sm) {
            StatusBadge(text: categoryName(event.category), tone: .brand, onPhoto: true)
            if view.cancelled { StatusBadge(text: "Скасовано", tone: .danger, onPhoto: true) }
            // Афіша завжди підписана джерелом: атрибуція обов'язкова.
            else if let listing = view.listing {
                StatusBadge(text: listing.isWithdrawn ? "Більше не проводиться" : "Афіша · \(listing.sourceName)", tone: .neutral, onPhoto: true)
            }
            else if view.organizer { StatusBadge(text: "Ви організатор", tone: .neutral, onPhoto: true) }
            else if view.room?.joined == true { StatusBadge(text: "Ви йдете", tone: .success, symbol: "checkmark", onPhoto: true) }
            else if view.waitlisted { StatusBadge(text: "У черзі", tone: .accent, symbol: "hourglass", onPhoto: true) }
            else if view.room?.awaitingApproval == true { StatusBadge(text: "Запит надіслано", tone: .accent, symbol: "hourglass", onPhoto: true) }
            else if eventScarce(event), let room = view.room { StatusBadge(text: "Лишилось \(room.seatsLeft) місць", tone: .accent, onPhoto: true) }
        }
    }

    private func headline(_ event: Event, _ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            // Для кого подія, на картці, а не через відмову сервера.
            if let room = view.room, room.hasAgeLimit || room.approvalRequired {
                HStack(spacing: Space.sm) {
                    if let limit = ageLimitLabel(room) { StatusBadge(text: limit, tone: .brand, symbol: "person") }
                    if room.approvalRequired { StatusBadge(text: "За підтвердженням", tone: .neutral, symbol: "lock") }
                }
            }
            Text(event.title).font(PoruchFont.display).displayTracking().foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Дати прокату. Лише коли сеансів більше одного. Скасований лишається на місці, позначеним.
    private func sessionRail(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Дати")
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        ForEach(sessions, id: \.id) { session in
                            sessionChip(session, selected: session.id == event.id).id(session.id)
                        }
                    }
                }
                // Смуга від краю до краю, відступ несе вміст.
                .railContentPadding()
                .padding(.horizontal, -Space.page)
                // Обраний сеанс має бути видно одразу, навіть якщо він шостий.
                .onAppear { proxy.scrollTo(event.id, anchor: .center) }
            }
        }
        // Без zIndex дотики до стрічки перехоплює сусідня секція.
        .zIndex(1)
    }

    private func sessionChip(_ session: EventSession, selected: Bool) -> some View {
        let label = sessionLabel(session)
        let started = parseEventDate(session.startsAt).map { $0 <= Date() } ?? false
        let status = session.cancelled ? "Скасовано" : started ? "Уже почався" : nil
        return Button {
            if !selected { model.app.openEvent(id: session.id) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.day).font(PoruchFont.caption).lineLimit(1)
                    .foregroundStyle(selected ? Palette.surface.opacity(0.8) : Palette.inkSecondary)
                Text(label.hour).font(PoruchFont.cardName).strikethrough(session.cancelled)
                    .foregroundStyle(selected ? Palette.surface : Palette.ink)
                if let status {
                    Text(status).font(PoruchFont.caption).lineLimit(1)
                        .foregroundStyle(session.cancelled ? Palette.danger : selected ? Palette.surface.opacity(0.8) : Palette.inkTertiary)
                }
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
            .frame(minWidth: 96, alignment: .leading)
            .background(selected ? Palette.ink : Palette.surface,
                        in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: selected ? 0 : 1)
            )
            .opacity(session.cancelled && !selected ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel([label.day, label.hour, status].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Факти про подію в чотирьох рядках. Останні два різні для кімнати й афіші.
    @ViewBuilder
    private func facts(_ event: Event) -> some View {
        VStack(spacing: Space.lg) {
            InfoRow(symbol: "calendar", label: "КОЛИ", value: eventDate(event))
            InfoRow(symbol: "mappin.and.ellipse", label: "ДЕ", value: [event.city, event.address].filter { !$0.isEmpty }.joined(separator: " · "))
            if let room = event.gathering {
                InfoRow(symbol: "person.crop.circle", label: "ОРГАНІЗАТОР", value: room.organizerName.isEmpty ? "Організатор" : room.organizerName)
                InfoRow(symbol: "person.2", label: "МІСТКІСТЬ", value: "\(room.attendeeCount) з \(room.capacity) учасників")
            }
            if let listing = event.listing {
                InfoRow(symbol: "globe", label: "ДЖЕРЕЛО", value: listing.sourceName)
                InfoRow(symbol: "ticket", label: "КВИТКИ", value: listingPrice(listing))
            }
        }.padding(Space.lg).cardSurface()
    }

    private func roster(_ event: Event, _ view: EventDetailPresentation) -> some View {
        HStack(spacing: Space.md) {
            AvatarStack(attendees: view.attendees, total: Int(event.gathering?.attendeeCount ?? Int32(view.attendees.count)))
            VStack(alignment: .leading, spacing: 2) {
                Text("ІДУТЬ").font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                Text(view.attendees.map(\.name).joined(separator: ", "))
                    .font(PoruchFont.subhead).foregroundStyle(Palette.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(Space.lg).cardSurface()
    }

    private func externalActions(_ event: Event, _ view: EventDetailPresentation) -> some View {
        HStack(spacing: Space.md) {
            SecondaryButton(title: "У календар", symbol: "calendar.badge.plus", enabled: !view.cancelled) {
                actions.requestCalendar()
            }
            SecondaryButton(title: "Маршрут", symbol: "arrow.triangle.turn.up.right") {
                SystemActions.openInMaps(event)
            }
        }
    }

    /// Місце події. Мініатюра без жестів, тап веде на велику мапу.
    private func venue(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            // В афіші це адреса залу, а не «місце зустрічі».
            SectionHeader(title: event.isCommunity ? "Місце зустрічі" : "Місце")
            ZStack(alignment: .bottomTrailing) {
                EventMap(
                    events: [event.asIndexEntry()], latitude: event.latitude, longitude: event.longitude,
                    selectedID: event.id, interactive: false, selected: { _ in }, moved: { _ in }
                )
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Corner.sm, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1)
                )
                .allowsHitTesting(false)
                StatusBadge(text: "Показати на мапі", tone: .neutral, symbol: "map").padding(Space.sm)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Вибір до переходу, щоб мапа навелась. Для другої дати прокату — картка представника.
                model.app.selectEvent(id: model.app.cardIdOf(id: event.id))
                dismiss()
                openMap()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Показати на мапі")
        }
    }

    /// Чат учасників. Кнопка веде не в браузер, а на попередження: посилання чуже, ми його не
    /// перевіряли, і людина має це знати до того, як вийде із застосунку.
    private func contact(_ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Звʼязок з учасниками")
            if view.hasChat {
                // Повний екран у стеку, а не шторка: чат читають довго.
                NavigationLink(value: ChatRoute(id: view.event?.id ?? "")) {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 15, weight: .semibold))
                        Text("Чат учасників").font(PoruchFont.button).lineLimit(1)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Space.xxl).frame(height: 52).frame(maxWidth: .infinity)
                    .background(Palette.surfaceMuted, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                Text("Пишуть лише організатор і підтверджені учасники.")
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
            if view.contactURL != nil {
                SecondaryButton(title: "Відкрити посилання", symbol: "link") { openingContact = true }
                    .frame(maxWidth: .infinity)
                Text("Посилання від організатора. Бачать лише учасники події.")
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    /// Запити на участь. На екрані деталей, бо організатор відповідає, дивлячись на свою подію.
    private func joinRequests(_ event: Event, _ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Запити на участь")
            ForEach(view.requests, id: \.userId) { person in
                HStack(spacing: Space.md) {
                    AvatarStack(attendees: [person], total: 1, size: 36)
                    Text(person.name.isEmpty ? "Учасник" : person.name)
                        .font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                    Button("Відхилити") { model.app.declineMember(eventId: event.id, userId: person.userId) }
                        .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                    Button("Прийняти") { model.app.approveMember(eventId: event.id, userId: person.userId) }
                        .font(PoruchFont.button).foregroundStyle(Palette.onBrand)
                        .padding(.horizontal, Space.lg).frame(height: 40)
                        .background(Palette.brand, in: Capsule())
                }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
            }
        }
    }

    /// Скарга й блокування внизу сторінки, не в меню: важка скарга — неподана скарга.
    private func safetyActions(_ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Divider().overlay(Palette.hairline)
            HStack(spacing: Space.lg) {
                Button("Поскаржитись") { if view.signedIn { reporting = .event } else { auth = true } }
                // Блокувати нема кого без людини; скарга на афішу лишається.
                if view.event?.organizerId != nil {
                    Button("Заблокувати організатора") { if view.signedIn { blocking = true } else { auth = true } }
                }
                Spacer(minLength: 0)
            }.font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
        }
    }

    private func organizerActions(_ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Divider().overlay(Palette.hairline)
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Додати або замінити фото", systemImage: "camera")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            }.disabled(view.mutating)
            if let error = actions.photoError {
                Text(error).font(PoruchFont.caption).foregroundStyle(Palette.danger)
            }
            HStack(spacing: Space.md) {
                SecondaryButton(title: "Редагувати", symbol: "pencil") { editing = true }
                SecondaryButton(title: "Скасувати", symbol: "xmark", tone: Palette.danger) { cancelling = true }
            }
        }
    }

    private func stickyBar(_ event: Event, _ view: EventDetailPresentation) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2)
                    .foregroundStyle(Palette.inkTertiary).lineLimit(1)
                Text(view.seatsSummary).font(PoruchFont.subhead)
                    .foregroundStyle(view.cancelled ? Palette.danger : Palette.inkSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            // Кнопки може не бути: у знятої афіші й афіші без посилання нема куди вести.
            if view.action != .none {
                PrimaryButton(
                    title: view.action.title,
                    tone: view.action == .leave ? Palette.success : view.action == .leaveWaitlist ? Palette.accent : nil,
                    loading: view.mutating,
                    enabled: view.action.isEnabled && !view.mutating
                ) {
                    if !actions.perform(view.action, on: event, signedIn: view.signedIn) { auth = true }
                }.fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.md)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

/// Сторінка джерела афіші. Лише https: інші схеми з чужого рядка не мають ставати посиланням.
func sourceURL(_ event: Event) -> URL? {
    guard let raw = event.listing?.canonicalUrl, let url = URL(string: raw), url.scheme == "https" else { return nil }
    return url
}

/// `sheet(item:)` потребує identity, а в `EKEventStore` її нема.
struct CalendarSession: Identifiable {
    let store: EKEventStore
    var id: ObjectIdentifier { ObjectIdentifier(store) }
}

struct ScrimGlyph: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
            .frame(width: 40, height: 40).background(.white.opacity(0.92), in: Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.06), lineWidth: 1))
    }
}

struct ScrimButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { ScrimGlyph(symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

/// На що скарга: на подію чи на того, хто її опублікував.
enum ReportTarget: String, Identifiable {
    case event, organizer, message
    var id: String { rawValue }
    var title: String {
        switch self {
        case .event: "Поскаржитись на подію"
        case .organizer: "Поскаржитись на організатора"
        case .message: "Поскаржитись на повідомлення"
        }
    }
}

/// Скарга: іменована причина для сортування черги модерації плюс необов'язковий текст.
struct ReportSheet: View {
    let target: ReportTarget
    let send: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ReportReason.shared.MINORS
    @State private var details = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text(target.title).font(PoruchFont.title1).titleTracking().foregroundStyle(Palette.ink)
                Text("Оберіть причину. Скаргу побачить лише модерація.")
                    .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                ForEach(reportReasons, id: \.value) { option in
                    Button { reason = option.value } label: {
                        HStack(spacing: Space.md) {
                            ZStack {
                                Circle().fill(reason == option.value ? Palette.brand : Palette.surfaceMuted)
                                if reason == option.value {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Palette.onBrand)
                                }
                            }.frame(width: 20, height: 20)
                            Text(option.title).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                        }.padding(.vertical, Space.sm).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                LabelledField(label: "Що сталося (необовʼязково)", text: $details, multiline: true)
                PrimaryButton(title: "Надіслати скаргу") { send(reason, details); dismiss() }
            }
            .padding(Space.page)
        }
        .background(Palette.canvas)
    }
}
