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
    /// Інші події на цій же точці: «Ще в цьому місці».
    @State private var othersHere: [EventIndexEntry] = []
    /// Зміщення стрічки, за яким їде обкладинка. Див. `reportsScrollOffset`.
    @State private var offset: CGFloat = 0
    /// Верхній відступ safe area саме цієї стрічки. У стосі це смуга статусу, у шторці — майже
    /// нуль; число з вікна (`measuredStatusBarInset`) у шторці завищене на висоту смуги, і
    /// обкладинка стирчала з-під місця, відведеного їй у стрічці. Початкове значення — для
    /// першого кадру в стосі; далі уточнює `onGeometryChange`.
    @State private var topInset: CGFloat = measuredStatusBarInset()
    /// Запит деталей уже побачили в стані. До того порожня подія — ще не відповідь, а перший кадр.
    @State private var requested = false
    /// Ростер розгорнуто кнопкою «Показати всіх».
    @State private var showAllPeople = false
    /// Картка людини відкрита з цього екрана. Див. `personSheet`.
    @State private var showingPerson = false
    /// Шторка «Шукаю компанію».
    @State private var seekingCompany = false
    /// «Поділитися» щойно створеним супутником.
    @State private var sharingCompanion: ShareText?
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
            } else if requested && model.state?.detail.loading == false {
                // Сервер відповів порожньо або з помилкою: не вічний спінер, а вихід.
                VStack(spacing: Space.lg) {
                    EmptyState(
                        symbol: "calendar.badge.exclamationmark", title: "Подія недоступна",
                        message: "Її могли скасувати, приховати або видалити.",
                        actionLabel: "Спробувати ще раз"
                    ) { model.app.openEvent(id: eventID) }
                    SecondaryButton(title: "Назад") { dismiss() }
                }
                .padding(Space.page).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            } else {
                PoruchLoader().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            }
        }
        .onChange(of: model.state?.detail.loading) { _, loading in if loading == true { requested = true } }
        // Єдине місце, де перепитуємо місця й членство. За переданим id, а не за `model.state`:
        // знімок стану приходить асинхронно і в мить появи ще тримає попередню відкриту подію.
        .task { model.app.openEvent(id: eventID) }
        // Перша картка стає якорем; перебудова лише коли оновилась вона або прийшов новий індекс.
        .onChange(of: view.event, initial: true) { _, event in
            guard let event, anchor == nil || anchor?.id == event.id else { return }
            anchor = event
            sessions = model.app.sessionsOf(event: event)
            othersHere = model.app.othersAt(event: event)
        }
        .onChange(of: model.eventsRevision) {
            if let anchor {
                sessions = model.app.sessionsOf(event: anchor)
                othersHere = model.app.othersAt(event: anchor)
            }
        }
        // Події закладу з сервера приїхали: «Ще в цьому місці» бачить і те, чого нема в індексі мапи.
        .onChange(of: model.state?.detail.placeEvents) {
            if let anchor { othersHere = model.app.othersAt(event: anchor) }
        }
        .task(id: photo) { if let event = view.event { await actions.upload(photo, to: event) } }
        // У деталей власна нижня панель, таббар стояв би на ній.
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $auth) { NavigationStack { AuthView() } }
        .personSheet(model, isPresented: $showingPerson, request: { userId in
            guard let event = view.event, view.organizer, view.requests.contains(where: { $0.userId == userId }) else { return nil }
            return PersonRequest(
                approve: { model.app.approveMember(eventId: event.id, userId: userId) },
                decline: { model.app.declineMember(eventId: event.id, userId: userId) }
            )
        }, onBlocked: { userId in
            // Організатор — разом із подією; учасник зникає лише з ростеру.
            if userId == view.event?.organizerId { dismiss() }
        })
        .onDisappear { model.app.closePerson() }
        // Супутник створено: «Поділитися» з посиланням на нього, бо без поширення компанію не знайти.
        .onChange(of: model.state?.createdCompanion) { _, created in
            guard let created, let event = view.event else { return }
            model.app.clearCreatedCompanion()
            sharingCompanion = ShareText(text: "Шукаю компанію на \(event.title), \(eventDate(event))\n\(EventLinks.shared.url(eventId: created))")
        }
        .sheet(item: $sharingCompanion) { share in ActivitySheet(items: [share.text]).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $seekingCompany) { if let event = view.event { CompanionSheet(event: event) } }
    }

    @ViewBuilder
    private func detail(_ event: Event, _ view: EventDetailPresentation) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    hero(event, view)
                    sections(event, view).padding(.horizontal, Space.page)
                }.padding(.bottom, view.canSeekCompany ? 210 : 140)
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
                            stops: [.init(color: .clear, location: 0), .init(color: Palette.canvas.opacity(0.85), location: 0.55),
                                    .init(color: Palette.canvas, location: 1)],
                            startPoint: .top, endPoint: .bottom
                        ).frame(height: 240)
                    }
                    .offset(y: min(offset, 0) * heroParallax)
                    .ignoresSafeArea(edges: .top)
            }
            // Коли обкладинка поїхала вгору, текст інакше йде під годинник: смуга статусу набирає колір полотна.
            .overlay(alignment: .top) {
                Palette.canvas.frame(height: topInset).ignoresSafeArea(edges: .top)
                    .opacity(min(max((-offset - scrimFrom) / scrimFade, 0), 1))
                    .allowsHitTesting(false)
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
            if let room = view.room, room.hasAgeLimit || room.approvalRequired { restrictions(room) }
            if let parent = view.companionOf {
                NavigationLink(value: EventRoute(id: parent.id)) {
                    HStack(spacing: Space.md) {
                        Image(systemName: "person.2").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink)
                            .frame(width: 40, height: 40).background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                        Text("Разом на: \(parent.title)").font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        Spacer(minLength: Space.sm)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
                    }
                    .padding(Space.lg).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(pressedScale: 1)).cardSurface()
                .accessibilityElement(children: .combine)
            }
            externalActions(event, view)
            if sessions.count > 1 { sessionRail(event) }
            facts(event)
            if !view.companions.isEmpty && !view.cancelled { companionsSection(view) }
            if let room = view.room { people(room, view) }
            venue(event, view)
            if !view.cancelled && !view.ended { safety() }
            if !othersHere.isEmpty { othersHereSection(placeName: event.placeName) }
            description(event)
            if view.hasChat || view.contactURL != nil { contact(view) }
            if view.organizer && !view.requests.isEmpty { joinRequests(event, view) }
            if view.canRate { RateEventSection(event: event, mine: view.myRating) }
            if view.organizer && view.ended && !view.cancelled { RatingsSummary(ratings: view.ratings) }
            // Після кінця редагувати й скасовувати нічого: лишаються відгуки.
            if view.organizer && !view.cancelled && !view.ended { organizerActions(view) }
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
            "Ви переходите на \(view.contactURL.map { ContactRules.shared.host(url: $0.absoluteString) } ?? "сторонній сайт"). Це посилання додав організатор події. «Поряд» не перевіряє його і не відповідає за вміст сторінки чи чату за ним. Не переходьте, якщо не довіряєте організатору.",
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
                // Скарга на повідомлення — з чату, на людину — з її картки.
                case .message, .person: break
                }
            }.presentationDetents([.medium, .large])
        }
    }
}

/// Скільки учасників видно до «Показати всіх».
private let rosterCollapsed = 3
/// Висота обкладинки від краю екрана.
private let heroHeight: CGFloat = 400
/// Звідки й за скільки проявляється смуга під статусом: низ обкладинки вже згас у полотно.
private let scrimFrom: CGFloat = 220
private let scrimFade: CGFloat = 80
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
            // Назва лежить на згасанні обкладинки в полотно, як у Moonly: одна сцена, а не фото з підписом.
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Space.md) {
                    badges(event, view)
                    Text(event.title).font(PoruchFont.display).displayTracking().foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, Space.page)
            }
            .overlay(alignment: .top) {
                HStack(spacing: Space.sm) {
                    ScrimButton(symbol: "chevron.left", label: "Назад") { dismiss() }
                    Spacer()
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
            // Після кінця лишається лише факт участі: черга й місця вже нічого не значать.
            else if view.ended { if view.room?.joined == true { StatusBadge(text: "Ви були", tone: .neutral, symbol: "checkmark", onPhoto: true) } }
            else if view.room?.joined == true { StatusBadge(text: "Ви йдете", tone: .success, symbol: "checkmark", onPhoto: true) }
            else if view.waitlisted { StatusBadge(text: "У черзі", tone: .accent, symbol: "hourglass", onPhoto: true) }
            else if view.room?.awaitingApproval == true { StatusBadge(text: "Запит надіслано", tone: .accent, symbol: "hourglass", onPhoto: true) }
            else if eventScarce(event), let room = view.room { StatusBadge(text: "Лишилось \(room.seatsLeft) місць", tone: .accent, onPhoto: true) }
        }
    }

    /// Для кого подія, на картці, а не через відмову сервера.
    private func restrictions(_ room: Gathering) -> some View {
        HStack(spacing: Space.sm) {
            if let limit = ageLimitLabel(room) { StatusBadge(text: limit, tone: .brand, symbol: "person") }
            if room.approvalRequired { StatusBadge(text: "За підтвердженням", tone: .neutral, symbol: "lock") }
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
            .opacity(session.cancelled && !selected ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel([label.day, label.hour, status].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Факти про подію сіткою два на два, як картка дня в Moonly: підпис над значенням, без гліфів.
    private func facts(_ event: Event) -> some View {
        var cells: [(String, String)] = [
            ("Коли", eventDate(event)),
            ("Де", [event.city, event.address].filter { !$0.isEmpty }.joined(separator: " · "))
        ]
        if let room = event.gathering {
            cells.append(("Організатор", room.organizerName.isEmpty ? "Організатор" : room.organizerName))
            cells.append(("Місткість", "\(room.attendeeCount) з \(room.capacity)"))
        }
        if let listing = event.listing {
            cells.append(("Джерело", listing.sourceName))
            cells.append(("Квитки", listingPrice(listing)))
        }
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: Space.xl) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(cell.0.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                    Text(cell.1).font(PoruchFont.title3).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }.padding(Space.xl).cardSurface()
    }

    /// Люди події: організатор і ті, хто йде. Рядок відкриває картку людини — так організатор і
    /// учасники бачать одне одного. Ростер віддає лише своїм, решта бачить тільки організатора.
    private func people(_ room: Gathering, _ view: EventDetailPresentation) -> some View {
        let organizerAvatar = model.state?.detail.organizerAvatar
        let shown = showAllPeople ? view.attendees : Array(view.attendees.prefix(rosterCollapsed))
        return VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Ідуть")
            GroupedRows {
                personRow(room.organizerName.isEmpty ? "Організатор" : room.organizerName,
                          avatar: organizerAvatar, caption: "Організатор", userId: room.organizerId, view)
                ForEach(shown, id: \.userId) { person in
                    Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                    personRow(person.name.isEmpty ? "Учасник" : person.name, avatar: person.avatarUrl, caption: nil, userId: person.userId, view)
                }
                if !showAllPeople && view.attendees.count > rosterCollapsed {
                    Divider().overlay(Palette.hairline).padding(.leading, Space.lg)
                    Button { showAllPeople = true } label: {
                        Text("Показати всіх · \(view.attendees.count)").font(PoruchFont.button).foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(Space.lg).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            // Гість і сторонній бачать лише число: імена — межа RLS.
            if view.attendees.isEmpty && room.attendeeCount > 0 {
                Text("Ідуть \(room.attendeeCount) з \(room.capacity)").font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    private func openPerson(_ userId: String) {
        showingPerson = true
        model.app.openPerson(userId: userId)
    }

    private func personRow(_ name: String, avatar: String?, caption: String?, userId: String, _ view: EventDetailPresentation) -> some View {
        Button { if view.signedIn { openPerson(userId) } else { auth = true } } label: {
            HStack(spacing: Space.md) {
                Avatar(name: name, url: avatar, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(1)
                    if let caption { Text(caption).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Відкрити профіль: \(name)")
    }

    /// Ряд круглих дій із підписами, як панель під картою дня в Moonly.
    private func externalActions(_ event: Event, _ view: EventDetailPresentation) -> some View {
        HStack(spacing: Space.sm) {
            Button { actions.openCalendar() } label: {
                RoundAction(title: "Календар", enabled: !view.cancelled) { Image(systemName: "calendar.badge.plus") }
            }.buttonStyle(PressableStyle()).disabled(view.cancelled)
            Button { SystemActions.openInMaps(event) } label: {
                RoundAction(title: "Маршрут") { Image(systemName: "arrow.turn.up.right") }
            }.buttonStyle(PressableStyle())
            ShareLink(item: SystemActions.shareText(for: event)) {
                RoundAction(title: "Поділитися") { Image(systemName: "square.and.arrow.up") }
            }.buttonStyle(PressableStyle())
            .simultaneousGesture(TapGesture().onEnded { model.app.eventShared() })
            Button { model.app.selectEvent(id: model.app.cardIdOf(id: event.id)); openMap() } label: {
                RoundAction(title: "На мапі") { Image(systemName: "map") }
            }.buttonStyle(PressableStyle())
        }
    }

    /// Місце події. Мініатюра без жестів, тап веде на велику мапу.
    private func venue(_ event: Event, _ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            // В афіші це адреса залу, а не «місце зустрічі».
            SectionHeader(title: event.isCommunity ? "Місце зустрічі" : "Місце")
            ZStack(alignment: .bottomTrailing) {
                EventMapSnapshot(latitude: event.latitude, longitude: event.longitude, category: event.category)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
                .allowsHitTesting(false)
                StatusBadge(text: "Показати на мапі", tone: .neutral, symbol: "map").padding(Space.sm)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Вибір до переходу, щоб мапа навелась. Для другої дати прокату — картка представника.
                // Без `dismiss()`: деталі закриває `openMap` разом зі стеком. Pop лише верхніх деталей
                // показував нижчі, і їхній `.task` знову обирав свою подію замість цієї.
                model.app.selectEvent(id: model.app.cardIdOf(id: event.id))
                openMap()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Показати на мапі")
            if FollowRules.shared.canFollowPlace(event: event), let placeId = event.placeId {
                followPlace(event, placeId, view)
            }
        }
    }

    /// «Стежити» за закладом афіші: пуш, коли тут зʼявиться нове. Гостя — на вхід, пуш прив'язаний до акаунта.
    private func followPlace(_ event: Event, _ placeId: String, _ view: EventDetailPresentation) -> some View {
        let following = model.state?.isFollowing(kind: .place, targetId: placeId) == true
        return HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.placeLabel).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Text("Скажемо, коли тут зʼявиться щось нове").font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: Space.sm)
            FollowPill(following: following) {
                guard view.signedIn else { auth = true; return }
                model.app.setFollowing(kind: .place, targetId: placeId, name: event.placeLabel, following: !following)
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md).frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Безпека: чи встигнеш до комендантської і куди йти під час тривоги. Правила Мінкульту з 11.09.2026
    /// вимагають заздалегідь казати учасникам про найближче укриття. Нема даних міста — нема секції.
    @ViewBuilder
    private func safety() -> some View {
        let shelters = model.state?.detail.safety?.shelters ?? []
        let curfew = model.state?.detail.curfewNote(now: nowInstant())
        if !shelters.isEmpty || curfew != nil {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title: "Безпека")
                VStack(spacing: 0) {
                    if let curfew {
                        // Година й менше до комендантської — уже привід планувати дорогу, тож колір попередження.
                        let tight = curfew.minutesLeft <= 60
                        HStack(spacing: Space.md) {
                            Image(systemName: "moon.stars").font(.system(size: 16, weight: .semibold))
                            Text(curfew.minutesLeft == 0
                                 ? "Закінчиться о \(curfew.endsAt), уже під час комендантської (з \(curfew.curfew.starts))"
                                 : "Закінчиться о \(curfew.endsAt). Комендантська з \(curfew.curfew.starts) — до неї лишиться \(durationWords(Int(curfew.minutesLeft)))")
                                .font(PoruchFont.bodyText).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(tight ? Palette.danger : Palette.inkSecondary)
                        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                    }
                    ForEach(Array(shelters.enumerated()), id: \.offset) { index, shelter in
                        if index > 0 || curfew != nil { Divider().overlay(Palette.hairline) }
                        Button { SystemActions.openInMaps(latitude: shelter.latitude, longitude: shelter.longitude, label: shelter.address) } label: {
                            HStack(spacing: Space.md) {
                                Image(systemName: shelter.kind == .metro ? "tram.fill.tunnel" : "shield")
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text("\(shelterLabel(shelter.kind)) · \(shelter.distanceMeters) м")
                                        .font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                                    Text(shelter.address).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                                        .multilineTextAlignment(.leading).lineLimit(2)
                                    let extras = [shelter.hours, shelter.accessible ? "Є пандус" : nil].compactMap { $0 }
                                    if !extras.isEmpty {
                                        Text(extras.joined(separator: " · ")).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
                            }
                            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Маршрут до укриття")
                    }
                }
                .cardSurface()
                // Ліцензія CC BY вимагає вказати джерело.
                if !shelters.isEmpty {
                    Text("Укриття — за відкритими даними КМДА. Тап відкриває маршрут.")
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                }
            }
        }
    }

    private func shelterLabel(_ kind: ShelterKind) -> String {
        switch kind {
        case .metro: "Метро"
        case .underpass: "Підземний перехід"
        case .parking: "Підземний паркінг"
        default: "Укриття"
        }
    }

    private func durationWords(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) хв" }
        return rest == 0 ? "\(hours) год" : "\(hours) год \(rest) хв"
    }

    /// Інші події на цій точці. Заголовок — місце (назва закладу, коли є), тому рядку досить дати й назви.
    /// Окремий екран поверх, а не підміна: «назад» має повертати сюди; `.task` вище перечитає подію після повернення.
    private func othersHereSection(placeName: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: placeName.map { "Ще в «\($0)»" } ?? "Ще в цьому місці")
            VStack(spacing: 0) {
                ForEach(othersHere, id: \.id) { other in
                    let label = sessionLabel(EventSession(id: other.id, startsAt: other.startsAt, timeZone: other.timeZone, cancelled: false))
                    NavigationLink(value: EventRoute(id: other.id)) {
                        HStack(spacing: Space.md) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("\(label.day) · \(label.hour)").font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                                Text(other.title).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
                        }
                        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityElement(children: .combine)
                }
            }
            .cardSurface()
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
                    .background(Palette.brandContainer, in: Capsule())
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
                    // Імʼя й фото — вхід у картку: вирішувати, дивлячись на людину, а не на імʼя.
                    Button { openPerson(person.userId) } label: {
                        HStack(spacing: Space.md) {
                            Avatar(name: person.name, url: person.avatarUrl, size: 36)
                            // Поступається імʼя, а не дії: з більшим кеглем кнопок «Прийняти» переносилось на два рядки.
                            Text(person.name.isEmpty ? "Учасник" : person.name)
                                .font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(1)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Відкрити профіль: \(person.name)")
                    Spacer(minLength: 0)
                    Button("Відхилити") { model.app.declineMember(eventId: event.id, userId: person.userId) }
                        .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).lineLimit(1).fixedSize()
                    Button("Прийняти") { model.app.approveMember(eventId: event.id, userId: person.userId) }
                        .font(PoruchFont.button).foregroundStyle(Palette.onBrand).lineLimit(1).fixedSize()
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
            // Час, місце й місткість супутника тримає сервер: лишається скасувати.
            if view.companionOf == nil {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Додати або замінити фото", systemImage: "camera")
                        .font(PoruchFont.subhead.weight(.semibold)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity).frame(minHeight: 52)
                        .background(Palette.brandContainer, in: Capsule())
                }.disabled(view.mutating)
            }
            if let error = actions.photoError {
                Text(error).font(PoruchFont.caption).foregroundStyle(Palette.danger)
            }
            HStack(spacing: Space.md) {
                if view.companionOf == nil { SecondaryButton(title: "Редагувати", symbol: "pencil") { editing = true } }
                SecondaryButton(title: "Скасувати", symbol: "xmark", tone: Palette.danger) { cancelling = true }
            }
        }
    }

    private func stickyBar(_ event: Event, _ view: EventDetailPresentation) -> some View {
        VStack(spacing: Space.md) {
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
                    primaryAction(event, view).fixedSize(horizontal: true, vertical: false)
                }
            }
            // «Шукаю компанію» під квитком на всю ширину: поруч із ціною й квитком не влазить.
            if view.canSeekCompany {
                SecondaryButton(title: "Шукаю компанію", symbol: "person.2", enabled: !view.mutating) {
                    if view.signedIn { seekingCompany = true } else { auth = true }
                }
            }
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.md)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

extension EventDetailView {
    private func primaryAction(_ event: Event, _ view: EventDetailPresentation) -> some View {
        PrimaryButton(
            title: view.action.title,
            tone: view.action == .leave ? Palette.success : view.action == .leaveWaitlist ? Palette.accent : nil,
            loading: view.mutating,
            enabled: view.action.isEnabled && !view.mutating
        ) {
            if !actions.perform(view.action, on: event, signedIn: view.signedIn) { auth = true }
        }
    }

    /// Хто вже шукає компанію на цю афішу. Без імен: організатора видно на сторінці супутника, туди
    /// й веде рядок. «Долучитися» — запит організатору прямо звідси.
    private func companionsSection(_ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Шукають компанію")
            VStack(spacing: 0) {
                ForEach(Array(view.companions.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { Divider().overlay(Palette.hairline) }
                    let label = sessionLabel(EventSession(id: card.id, startsAt: card.meetAt, timeZone: card.timeZone, cancelled: false))
                    HStack(spacing: Space.md) {
                        NavigationLink(value: EventRoute(id: card.id)) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("\(label.day) · \(label.hour)").font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                                Text(card.meetNote ?? "Місце зустрічі").font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading).lineLimit(2)
                                Text("\(card.attendeeCount) з \(card.capacity)").font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(pressedScale: 1))
                        .accessibilityElement(children: .combine)
                        if card.mine { StatusBadge(text: "Ваш пошук", tone: .brand) }
                        else if card.membership == .approved { StatusBadge(text: "Ви йдете", tone: .success, symbol: "checkmark") }
                        else if card.membership == .requested { StatusBadge(text: "Запит надіслано", tone: .accent, symbol: "hourglass") }
                        else if card.isFull { StatusBadge(text: "Місць немає") }
                        else {
                            SecondaryButton(title: "Долучитися", enabled: !view.mutating) {
                                if !actions.joinCompanion(id: card.id, signedIn: view.signedIn) { auth = true }
                            }.fixedSize()
                        }
                    }
                    .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                }
            }
            .cardSurface()
        }
    }
}

/// Текст для системного «Поділитися», відкритого не кнопкою, а подією стану.
struct ShareText: Identifiable {
    let text: String
    var id: String { text }
}

/// Системний аркуш «Поділитися». `ShareLink` — лише кнопка, а тут його відкриває створення супутника.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Коротка шторка замість повного редактора: лише час зустрічі, де зустрітись і скільки людей.
/// Назву, місце й кінець сервер бере з афіші.
struct CompanionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let event: Event
    private let times: [String]
    @State private var at: Int
    @State private var note = ""
    @State private var capacity = Int(CompanionRules.shared.DEFAULT_CAPACITY)

    init(event: Event) {
        self.event = event
        let now = nowInstant()
        let times = CompanionRules.shared.meetTimes(startsAt: event.startsAt, now: now)
        let fallback = CompanionRules.shared.defaultMeetAt(startsAt: event.startsAt, now: now)
        self.times = times
        _at = State(initialValue: fallback.flatMap { times.firstIndex(of: $0) } ?? 0)
    }

    private var mutating: Bool { model.state?.mutating == true }
    private var meetAt: String? { times.indices.contains(at) ? times[at] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Шукаю компанію").font(PoruchFont.title2).foregroundStyle(Palette.ink)
                Text(event.title).font(PoruchFont.cardName).foregroundStyle(Palette.inkSecondary).lineLimit(2)
                Text("Зберіть невелику компанію й ідіть разом. Хто хоче долучитися, надсилає запит — ви вирішуєте, кого взяти. Лише 18+.")
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
                if let meetAt {
                    let lead = (times.count - 1 - at) * Int(CompanionRules.shared.STEP_MINUTES)
                    stepper("Час зустрічі", value: sessionLabel(EventSession(id: event.id, startsAt: meetAt, timeZone: event.timeZone, cancelled: false)).hour,
                            caption: lead == 0 ? "На початку" : "За \(leadWords(lead)) до початку",
                            minus: ("Раніше", at > 0, { at -= 1 }), plus: ("Пізніше", at < times.count - 1, { at += 1 }))
                }
                LabelledField(label: "Де зустрітись", text: $note, placeholder: "Біля головного входу")
                    .onChange(of: note) { _, value in
                        let limit = Int(CompanionRules.shared.NOTE_MAX)
                        if value.count > limit { note = String(value.prefix(limit)) }
                    }
                stepper("Скільки людей шукаєте", value: "\(capacity)", caption: nil,
                        minus: ("Менше", capacity > Int(CompanionRules.shared.MIN_CAPACITY), { capacity -= 1 }),
                        plus: ("Більше", capacity < Int(CompanionRules.shared.MAX_CAPACITY), { capacity += 1 }))
                PrimaryButton(title: "Опублікувати й поділитися", symbol: "square.and.arrow.up", loading: mutating,
                              enabled: meetAt != nil && !mutating) {
                    guard let meetAt else { return }
                    model.app.createCompanion(parentId: event.id, meetAt: meetAt, note: note, capacity: Int32(capacity))
                    dismiss()
                }
            }
            .padding(Space.page)
        }
        .background(Palette.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func leadWords(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) хв" }
        return rest == 0 ? "\(hours) год" : "\(hours) год \(rest) хв"
    }

    /// Значення з кнопками «−» і «+». Підписи кнопок — для VoiceOver.
    private func stepper(_ label: String, value: String, caption: String?,
                         minus: (String, Bool, () -> Void), plus: (String, Bool, () -> Void)) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                Text(value).font(PoruchFont.title2).foregroundStyle(Palette.ink).monospacedDigit()
                if let caption { Text(caption).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary) }
            }
            Spacer(minLength: 0)
            ForEach([(minus, "minus"), (plus, "plus")], id: \.1) { step, symbol in
                Button(action: step.2) {
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(step.1 ? Palette.ink : Palette.inkTertiary)
                        .frame(width: 44, height: 44).background(Palette.surfaceMuted, in: Circle())
                }
                .buttonStyle(PressableStyle()).disabled(!step.1).accessibilityLabel(step.0)
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .cardSurface()
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
        // Коло завжди біле, бо лежить на довільному фото, тож і гліф завжди темний: `Palette.ink`
        // у темній темі майже білий, і кнопки «назад» та «зберегти» ставали порожніми колами.
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(light: 0x1D1D1F, dark: 0x1D1D1F))
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
    case event, organizer, message, person
    var id: String { rawValue }
    var title: String {
        switch self {
        case .event: "Поскаржитись на подію"
        case .organizer: "Поскаржитись на організатора"
        case .message: "Поскаржитись на повідомлення"
        case .person: "Поскаржитись на людину"
        }
    }
}

/// Скарга: іменована причина для сортування черги модерації плюс необов'язковий текст.
/// Кнопка замість форми: сама оцінка — у `RateSheet`, як у «Моїх подіях».
private struct RateEventSection: View {
    let event: Event
    let mine: EventRating?
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Як пройшло?")
            if let mine {
                SecondaryButton(title: "Ваша оцінка ★ \(mine.score) · змінити") { open = true }
            } else {
                PrimaryButton(title: "Оцінити") { open = true }
            }
        }
        .sheet(isPresented: $open) { RateSheet(event: event, mine: mine) }
    }
}

/// «Як пройшло?»: бал 1–5, що сподобалось, кілька слів організатору. Повторна відправка
/// замінює попередню. Спільна для деталей і «Моїх подій».
struct RateSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let event: Event
    let mine: EventRating?
    @State private var score: Int
    @State private var tags: Set<String>
    @State private var comment: String
    /// Перемикач «Стежити за організатором». Nil — не чіпали: тоді початкове значення дає стан підписок.
    @State private var follow: Bool?

    init(event: Event, mine: EventRating?) {
        self.event = event; self.mine = mine
        _score = State(initialValue: mine.map { Int($0.score) } ?? 0)
        _tags = State(initialValue: Set((mine?.tags ?? []).map(\.key)))
        _comment = State(initialValue: mine?.comment ?? "")
    }

    private var mutating: Bool { model.state?.mutating == true }
    /// Теги за категорією події: спершу про суть, далі загальні.
    private var offered: [RatingTag] { RatingRules.shared.tagsFor(category: event.category) }
    /// Організатор, за яким можна стежити: у афіші його нема, а за собою не стежать.
    private var organizerId: String? { event.organizerId.flatMap { $0 == model.state?.session.userId ? nil : $0 } }
    /// Що показує перемикач. Нова оцінка — увімкнено, змінена — як є, щоб не підписати знову того, від кого відписались.
    private var followOrganizer: Bool {
        guard let organizerId else { return false }
        return follow ?? FollowRules.shared.followOnRating(
            alreadyFollowing: model.state?.isFollowing(kind: .organizer, targetId: organizerId) == true, alreadyRated: mine != nil
        )
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    Text("Як пройшло?").font(PoruchFont.title2).foregroundStyle(Palette.ink)
                    VStack(spacing: Space.sm) {
                        HStack(spacing: Space.sm) {
                            ForEach(1...5, id: \.self) { value in
                                Button { score = value } label: {
                                    Text("\(value)").font(PoruchFont.cardName)
                                        .foregroundStyle(value == score ? Palette.onBrand : Palette.ink)
                                        .frame(maxWidth: .infinity).frame(height: 56)
                                        .background {
                                            let shape = RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                                            if value == score { shape.fill(brandGradient) } else { shape.fill(Palette.surface) }
                                        }
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel("\(value) з 5")
                                .accessibilityAddTraits(value == score ? .isSelected : [])
                            }
                        }
                        HStack {
                            Text("Не моє")
                            Spacer()
                            Text("Чудово")
                        }.font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("ЩО СПОДОБАЛОСЬ").font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                        FlexibleChips(
                            items: offered.map { ($0.key, ratingTagTitle($0), nil) },
                            isSelected: { tags.contains($0) },
                            action: { key in if tags.contains(key) { tags.remove(key) } else { tags.insert(key) } }
                        )
                    }
                    LabelledField(label: "Кілька слів організатору", text: $comment, placeholder: "Необовʼязково", multiline: true)
                        .onChange(of: comment) { _, value in
                            let limit = Int(RatingRules.shared.COMMENT_MAX)
                            if value.count > limit { comment = String(value.prefix(limit)) }
                        }
                    if organizerId != nil {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Toggle(isOn: Binding(get: { followOrganizer }, set: { follow = $0 })) {
                                Text("Стежити за організатором").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                            }
                            .tint(Palette.brand)
                            Text("Скажемо, коли в нього зʼявиться нова подія").font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                        }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                    }
                }
                .padding(Space.page)
            }
            Divider().overlay(Palette.hairline)
            VStack(spacing: Space.xs) {
                PrimaryButton(title: mine == nil ? "Надіслати" : "Оновити оцінку", loading: mutating,
                              enabled: score > 0 && !mutating) {
                    // Порядок шторки, не порядок тапів.
                    model.app.rateEvent(id: event.id, score: Int32(score), comment: comment,
                                        tags: offered.filter { tags.contains($0.key) },
                                        followOrganizer: organizerId == nil ? nil : KotlinBoolean(bool: followOrganizer))
                    dismiss()
                }
                Button("Пропустити") { dismiss() }
                    .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).frame(minHeight: 44)
            }
            .padding(.horizontal, Space.page).padding(.top, Space.lg)
        }
        .background(Palette.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

func ratingTagTitle(_ tag: RatingTag) -> String {
    switch tag.key {
    case "atmosphere": "Атмосфера"
    case "organization": "Організація"
    case "place": "Місце"
    case "people": "Люди"
    case "on_time": "Почали вчасно"
    case "music": "Музика"
    case "sound": "Звук"
    case "humor": "Жарти"
    case "host": "Ведучий"
    case "program": "Програма"
    case "coach": "Тренер"
    case "workout": "Тренування"
    case "route": "Маршрут"
    case "views": "Краєвиди"
    case "pace": "Темп"
    case "guide": "Гід"
    case "stories": "Історії"
    case "food": "Їжа"
    case "drinks": "Напої"
    case "game_choice": "Вибір ігор"
    case "rules": "Пояснили правила"
    case "conversation": "Розмови"
    case "kids_liked": "Дітям сподобалось"
    case "safety": "Безпечно"
    case "speakers": "Спікери"
    case "useful": "Корисно"
    case "networking": "Нетворкінг"
    default: tag.key
    }
}

/// Відгуки для організатора: середнє, що сподобалось, коментарі — без імен.
struct RatingsSummary: View {
    let ratings: [EventRating]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Відгуки учасників")
            if let average = RatingRules.shared.average(ratings: ratings)?.doubleValue {
                Text("★ \(String(format: "%.1f", average).replacingOccurrences(of: ".", with: ",")) з 5 · оцінок: \(ratings.count)")
                    .font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                let tags = RatingRules.shared.tagCounts(ratings: ratings)
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.sm) {
                            ForEach(tags, id: \.tag) { StatusBadge(text: "\(ratingTagTitle($0.tag)) · \($0.count)") }
                        }
                    }
                }
                ForEach(Array(ratings.filter { !($0.comment ?? "").isEmpty }.enumerated()), id: \.offset) { _, rating in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Stars(score: Int(rating.score), size: 14)
                        Text(rating.comment ?? "").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                    }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                }
            } else {
                Text("Учасники ще не оцінили зустріч. Оцінити можна протягом 14 днів після завершення.")
                    .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}

/// Пʼять зірок у відгуку організатора.
struct Stars: View {
    let score: Int
    var size: CGFloat
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= score ? "star.fill" : "star")
                    .font(.system(size: size)).foregroundStyle(value <= score ? Palette.brand : Palette.inkTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(score) з 5")
    }
}

struct ReportSheet: View {
    let target: ReportTarget
    let send: (ReportReason, String) -> Void
    @Environment(\.dismiss) private var dismiss
    /// Без причини за замовчуванням: інакше поспіх дає хибні скарги найвищого пріоритету.
    @State private var reason: ReportReason?
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
                    .accessibilityAddTraits(reason == option.value ? .isSelected : [])
                }
                LabelledField(label: "Що сталося (необовʼязково)", text: $details, multiline: true)
                PrimaryButton(title: "Надіслати скаргу", enabled: reason != nil) {
                    if let reason { send(reason, details); dismiss() }
                }
            }
            .padding(Space.page)
        }
        .background(Palette.canvas)
    }
}
