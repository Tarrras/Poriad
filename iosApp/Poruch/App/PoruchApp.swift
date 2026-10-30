import SwiftUI
import Shared
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics
import StoreKit
import GoogleSignIn

@main struct PoruchApplication: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Єдиний системний заголовок у застосунку — «Знайти місто» у шторці міст (`navigationTitle`): і він голосом квитка,
        // як решта заголовків. Кегль росте з Dynamic Type, як у `PoruchFont.brand*`.
        if let display = UIFont(name: "SofiaSansCondensed-ExtraBold", size: 38) {
            UINavigationBar.appearance().largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: display), .kern: -0.4
            ]
        }
        // Analytics і Crashlytics. Без GoogleService-Info.plist (збірка без ключів) Firebase не піднімаємо.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            // Продуктові події зі спільного коду → Firebase. Словник — docs/analytics.md.
            PoruchAnalytics.shared.sink = { name, params in Analytics.logEvent(name, parameters: params) }
            // Збої бізнес-логіки → Crashlytics non-fatal, з кроками перед ними. NSError групується за
            // domain, тож назва проблеми йде туди; текст — лише безпечний підсумок винятку.
            let crashlytics = Crashlytics.crashlytics()
            PoruchLog.shared.breadcrumbs = { crashlytics.log($0) }
            PoruchLog.shared.reporter = { issue, error in
                crashlytics.record(error: NSError(domain: issue, code: 0, userInfo: error.map { [NSLocalizedDescriptionKey: $0.summary()] }))
            }
            // Перемикач «Аналітика» в профілі: і події, і звіти про збої. Хук кличеться одразу з поточним
            // значенням, а спільний шар ставить збережене до першої події.
            PoruchAnalytics.shared.collection = { enabled in
                Analytics.setAnalyticsCollectionEnabled(enabled.boolValue)
                crashlytics.setCrashlyticsCollectionEnabled(enabled.boolValue)
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).environment(\.appModel, model).tint(Palette.brand)
                .overlay { SplashView() }
                // Сюди приходять і auth-колбек, і посилання на подію: Universal Link `poriad.app/e/…` та
                // `poriad://event/…` з кнопки веб-сторінки. Подію відкриваємо тим самим шляхом, що й тап по пушу.
                .onOpenURL { url in
                    // Файл квитка з «Поділитися» чи «Відкрити в…» (docs/ticket-wallet.md): копіюємо, читаємо, питаємо.
                    if url.isFileURL {
                        TicketFiles.intake(model) { await TicketFiles.load(url, app: model.app, origin: "share") }
                        return
                    }
                    // Повернення з вікна входу Google — його URL-схема, не наша.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if let id = EventLinks.shared.eventId(link: url.absoluteString) {
                        model.app.eventLinkOpened(link: url.absoluteString)
                        PushDelegate.open(eventId: id, chat: false)
                    } else {
                        model.app.handleAuthCallback(url: url.absoluteString)
                    }
                }
                .onAppear { PushDelegate.app = model.app }
                .onChange(of: scenePhase) { _, phase in
                    // Повернення в застосунок: запити на участь і членство могли змінитися, поки його не було.
                    if phase == .active {
                        model.start(); model.app.resume(); LocalReminderScheduler.shared.reschedule(); PushDelegate.reportPermission()
                    }
                    if phase == .background { model.stop() }
                }
        }
    }
}

/// Сплеш поверх застосунку, що вже вантажиться під ним: на диску мапи спливають події, у центр падає
/// шпилька з іконки, під нею зʼявляються назва й обіцянка. Системний екран запуску — те саме полотно.
private struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var done = false
    @State private var titled = false
    var body: some View {
        if !done, !reduceMotion {
            ZStack {
                Palette.canvas.ignoresSafeArea()
                BrandAnimation(name: "Splash", loop: false, onFinish: finish).frame(width: 280, height: 280)
                    // Назва висить під мапою, а не стоїть з нею в стовпці: так мапа точно в центрі екрана,
                    // і виліт у місто йде з неї. Приходить, коли шпилька торкається землі.
                    .overlay(alignment: .bottom) {
                        VStack(spacing: Space.xs) {
                            Text(Copy.brand_name).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                            Text(Copy.tagline).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        }
                        .fixedSize()
                        .alignmentGuide(.bottom) { $0[.top] - Space.xs }
                        .opacity(titled ? 1 : 0).offset(y: titled ? 0 : 8)
                    }
            }
            // Вихід — наліт на мапу: сплеш росте з центру й розчиняється в головній.
            .transition(.asymmetric(insertion: .identity, removal: .scale(scale: 2.4).combined(with: .opacity)))
            .task {
                try? await Task.sleep(for: .milliseconds(950))
                withAnimation(.easeOut(duration: 0.4)) { titled = true }
                // Страховка: анімація не завантажилась чи не відіграла — не тримаємо людину на сплеші.
                try? await Task.sleep(for: .seconds(2.5))
                finish()
            }
        }
    }

    private func finish() { withAnimation(.easeIn(duration: 0.45)) { done = true } }
}

/// Чати з непрочитаним і запити на участь живуть у «Моїх подіях»: туди й бейдж, по одному на подію.
/// Нове в підписках — крапкою на «Профілі»: звідти відкривається «Ви стежите».
private func tabItems(waiting: Int, newFollows: Bool) -> [TabItem] {
    [
        TabItem(id: 0, label: Copy.home, glyph: PoruchIcons.home),
        TabItem(id: 1, label: Copy.map, glyph: PoruchIcons.map, tip: .map),
        TabItem(id: 2, label: Copy.my_events, glyph: PoruchIcons.calendar, badge: waiting),
        TabItem(id: 3, label: Copy.profile, glyph: PoruchIcons.person, dot: newFollows)
    ]
}

/// Що показує шит входу: причина, з якою гість до нього прийшов.
struct AuthSheet: Identifiable {
    let id = UUID()
    let reason: AuthReason
}

struct RootView: View {
    /// Без підписки на весь `AppModel`: корінь перераховується зі свого зрізу `RootScreenModel`.
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    private var root: RootScreenModel { model.root }
    @State private var tab = 0
    @State private var creating = false
    /// Шит входу. Причину віддаємо разом із ним, а не окремим станом: тоді екран входу отримує її в мить показу.
    @State private var authSheet: AuthSheet?
    /// Гість тапнув «Створити»: після входу редактор відкривається сам, а не лишає людину на головній.
    @State private var createAfterAuth = false
    /// Екран, що заявив `hidesTabBar()`, зараз це деталі події.
    @State private var tabBarHidden = false
    /// Явні шляхи стосів замість `navigationDestination(isPresented:)`: після `dismiss()` SwiftUI
    /// не завжди скидав біндінг, і наступний тап по картці відкривав попередню або нічого.
    @State private var homePath = NavigationPath()
    @State private var minePath = NavigationPath()
    @State private var profilePath = NavigationPath()
    /// Стек мапи (артист → подія) теж явний: «На мапі» з його деталей і пуш мають його скинути, інакше
    /// деталі лишались зверху, а їхній `hidesTabBar()` ховав таббар.
    @State private var mapPath = NavigationPath()
    /// Лічильник переходів на мапу: мапа по ньому закриває свої шторки, щоб показати вибрану подію.
    @State private var mapToken = 0
    /// Стартове місто — те, де людина зараз, а не Київ за замовчуванням. Відмову мовчки приймаємо.
    @StateObject private var location = LocationFinder()
    /// Мʼяке питання про дайджест вихідних, див. `DigestPrompt`.
    @State private var digestAsk = false
    /// Стос «Ваш тиждень» (docs/return-hooks.md): раз, у першій сесії після онбордингу, до туру.
    @AppStorage("poruch.deckDone") private var deckDone = false
    @State private var deck: DeckCards?
    /// Людина натиснула кнопку в листі дайджесту; змах униз без відповіді рахуємо як «не зараз».
    @State private var digestAnswered = false
    /// Перший-другий запуск: лише новим показуємо, де що на головній (docs/coach-marks.md). Лічильник рахує
    /// `DigestPrompt` уже після цього читання, тож на першому запуску тут 0.
    @State private var newcomer = UserDefaults.standard.integer(forKey: "poruch.launches") < 2
    @Environment(\.requestReview) private var requestReview
    /// Простір морфа «квиток → екран»: квитки головної й гаманця та їхні екрани в різних гілках (`morphSource`).
    @Namespace private var morph
    var body: some View {
        // Онбординг замінює застосунок, а не накриває: за ним на першому запуску ще нічого нема.
        // Поки стану нема, невідомо, чи потрібен онбординг: нейтральне полотно, без запиту геолокації.
        if root.ready {
            if root.needsOnboarding {
                OnboardingView()
            } else {
                app
                    // Геолокацію питаємо, лише коли онбординг позаду: не поверх його першого екрана. Нового ще й
                    // спершу вітаємо туром по головній, а питаємо після нього (`.coachMarks`, `onFinish`).
                    .onAppear { if !(newcomer && location.undecided) { location.request() } }
                    .task { digestAsk = await DigestPrompt.due(digestEnabled: root.digestEnabled) }
                    // Видача їде паралельно з онбордингом; за секунду її вже досить. Не встигла — стосу нема, лишається
                    // рядок на головній. ponytail: одна перевірка, а не очікування видачі.
                    .task {
                        guard newcomer, !deckDone else { return }
                        try? await Task.sleep(for: .seconds(1))
                        deckDone = true
                        let cards = model.app.deckCards()
                        guard cards.count >= Int(DeckRules.shared.MIN) else { return }
                        UserDefaults.standard.set(model.app.deckWeek(), forKey: "poruch.deckWeek")
                        deck = DeckCards(events: cards)
                    }
                    .fullScreenCover(item: $deck) { DeckView(cards: $0.events) { deck = nil } }
                    // Перша підписка за запуск: питаємо про сповіщення, без них пуші про нове не дійдуть.
                    .onChange(of: root.followsMade) { _, made in if made > 0 { FollowPrompt.ask() } }
                    // Перша закладка, і гостя теж: нагадування напередодні без дозволу не прийде (docs/guest-saves.md).
                    // У стосі «Ваш тиждень» про сповіщення питає його кінець, а не перша закладка.
                    .onChange(of: root.savesMade) { _, made in if made > 0 && deck == nil { ReminderPrompt.offer(model.app) } }
                    .onChange(of: root.reviewMoment) { _, moment in
                        guard moment else { return }
                        let due = ReviewPrompt.due()
                        model.app.reviewMomentHandled(prompted: due)
                        // Шторка оцінки ще закривається: вікно поверх анімації iOS мовчки пропускає.
                        if due { Task { try? await Task.sleep(for: .seconds(1)); requestReview() } }
                    }
                    // Лист знизу, не `alert`: усі питання в застосунку ставляться листом (DS, «Нижні листи»).
                    .sheet(isPresented: $digestAsk, onDismiss: { if !digestAnswered { model.app.digestPromptAnswered(granted: false, from: nil) } }) {
                        let weekdays = model.state.map { DigestRules.shared.weekdaysOnly(times: $0.taste.times) } ?? false
                        PromptSheet(
                            title: weekdays ? Copy.digest_prompt_weekdays_title : Copy.digest_prompt_title,
                            message: weekdays ? Copy.digest_prompt_weekdays_body : Copy.digest_prompt_body,
                            primary: Copy.digest_prompt_yes, secondary: Copy.digest_prompt_no,
                            onPrimary: {
                                digestAnswered = true
                                NotificationPermission.request { granted in
                                    model.app.digestPromptAnswered(granted: granted, from: nil)
                                    if granted { PushDelegate.registerIfAllowed() }
                                }
                            },
                            onSecondary: { digestAnswered = true; model.app.digestPromptAnswered(granted: false, from: nil) }
                        )
                    }
                    .onReceive(location.$city) { city in
                        if let city { model.app.locatedCity(city: city) }
                    }
            }
        } else {
            Palette.canvas.ignoresSafeArea()
        }
    }

    /// Мапа з деталей: стоси скидаємо самі. `dismiss()` у ту ж мить, що й зміна вкладки, SwiftUI
    /// пропускав, деталі лишались у стосі головної, а їхній `hidesTabBar()` ховав таббар і на мапі.
    private func showMap() {
        homePath = NavigationPath()
        minePath = NavigationPath()
        profilePath = NavigationPath()
        mapPath = NavigationPath()
        mapToken += 1
        tab = 1
    }

    /// Повторний тап «Головна»: з деталей — на корінь, на корені — вгору стрічки.
    private func reselectTab(_ tab: Int) {
        guard tab == 0 else { return }
        if homePath.isEmpty { NotificationCenter.default.post(name: .homeScrollToTop, object: nil) } else { homePath = NavigationPath() }
    }

    /// Тап по «Створити»: рахуємо його разом зі входом, з якого місця він був, — гостя далі чекає реєстрація.
    private func startCreating(from: String) {
        model.app.createStarted(from: from)
        if !root.signedIn { createAfterAuth = true; authSheet = AuthSheet(reason: .create) } else { creating = true }
    }

    /// Шит входу закрився: якщо людина тепер увійшла, її створення не губимо — відкриваємо редактор. Закрила без входу — нічого.
    private func continueCreating() {
        let signedIn = root.signedIn
        let go = createAfterAuth && signedIn
        createAfterAuth = false
        if go { creating = true }
    }

    private var app: some View {
        ZStack(alignment: .bottom) {
            Palette.canvas.ignoresSafeArea()
            TabView(selection: $tab) {
                NavigationStack(path: $homePath) {
                    HomeView(
                        openMap: showMap, openProfile: { tab = 3 }, openMyEvents: { tab = 2 },
                        createEvent: { startCreating(from: $0) },
                        openEvent: { homePath.append(EventRoute(id: $0, morph: $1)) },
                        openChat: { homePath.append(ChatRoute(id: $0.id)) },
                        openFollows: { homePath.append(FollowsRoute()) }
                    )
                    .equatable()
                    .safeAreaPadding(.bottom, 92)
                    .toolbar(.hidden, for: .tabBar)
                    // Пуш і посилання ставлять нову подію в той самий слот стосу (див. `PushDelegate.openEvent`):
                    // без `.id` SwiftUI лишав екран попередньої з її станом — датами прокату, чатом, запитом деталей.
                    .navigationDestination(for: EventRoute.self) { EventScreen(route: $0) }
                    .navigationDestination(for: ChatRoute.self) { ChatView(eventID: $0.id).id($0.id) }
                    .navigationDestination(for: FollowsRoute.self) { _ in FollowsView() }
                    .navigationDestination(for: ArtistRoute.self) { ArtistView(route: $0) }
                }.tag(0)
                // Артист з пошуку мапи відкривається стеком; його події, у свою чергу, — деталями.
                NavigationStack(path: $mapPath) {
                    DiscoveryView(openToken: mapToken, createEvent: { startCreating(from: $0) }).equatable().toolbar(.hidden, for: .tabBar)
                        .navigationDestination(for: ArtistRoute.self) { ArtistView(route: $0) }
                        .navigationDestination(for: EventRoute.self) { EventScreen(route: $0) }
                }.tag(1)
                NavigationStack(path: $minePath) {
                    MyEventsView(openEvent: { minePath.append(EventRoute(id: $0, morph: $1)) }, openChat: { minePath.append(ChatRoute(id: $0)) })
                        .equatable()
                        .safeAreaPadding(.bottom, 92).toolbar(.hidden, for: .tabBar)
                        .navigationDestination(for: EventRoute.self) { EventScreen(route: $0) }
                        .navigationDestination(for: ChatRoute.self) { ChatView(eventID: $0.id) }
                        .navigationDestination(for: ArtistRoute.self) { ArtistView(route: $0) }
                }.tag(2)
                NavigationStack(path: $profilePath) {
                    ProfileView(
                        openFollows: { profilePath.append(FollowsRoute()) }, openPlaces: { profilePath.append(PlacesRoute()) },
                        createEvent: { startCreating(from: "profile") }
                    )
                        .safeAreaPadding(.bottom, 92).toolbar(.hidden, for: .tabBar)
                        .navigationDestination(for: FollowsRoute.self) { _ in FollowsView() }
                        .navigationDestination(for: PlacesRoute.self) { _ in MyPlacesView() }
                        .navigationDestination(for: ArtistRoute.self) { ArtistView(route: $0) }
                        .navigationDestination(for: EventRoute.self) { EventScreen(route: $0) }
                }.tag(3)
            }
            .toolbar(.hidden, for: .tabBar)
            .onPreferenceChange(HidesTabBarKey.self) { hidden in tabBarHidden = hidden }
            if !tabBarHidden {
                PoruchTabBar(items: tabItems(waiting: root.waitingEvents, newFollows: root.newFollows), selection: $tab, reselect: reselectTab) {
                    CreateButton { startCreating(from: "fab") }.coachTarget(.create)
                }
                // Як системний таббар: підписи не ростуть з Dynamic Type, інакше чотири вкладки не вміщаються.
                .dynamicTypeSize(...DynamicTypeSize.large)
                .padding(.bottom, Space.sm)
                // Як системний таббар: лишається під клавіатурою, а не спливає над нею й не закриває результати пошуку.
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .motion(value: tabBarHidden)
        // Лише на корені головної й не разом з іншим питанням: пуш чи посилання, що відкрили подію, ставлять тур
        // на паузу, а лист дайджесту (другий запуск) чи вхід — відкладають, поки людина не відповість.
        .coachMarks(
            [.city, .map, .create],
            enabled: newcomer && tab == 0 && homePath.isEmpty && !tabBarHidden && !digestAsk && deck == nil && authSheet == nil && !creating
        ) {
            // Тур пройдено чи пропущено: тепер питання про геолокацію. Пауза — щоб системне вікно не наклалось на згасання.
            guard location.undecided else { return }
            Task { try? await Task.sleep(for: .milliseconds(400)); location.request() }
        }
        .onAppear {
            // Тап по сповіщенню веде на подію (або в її чат) зі стеку головної, поверх усього, що було відкрите.
            // Без події, але із закладом — пуш про кілька його нових подій: мапа на його стосі.
            // Без події й закладу, але з артистом — пуш про кілька його нових подій: екран артиста поверх головної.
            // Без нічого — дайджест вихідних: лише головна.
            PushDelegate.openEvent = { id, chat, placeId, artistId in
                creating = false
                authSheet = nil
                dismissPresentedSheets()
                tab = 0
                minePath = NavigationPath()
                profilePath = NavigationPath()
                mapPath = NavigationPath()
                // Шторка деталей на мапі має свій SwiftUI-прапорець: мапа скидає його по токену, UIKit-закриття вище його не чіпає.
                mapToken += 1
                if id == nil, let placeId { showMap(); model.app.openPlace(placeId: placeId); return }
                // Нагадування про квиток за годину: сам квиток на весь екран, а не подія.
                if let id, id.hasPrefix(ReminderRules.shared.TICKET_PREFIX) {
                    root.shownTicket = TicketRoute(id: String(id.dropFirst(ReminderRules.shared.TICKET_PREFIX.count)))
                    return
                }
                if id == nil, let artistId {
                    var path = NavigationPath()
                    path.append(ArtistRoute(id: artistId))
                    homePath = path
                    return
                }
                guard let id else { homePath = NavigationPath(); return }
                model.app.selectEvent(id: id)
                var path = NavigationPath()
                if chat { path.append(ChatRoute(id: id)) } else { path.append(EventRoute(id: id)) }
                homePath = path
            }
        }
        .environment(\.openMap, showMap)
        .environment(\.morphSpace, morph)
        .sheet(isPresented: $creating) { EventEditor(event: nil, app: model.app, home: model.state) }
        .sheet(item: $authSheet, onDismiss: continueCreating) { sheet in
            NavigationStack { AuthView(reason: sheet.reason) }
        }
        .sheet(isPresented: Binding(get: { root.passwordRecovery }, set: { _ in })) { NewPasswordView() }
        .sheet(
            item: Binding(get: { root.ticketIntake }, set: { root.ticketIntake = $0 }),
            onDismiss: { if let next = root.ticketNext { root.ticketNext = nil; root.shownTicket = next } }
        ) { TicketIntakeSheet(intake: $0) }
        .onChange(of: root.ticketAdded) { _, added in
            guard added else { return }
            tab = 2
            minePath = NavigationPath()
        }
        .fullScreenCover(item: Binding(get: { root.shownTicket }, set: { root.shownTicket = $0 })) {
            TicketViewer(ticketID: $0.id, invite: $0.invite).morphDestination($0.morph, in: morph)
        }
        .notice(root.notice?.presented) { model.app.clearNotice() }
    }
}

/// Шторки з будь-якої вкладки (редактор у «Моїх», скарга в деталях): SwiftUI-прапорці в кожної свої,
/// тож закриваємо все, що показує корінь вікна.
@MainActor private func dismissPresentedSheets() {
    let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
    root?.presentedViewController?.dismiss(animated: false)
}

/// Свайп «назад» від лівого краю живий і там, де системну панель сховано (`.toolbar(.hidden)`,
/// `navigationBarBackButtonHidden`): UIKit вимикає жест разом із панеллю, а тоді з деталей, артиста, чату
/// й «Ви стежите» можна вийти лише кнопкою. На корені стосу жест не починається.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
