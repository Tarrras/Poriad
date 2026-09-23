import SwiftUI
import Shared
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

@main struct PoruchApplication: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Analytics і Crashlytics. Без GoogleService-Info.plist (збірка без ключів) Firebase не піднімаємо.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            // Продуктові події зі спільного коду → Firebase. Словник — docs/analytics.md.
            PoruchAnalytics.shared.sink = { name, params in Analytics.logEvent(name, parameters: params) }
            // Перемикач «Аналітика» в профілі: і події, і звіти про збої. Хук кличеться одразу з поточним
            // значенням, а спільний шар ставить збережене до першої події.
            PoruchAnalytics.shared.collection = { enabled in
                Analytics.setAnalyticsCollectionEnabled(enabled.boolValue)
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled.boolValue)
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).tint(Palette.brand)
                .onOpenURL { model.app.handleAuthCallback(url: $0.absoluteString) }
                .onAppear { PushDelegate.app = model.app }
                .onChange(of: scenePhase) { _, phase in
                    // Повернення в застосунок: запити на участь і членство могли змінитися, поки його не було.
                    if phase == .active { model.start(); model.app.resume() }
                    if phase == .background { model.stop() }
                }
        }
    }
}

/// Непрочитані чати живуть у «Моїх подіях»: туди й бейдж.
private func tabItems(unreadChats: Int) -> [TabItem] {
    [
        TabItem(id: 0, label: "Головна", glyph: PoruchIcons.home),
        TabItem(id: 1, label: "Мапа", glyph: PoruchIcons.map),
        TabItem(id: 2, label: "Мої події", glyph: PoruchIcons.calendar, badge: unreadChats),
        TabItem(id: 3, label: "Профіль", glyph: PoruchIcons.person)
    ]
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0
    @State private var creating = false
    @State private var authenticating = false
    /// Екран, що заявив `hidesTabBar()`, зараз це деталі події.
    @State private var tabBarHidden = false
    /// Явні шляхи стосів замість `navigationDestination(isPresented:)`: після `dismiss()` SwiftUI
    /// не завжди скидав біндінг, і наступний тап по картці відкривав попередню або нічого.
    @State private var homePath = NavigationPath()
    @State private var minePath = NavigationPath()
    /// Лічильник переходів на мапу: мапа по ньому закриває свої шторки, щоб показати вибрану подію.
    @State private var mapToken = 0
    /// Стартове місто — те, де людина зараз, а не Київ за замовчуванням. Відмову мовчки приймаємо.
    @StateObject private var location = LocationFinder()
    var body: some View {
        // Онбординг замінює застосунок, а не накриває: за ним на першому запуску ще нічого нема.
        // Поки стану нема, невідомо, чи потрібен онбординг: нейтральне полотно, без запиту геолокації.
        if let state = model.state {
            if state.needsOnboarding {
                OnboardingView()
            } else {
                app
                    // Геолокацію питаємо, лише коли онбординг позаду: не поверх його першого екрана.
                    .onAppear { location.request() }
                    .onReceive(location.$city) { city in
                        if let city { model.app.selectCity(city: city) }
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
        mapToken += 1
        tab = 1
    }

    private var app: some View {
        ZStack(alignment: .bottom) {
            Palette.canvas.ignoresSafeArea()
            TabView(selection: $tab) {
                NavigationStack(path: $homePath) {
                    HomeView(
                        openMap: showMap, openProfile: { tab = 3 },
                        createEvent: { if model.state?.session.userId == nil { authenticating = true } else { creating = true } },
                        openEvent: { homePath.append(EventRoute(id: $0)) },
                        openChat: { homePath.append(ChatRoute(id: $0.id)) }
                    )
                    .safeAreaPadding(.bottom, 92)
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: EventRoute.self) { EventDetailView(app: model.app, eventID: $0.id) }
                    .navigationDestination(for: ChatRoute.self) { ChatView(eventID: $0.id) }
                }.tag(0)
                NavigationStack { DiscoveryView(openToken: mapToken).toolbar(.hidden, for: .tabBar) }.tag(1)
                NavigationStack(path: $minePath) {
                    MyEventsView(openEvent: { minePath.append(EventRoute(id: $0)) })
                        .safeAreaPadding(.bottom, 92).toolbar(.hidden, for: .tabBar)
                        .navigationDestination(for: EventRoute.self) { EventDetailView(app: model.app, eventID: $0.id) }
                        .navigationDestination(for: ChatRoute.self) { ChatView(eventID: $0.id) }
                }.tag(2)
                NavigationStack { ProfileView().safeAreaPadding(.bottom, 92).toolbar(.hidden, for: .tabBar) }.tag(3)
            }
            .toolbar(.hidden, for: .tabBar)
            .onPreferenceChange(HidesTabBarKey.self) { hidden in tabBarHidden = hidden }
            if !tabBarHidden {
                PoruchTabBar(items: tabItems(unreadChats: Int(model.state?.unreadChats ?? 0)), selection: $tab) {
                    CreateButton { if model.state?.session.userId == nil { authenticating = true } else { creating = true } }
                }
                // Як системний таббар: підписи не ростуть з Dynamic Type, інакше чотири вкладки не вміщаються.
                .dynamicTypeSize(...DynamicTypeSize.large)
                .padding(.bottom, Space.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tabBarHidden)
        .onAppear {
            // Тап по сповіщенню веде на подію (або в її чат) зі стеку головної, поверх усього, що було відкрите.
            PushDelegate.openEvent = { id, chat in
                creating = false
                authenticating = false
                dismissPresentedSheets()
                tab = 0
                model.app.selectEvent(id: id)
                var path = NavigationPath()
                if chat { path.append(ChatRoute(id: id)) } else { path.append(EventRoute(id: id)) }
                homePath = path
                minePath = NavigationPath()
            }
        }
        .environment(\.openMap, showMap)
        .sheet(isPresented: $creating) { EventEditor(event: nil, app: model.app, home: model.state) }
        .sheet(isPresented: $authenticating) {
            NavigationStack {
                AuthView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { authenticating = false } } }
            }
        }
        .sheet(isPresented: Binding(get: { model.state?.session.passwordRecovery == true }, set: { _ in })) { NewPasswordView() }
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
    }
}

/// Шторки з будь-якої вкладки (редактор у «Моїх», скарга в деталях): SwiftUI-прапорці в кожної свої,
/// тож закриваємо все, що показує корінь вікна.
@MainActor private func dismissPresentedSheets() {
    let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
    root?.presentedViewController?.dismiss(animated: false)
}
