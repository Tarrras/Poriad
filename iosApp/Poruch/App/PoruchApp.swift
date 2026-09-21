import SwiftUI
import Shared
import FirebaseCore
import FirebaseAnalytics

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
    /// Стартове місто — те, де людина зараз, а не Київ за замовчуванням. Відмову мовчки приймаємо.
    @StateObject private var location = LocationFinder()
    var body: some View {
        // Онбординг замінює застосунок, а не накриває: за ним на першому запуску ще нічого нема.
        if model.state?.needsOnboarding == true {
            OnboardingView()
        } else {
            app
                .onAppear { location.request() }
                .onReceive(location.$city) { city in
                    if let city { model.app.selectCity(city: city) }
                }
        }
    }

    /// Мапа з деталей: стоси скидаємо самі. `dismiss()` у ту ж мить, що й зміна вкладки, SwiftUI
    /// пропускав, деталі лишались у стосі головної, а їхній `hidesTabBar()` ховав таббар і на мапі.
    private func showMap() {
        homePath = NavigationPath()
        minePath = NavigationPath()
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
                NavigationStack { DiscoveryView().toolbar(.hidden, for: .tabBar) }.tag(1)
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
                .padding(.bottom, Space.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tabBarHidden)
        .onAppear {
            // Тап по сповіщенню веде на подію зі стеку головної.
            PushDelegate.openEvent = { id in tab = 0; model.app.selectEvent(id: id); homePath = NavigationPath([EventRoute(id: id)]) }
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
