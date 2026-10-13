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
    @Environment(\.dismiss) var dismiss
    @StateObject var actions: EventActionsModel
    @State var editing = false
    @State var auth = false
    @State var cancelling = false
    @State var reporting: ReportTarget?
    @State var blocking = false
    /// Попередження перед виходом у чужий чат: спершу кажемо, куди й хто це додав.
    @State var openingContact = false
    @State var photo: PhotosPickerItem?
    /// Картка, з якою відкрили екран. Карусель будується від неї: скасованого вечора в індексі нема.
    @State var anchor: Event?
    @State var sessions: [EventSession] = []
    /// Інші події на цій же точці: «Ще в цьому місці».
    @State var othersHere: [EventIndexEntry] = []
    /// Зміщення стрічки, за яким їде обкладинка. Див. `reportsScrollOffset`.
    @State var offset: CGFloat = 0
    /// Верхній відступ safe area саме цієї стрічки. У стосі це смуга статусу, у шторці — майже
    /// нуль; число з вікна (`measuredStatusBarInset`) у шторці завищене на висоту смуги, і
    /// обкладинка стирчала з-під місця, відведеного їй у стрічці. Початкове значення — для
    /// першого кадру в стосі; далі уточнює `onGeometryChange`.
    @State var topInset: CGFloat = measuredStatusBarInset()
    /// Запит деталей уже побачили в стані. До того порожня подія — ще не відповідь, а перший кадр.
    @State var requested = false
    /// Ростер розгорнуто кнопкою «Показати всіх».
    @State var showAllPeople = false
    /// Картка людини відкрита з цього екрана. Див. `personSheet`.
    @State var showingPerson = false
    /// «Ще в цьому місці» розгорнуто. Згорнуто за замовчуванням: це вихід з події, а не її частина.
    @State var showOthersHere = false
    /// Шторка «Шукаю компанію».
    @State var seekingCompany = false
    /// «Поділитися» щойно створеним супутником.
    @State var sharingCompanion: ShareText?
    @Environment(\.openMap) var openMap

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
        // Ключ — ідентичність Kotlin-обʼєкта, а не `Equatable`: той порівнював data-клас з усіма сеансами й артистами на кожен рендер.
        .onChange(of: view.event.map(ObjectIdentifier.init), initial: true) { _, _ in
            guard let event = view.event, anchor == nil || anchor?.id == event.id else { return }
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
        .onChange(of: model.state?.detail.placeEvents.map(ObjectIdentifier.init)) {
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
    func detail(_ event: Event, _ view: EventDetailPresentation) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(event, view)
                    // Аркуш із заокругленим верхом наїжджає на обкладинку: сторінка лягає на афішу, а не продовжує її.
                    sections(event, view).padding(.horizontal, Space.page).padding(.top, Space.xl)
                        .padding(.bottom, view.canSeekCompany ? 210 : 140)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.canvas, in: UnevenRoundedRectangle(
                            topLeadingRadius: Corner.xl, topTrailingRadius: Corner.xl, style: .continuous))
                }
                .reportsScrollOffset(in: detailScrollSpace, to: $offset)
            }
            .coordinateSpace(name: detailScrollSpace)
            .refreshable { await model.reloadEvent(id: eventID) }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
            // Єдиний шар обкладинки: від краю екрана, під смугою статусу. При потягу вниз
            // розтягується, при прокрутці їде вгору вдвічі повільніше за стрічку (паралакс);
            // сама стрічка лишається в safe area, щоб індикатор потягу було видно. Та сама афіша,
            // що й велика картка головної (`EventArt`): без фото — насичений градієнт категорії,
            // а не бліда пастель; низ темніє під білу назву.
            .background(alignment: .top) {
                EventArt(event: event, maxDimension: heroHeight, glyphSize: 260, glyphDrop: 120)
                    .frame(height: heroHeight + max(offset, 0)).frame(maxWidth: .infinity).clipped()
                    .overlay(photoScrim)
                    .offset(y: min(offset, 0) * heroParallax)
                    .ignoresSafeArea(edges: .top)
            }
            // Коли аркуш доїхав до годинника, текст інакше йде під нього: смуга статусу набирає колір полотна.
            // Не раніше: світла смуга над темною обкладинкою відрізала б її, а з-під смуги визирали б кути аркуша.
            .overlay(alignment: .top) {
                Palette.canvas.frame(height: topInset).ignoresSafeArea(edges: .top)
                    .opacity(min(max((-offset - (heroHeight - topInset - Corner.xl - scrimFade)) / scrimFade, 0), 1))
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
    func sections(_ event: Event, _ view: EventDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if let room = view.room, room.hasAgeLimit || room.approvalRequired { restrictions(room) }
            if let parent = view.companionOf {
                NavigationLink(value: EventRoute(id: parent.id)) {
                    HStack(spacing: Space.md) {
                        PoruchIcon(glyph: PoruchIcons.social, size: 20).foregroundStyle(Palette.ink)
                            .frame(width: 40, height: 40).background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                        Text("Разом на: \(TitleRules.shared.display(title: parent.title))").font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        Spacer(minLength: Space.sm)
                        PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
                    }
                    .padding(Space.lg).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(pressedScale: 1)).cardSurface()
                .accessibilityElement(children: .combine)
            }
            externalActions(event, view)
            if sessions.count > 1 { sessionRail(event) }
            if !event.artists.isEmpty { lineup(event) }
            facts(event)
            if !view.companions.isEmpty && !view.cancelled { companionsSection(view) }
            if let room = view.room { people(room, view) }
            venue(event, view)
            if !view.cancelled && !view.ended { safety() }
            description(event)
            if !othersHere.isEmpty { othersHereSection(placeName: event.placeName) }
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
    func description(_ event: Event) -> some View {
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
struct DetailSheets: ViewModifier {
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
struct DetailDialogs: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
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
let rosterCollapsed = 3
/// Висота обкладинки від краю екрана.
let heroHeight: CGFloat = 480
/// Звідки й за скільки гасне текст на обкладинці при прокрутці.
let heroTextFadeFrom: CGFloat = 100
let heroTextFade: CGFloat = 140
/// За скільки проявляється смуга під статусом, поки аркуш під'їжджає до неї.
let scrimFade: CGFloat = 40
/// Частка швидкості стрічки, з якою обкладинка їде вгору. Менше одиниці — паралакс.
let heroParallax: CGFloat = 0.5
/// Ім'я системи координат стрічки для `reportsScrollOffset`.
let detailScrollSpace = "detail"
