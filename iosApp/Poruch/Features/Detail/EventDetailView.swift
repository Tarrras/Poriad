import SwiftUI
import PhotosUI
import EventKit
import Shared

struct EventDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var actions: EventActionsModel
    @State private var editing = false
    @State private var auth = false
    @State private var cancelling = false
    @State private var reporting: ReportTarget?
    @State private var blocking = false
    @State private var photo: PhotosPickerItem?
    @Environment(\.openMap) private var openMap

    init(app: PoruchApp) {
        _actions = StateObject(wrappedValue: EventActionsModel(app: app))
    }

    var body: some View {
        let view = EventDetailPresentation(state: model.state)
        Group {
            if let event = view.event {
                detail(event, view)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            }
        }
        // Один гачок замість пʼяти місць презентації: саме тут видно, що екран справді відкрили,
        // і саме тут варто перепитати число місць та членство. Вибір події на мапі цього не варт.
        .task { if let id = model.state?.selectedEvent?.id { model.app.openEvent(id: id) } }
        .task(id: photo) { if let event = view.event { await actions.upload(photo, to: event) } }
        // Деталі мають власну нижню панель із дією; плаваюча панель вкладок стояла б просто на ній.
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
                    VStack(alignment: .leading, spacing: Space.lg) {
                        headline(event, view)
                        facts(event)
                        if !view.attendees.isEmpty { roster(event, view) }
                        externalActions(event, view)
                        venue(event)
                        // 867 подій із 1256 приходять без опису взагалі — джерело його не дає.
                        // Заголовок «опис» над порожнечею обіцяє текст, якого немає й не буде.
                        if !event.displayDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            SectionHeader(title: "Опис")
                            // Свій опис показуємо повністю, чужий — уривком і з посиланням: межу
                            // проводить домен (`displayDescription`), бо вона правова, а не верстальна.
                            Text(event.displayDescription).font(PoruchFont.lead).foregroundStyle(Palette.inkSecondary).lineSpacing(5)
                        }
                        if let url = sourceURL(event) {
                            Link("Читати повністю на джерелі", destination: url)
                                .font(PoruchFont.button).foregroundStyle(Palette.brand)
                        }
                        if view.organizer && !view.requests.isEmpty { joinRequests(event, view) }
                        if view.organizer && !view.cancelled { organizerActions(view) }
                        if !view.organizer { safetyActions(view) }
                    }.padding(.horizontal, Space.page)
                }.padding(.bottom, 140)
            }.ignoresSafeArea(edges: .top)
            stickyBar(event, view)
        }
        .background(Palette.canvas)
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
        .confirmationDialog("Скасувати цю подію? Учасники бачитимуть її скасованою.", isPresented: $cancelling, titleVisibility: .visible) {
            Button("Скасувати подію", role: .destructive) { actions.cancel(event) }
        }
        .confirmationDialog(
            "Ви більше не побачите подій цієї людини, а вона — ваших. Скасувати можна у профілі.",
            isPresented: $blocking, titleVisibility: .visible
        ) {
            Button("Заблокувати", role: .destructive) {
                // У імпортованої афіші організатора немає — блокувати нема кого.
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
                }
            }.presentationDetents([.medium, .large])
        }
    }

    private func hero(_ event: Event, _ view: EventDetailPresentation) -> some View {
        // Справжній відступ під смугу статусу, а не `Space.xxl` навмання: на телефоні з вирізом
        // кнопки заходили під годинник. Головна й профіль уже читають цей самий інсет.
        let topInset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }.first ?? Space.xxl
        return EventThumbnail(event: event, glyphSize: 48, maxDimension: 420)
            .frame(height: 300).frame(maxWidth: .infinity).clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Palette.canvas], startPoint: .top, endPoint: .bottom).frame(height: 120)
            }
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
                }.padding(Space.page).padding(.top, topInset)
            }
    }

    private func headline(_ event: Event, _ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.sm) {
                StatusBadge(text: categoryName(event.category), tone: .brand)
                if view.cancelled { StatusBadge(text: "Скасовано", tone: .danger) }
                // Афіша підписана джерелом завжди: атрибуція обов'язкова, а стану участі в неї немає.
                else if let listing = view.listing {
                    StatusBadge(text: listing.isWithdrawn ? "Більше не проводиться" : "Афіша · \(listing.sourceName)", tone: .neutral)
                }
                else if view.organizer { StatusBadge(text: "Ви організатор", tone: .neutral) }
                else if view.room?.joined == true { StatusBadge(text: "Ви йдете", tone: .success, symbol: "checkmark") }
                else if view.waitlisted { StatusBadge(text: "У черзі", tone: .accent, symbol: "hourglass") }
                else if view.room?.awaitingApproval == true { StatusBadge(text: "Запит надіслано", tone: .accent, symbol: "hourglass") }
                else if eventScarce(event), let room = view.room { StatusBadge(text: "Лишилось \(room.seatsLeft) місць", tone: .accent) }
            }
            // Who the evening is for, said on the card rather than discovered when the server refuses.
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

    /// Що це за подія, у чотирьох рядках. Останні два різні для кімнати й для афіші, і саме тут
    /// найдовше жила вада: «ОРГАНІЗАТОР Karabas» і «0 з 1 учасників» під чужим концертом.
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

    /**
     Місце події та вихід на велику мапу.

     Сама мініатюра жестів не приймає — сто вісімдесят точок замало, щоб у ній щось шукати. Але
     питання «а що там поруч?» виникає саме тут, і відповідь у застосунку вже є, тож тап веде на
     мапу, наведену на цей самий пін.
     */
    private func venue(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            // На концерт не «зустрічаються»: у афіші це просто адреса залу.
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
                // Вибір робимо до переходу: мапа наводиться саме на вибрану подію.
                model.app.selectEvent(id: event.id)
                dismiss()
                openMap()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Показати на мапі")
        }
    }

    /**
     The door of an event that vets its guests. It sits inside the detail screen rather than on a
     screen of its own because an organizer answers a request while looking at what they published —
     the age limit they set is right above it.
     */
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

    /**
     Reporting and blocking, at the bottom of the page and not hidden in a menu: somebody who needs
     them is not in the mood to go looking, and a report that is hard to file is a report not filed.
     */
    private func safetyActions(_ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Divider().overlay(Palette.hairline)
            HStack(spacing: Space.lg) {
                Button("Поскаржитись") { if view.signedIn { reporting = .event } else { auth = true } }
                // Блокувати нема кого там, де немає людини: скарга на саму афішу лишається доступною.
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
            // Кнопки може не бути зовсім: у знятої афіші й у афіші без посилання нема куди вести,
            // і вимкнена кнопка тут була б лише запрошенням у нікуди.
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

/// Сторінка джерела афіші, якщо вона є і виглядає як адреса. Тільки https: інші схеми з чужого
/// рядка в базі не мають ставати посиланням, на яке можна натиснути.
func sourceURL(_ event: Event) -> URL? {
    guard let raw = event.listing?.canonicalUrl, let url = URL(string: raw), url.scheme == "https" else { return nil }
    return url
}

/// `sheet(item:)` needs an identity; an `EKEventStore` has none of its own.
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

/// What a report is about: the event in front of the reader, or the person who published it.
enum ReportTarget: String, Identifiable {
    case event, organizer
    var id: String { rawValue }
    var title: String { self == .event ? "Поскаржитись на подію" : "Поскаржитись на організатора" }
}

/**
 A report is a named reason plus, optionally, a sentence. The reason is what a moderation queue can
 sort by — «this is about a minor» has to be answerable before «this is spam» — and the sentence is
 what a person needs when the list does not fit their case.
 */
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
