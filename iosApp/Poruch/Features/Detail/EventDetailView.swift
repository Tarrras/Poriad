import SwiftUI
import PhotosUI
import EventKit
import Shared

/// Маршрут деталей події: для шляху стосу й для шторки.
struct EventRoute: Hashable, Identifiable {
    let id: String
}

/// З якого часу відкрити шторку часу збору.
struct MeetTarget: Identifiable {
    let at: String
    var id: String { at }
}

/// `Equatable` за id: стек створює view заново на кожну емісію кореня, а стан екрану дає `DetailScreenModel`.
struct EventDetailView: View, Equatable {
    static func == (lhs: EventDetailView, rhs: EventDetailView) -> Bool { lhs.eventID == rhs.eventID }
    /// Без підписки на весь `AppModel`: деталі перемальовуються зі своїм `DetailScreenState`.
    @Environment(\.appModel) var appModel
    var model: AppModel { appModel! }
    @Environment(\.dismiss) var dismiss
    @StateObject var actions: EventActionsModel
    /// Стан екрана зі спільного `DetailPresenter`.
    @StateObject var screen: DetailScreenModel
    @State var editing = false
    /// Шит входу з причиною: підзаголовок каже, навіщо профіль саме зараз.
    @State var auth: AuthReason?
    @State var cancelling = false
    @State var reporting: ReportTarget?
    @State var blocking = false
    /// Попередження перед виходом у чужий чат: спершу кажемо, куди й хто це додав.
    @State var openingContact = false
    @State var photo: PhotosPickerItem?
    /// Зміщення стрічки, за яким їде обкладинка. Див. `reportsScrollOffset`. Класом, а не `@State CGFloat`: його
    /// читають лише обкладинка, смуга статусу й згасання назви, тож на кадр прокрутки перераховуються вони, а не весь екран.
    @State var scroll = DetailScroll()
    /// Верхній відступ safe area саме цієї стрічки. У стосі це смуга статусу, у шторці — майже
    /// нуль; число з вікна (`measuredStatusBarInset`) у шторці завищене на висоту смуги, і
    /// обкладинка стирчала з-під місця, відведеного їй у стрічці. Початкове значення — для
    /// першого кадру в стосі; далі уточнює `onGeometryChange`.
    @State var topInset: CGFloat = measuredStatusBarInset()
    /// Ростер розгорнуто кнопкою «Показати всіх».
    @State var showAllPeople = false
    /// Картка людини відкрита з цього екрана. Див. `personSheet`.
    @State var showingPerson = false
    /// «Ще в цьому місці» розгорнуто. Згорнуто за замовчуванням: це вихід з події, а не її частина.
    @State var showOthersHere = false
    /// Шторка «Шукаю компанію».
    @State var seekingCompany = false
    /// Системне «Поділитися» з готовим текстом: щойно створений супутник чи «Покликати».
    @State var sharing: ShareText?
    /// «Покликати» чекає посилання від сервера: повторний тап нічого не робить.
    @State var inviting = false
    /// «Купили? Стежитимемо за змінами» — після повернення від продавця (R9).
    @State var boughtPrompt = false
    /// Шторка часу збору (R7б): з якого часу почати — пропозиція R7а чи поточний.
    @State var movingMeet: MeetTarget?
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openMap) var openMap

    /// Id відкритої події від того, хто відкриває, а не зі стану: див. `.task` нижче.
    let eventID: String

    init(app: PoruchApp, eventID: String) {
        self.eventID = eventID
        _actions = StateObject(wrappedValue: EventActionsModel(app: app))
        _screen = StateObject(wrappedValue: DetailScreenModel(app: app, eventID: eventID))
    }

    var body: some View {
        let view = screen.state
        Group {
            if let event = view.event {
                detail(event, view)
            } else if !view.loading {
                // Сервер відповів порожньо або з помилкою: не вічний спінер, а вихід. Без мережі — корінець на ниточці:
                // подія відкриється сама, щойно мережа повернеться.
                VStack(spacing: Space.lg) {
                    if view.offline {
                        EmptyState(
                            glyph: PoruchIcons.wifiOff, title: Copy.offline_title, message: Copy.offline_event_hint,
                            animation: "Offline", actionLabel: Copy.try_again
                        ) { model.app.openEvent(id: eventID) }
                    } else {
                        EmptyState(
                            glyph: PoruchIcons.calendarAlert, title: Copy.err_event_unavailable,
                            message: Copy.event_unavailable_hint,
                            actionLabel: Copy.try_again
                        ) { model.app.openEvent(id: eventID) }
                    }
                    SecondaryButton(title: Copy.back) { dismiss() }
                }
                .padding(Space.page).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            } else {
                PoruchLoader().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            }
        }
        // Повернення поверх іншого екрана деталей: той перебрав єдиний слот відкритої події, просимо назад.
        .onAppear { screen.reopen() }
        .task(id: photo) { if let event = view.event { await actions.upload(photo, to: event) } }
        // У деталей власна нижня панель, таббар стояв би на ній.
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        // Вхід міняє акаунт і чистить відкриту подію: після шторки просимо її знову, інакше лишався б лоадер.
        .sheet(item: $auth, onDismiss: { screen.reopen() }) { reason in NavigationStack { AuthView(reason: reason) } }
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
        .onChange(of: view.createdCompanion) { _, created in
            guard let created, let event = view.event else { return }
            model.app.clearCreatedCompanion()
            sharing = ShareText(text: Copy.companion_share_text("\(event.title)", "\(eventDate(event))", EventLinks.shared.url(eventId: created)))
        }
        .sheet(item: $sharing) { share in ActivitySheet(items: [share.text]).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $seekingCompany) { if let event = view.event { CompanionSheet(event: event) } }
        .sheet(item: $movingMeet) { target in
            if let event = view.event, let parent = view.companionOf, let start = parent.startsAt {
                CompanionSheet(moving: event, parent: parent, startsAt: start, to: target.at)
            }
        }
        // Повернулись від продавця: спільний шар каже, чи питати «Купили?» (раз на подію, лише незбереженій).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.app.takeBoughtPrompt(eventId: screen.sessionID) else { return }
            withAnimation(.snappy) { boughtPrompt = true }
        }
        // Без відповіді за 10 с картка зникає сама: це питання, а не перешкода.
        .task(id: boughtPrompt) {
            guard boughtPrompt else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, boughtPrompt else { return }
            withAnimation(.snappy) { boughtPrompt = false }
            model.app.boughtPromptAnswered(saved: false)
        }
    }

    @ViewBuilder
    func detail(_ event: Event, _ view: DetailScreenState) -> some View {
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
                // Пише напряму в `scroll`, без `Binding(get:)`: геттер біндингу SwiftUI читав у тілі екрана, і кожен кадр
                // прокрутки знову перераховував увесь екран.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(detailScrollSpace)).minY } action: { scroll.offset = $0 }
            }
            .coordinateSpace(name: detailScrollSpace)
            .refreshable { await screen.refresh() }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
            // Єдиний шар обкладинки: від краю екрана, під смугою статусу. При потягу вниз
            // розтягується, при прокрутці їде вгору вдвічі повільніше за стрічку (паралакс);
            // сама стрічка лишається в safe area, щоб індикатор потягу було видно. Та сама афіша,
            // що й велика картка головної (`EventArt`): без фото — насичений градієнт категорії,
            // а не бліда пастель; низ темніє під білу назву.
            .background(alignment: .top) { HeroBackdrop(event: event, scroll: scroll) }
            // Коли аркуш доїхав до годинника, текст інакше йде під нього: смуга статусу набирає колір полотна.
            // Не раніше: світла смуга над темною обкладинкою відрізала б її, а з-під смуги визирали б кути аркуша.
            .overlay(alignment: .top) { StatusStrip(scroll: scroll, topInset: topInset) }
            VStack(spacing: Space.sm) {
                if boughtPrompt { boughtCard(event, view) }
                stickyBar(event, view)
            }
        }
        .background(Palette.canvas)
        // Тут, а не в корені: з мапи деталі відкриваються шторкою, і корінь лежав би під нею.
        .coachMarks([.companion, .invite], enabled: view.canSeekCompany || (view.canInvite && view.signedIn))
        .modifier(DetailSheets(event: event, view: view, editing: $editing, actions: actions))
        .modifier(DetailDialogs(event: event, view: view, openingContact: $openingContact, cancelling: $cancelling, blocking: $blocking, reporting: $reporting, actions: actions))
    }

    /// Секції під обкладинкою. Окремою функцією: в одному виразі компілятор не встигав вивести тип.
    @ViewBuilder
    func sections(_ event: Event, _ view: DetailScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if let pending = view.pendingMeet, let parent = view.companionOf { meetDecision(event, parent, pending, view) }
            if let room = view.room, room.hasAgeLimit || room.approvalRequired { restrictions(room) }
            if let parent = view.companionOf {
                NavigationLink(value: EventRoute(id: parent.id)) {
                    HStack(spacing: Space.md) {
                        PoruchIcon(glyph: PoruchIcons.social, size: 20).foregroundStyle(Palette.ink)
                            .frame(width: 40, height: 40).background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                        Text(Copy.companion_parent("\(TitleRules.shared.display(title: parent.title))")).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        Spacer(minLength: Space.sm)
                        PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
                    }
                    .padding(Space.lg).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(pressedScale: 1)).cardSurface()
                .accessibilityElement(children: .combine)
            }
            // Щось сталось — стан і продавці першими: по них сюди й прийшли.
            if let listing = view.listing, listing.needsAttention { tickets(event, listing, view) }
            externalActions(event, view)
            if view.sessions.count > 1 { sessionRail(event, view.sessions) }
            if !event.artists.isEmpty { lineup(event) }
            facts(event)
            if let listing = view.listing, !listing.needsAttention { tickets(event, listing, view) }
            if !view.companions.isEmpty && !view.cancelled { companionsSection(view) }
            if let room = view.room { people(room, view) }
            venue(event, view)
            if !view.cancelled && !view.ended { safety() }
            description(event)
            if !view.othersHere.isEmpty { othersHereSection(view.othersHere, placeName: event.placeName) }
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
            SectionHeader(title: Copy.description)
            Text(event.displayDescription).font(PoruchFont.lead).foregroundStyle(Palette.inkSecondary).lineSpacing(5)
        }
        if let url = sourceURL(event) {
            Link(Copy.listing_read_more, destination: url)
                .font(PoruchFont.button).foregroundStyle(Palette.brand)
        }
    }
}

/// Аркуші деталей: редактор, календар. Винесено з `detail`, щоб вираз лишався компільованим.
struct DetailSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    let event: Event
    let view: DetailScreenState
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
    let view: DetailScreenState
    @Binding var openingContact: Bool
    @Binding var cancelling: Bool
    @Binding var blocking: Bool
    @Binding var reporting: ReportTarget?
    @ObservedObject var actions: EventActionsModel

    func body(content: Content) -> some View {
        content
        .confirmationDialog(
            Copy.contact_confirm_body(view.contactURL.map { ContactRules.shared.host(url: $0.absoluteString) } ?? Copy.contact_unknown_site),
            isPresented: $openingContact, titleVisibility: .visible
        ) {
            Button(Copy.contact_confirm_open) { if let url = view.contactURL { UIApplication.shared.open(url) } }
        }
        .confirmationDialog(Copy.cancel_event_confirm, isPresented: $cancelling, titleVisibility: .visible) {
            Button(Copy.cancel_event, role: .destructive) { actions.cancel(event) }
        }
        .confirmationDialog(
            Copy.block_user_body,
            isPresented: $blocking, titleVisibility: .visible
        ) {
            Button(Copy.block_confirm, role: .destructive) {
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

/// Зміщення стрічки деталей. Його читають лише вигляди нижче, тож кадр прокрутки не перераховує секції й панель дії.
@Observable final class DetailScroll {
    var offset: CGFloat = 0
}

/// Єдиний шар обкладинки: від краю екрана, під смугою статусу. При потягу вниз розтягується, при прокрутці їде вгору
/// вдвічі повільніше за стрічку (паралакс; зі «зменшити рух» — разом зі стрічкою). Сама стрічка лишається в safe area,
/// щоб індикатор потягу було видно. Та сама афіша, що й велика картка головної (`EventArt`): без фото — насичений
/// градієнт категорії, а не бліда пастель; низ темніє під білу назву.
private struct HeroBackdrop: View {
    let event: Event
    let scroll: DetailScroll
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let offset = scroll.offset
        // `fill`: горизонтальне фото на 480 pt заввишки розпаковується з запасом за шириною, а не розтягується.
        EventArt(event: event, maxDimension: heroHeight, glyphSize: 260, glyphDrop: 120, fill: true)
            .frame(height: heroHeight + max(offset, 0)).frame(maxWidth: .infinity).clipped()
            .overlay(photoScrim)
            .offset(y: min(offset, 0) * (reduceMotion ? 1 : heroParallax))
            .ignoresSafeArea(edges: .top)
    }
}

/// Коли аркуш доїхав до годинника, текст інакше йде під нього: смуга статусу набирає колір полотна.
/// Не раніше: світла смуга над темною обкладинкою відрізала б її, а з-під смуги визирали б кути аркуша.
private struct StatusStrip: View {
    let scroll: DetailScroll
    let topInset: CGFloat
    var body: some View {
        Palette.canvas.frame(height: topInset).ignoresSafeArea(edges: .top)
            .opacity(min(max((-scroll.offset - (heroHeight - topInset - Corner.xl - scrimFade)) / scrimFade, 0), 1))
            .allowsHitTesting(false)
    }
}

/// Текст на обкладинці їде зі стрічкою й гасне, поки не дійшов до годинника. Окремим виглядом, а не модифікатором:
/// тіло модифікатора SwiftUI рахує разом із батьком, і зміщення знову перераховувало б увесь екран.
struct HeroTextFade<Content: View>: View {
    let scroll: DetailScroll
    @ViewBuilder let content: Content
    var body: some View {
        let scrolled = min(max(1 - (-scroll.offset - heroTextFadeFrom) / heroTextFade, 0), 1)
        // Скасування каже штамп над назвою; приглушена до 70 % біла назва на затемненні втрачала контраст.
        content.opacity(scrolled)
    }
}
