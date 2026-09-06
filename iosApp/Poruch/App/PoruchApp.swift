import SwiftUI
import Shared

@main struct PoruchApplication: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).tint(Palette.brand)
                .onOpenURL { model.app.handleAuthCallback(url: $0.absoluteString) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.start(); model.app.refresh() }
                    if phase == .background { model.stop() }
                }
        }
    }
}

private let tabItems = [
    TabItem(id: 0, label: "Головна", glyph: PoruchIcons.home),
    TabItem(id: 1, label: "Мапа", glyph: PoruchIcons.map),
    TabItem(id: 2, label: "Мої події", glyph: PoruchIcons.calendar),
    TabItem(id: 3, label: "Профіль", glyph: PoruchIcons.person)
]

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0
    @State private var creating = false
    @State private var authenticating = false
    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.canvas.ignoresSafeArea()
            TabView(selection: $tab) {
                NavigationStack {
                    HomeView(
                        openMap: { tab = 1 }, openProfile: { tab = 3 },
                        createEvent: { if model.state?.userId == nil { authenticating = true } else { creating = true } }
                    )
                    .safeAreaPadding(.bottom, 92)
                    .toolbar(.hidden, for: .tabBar)
                }.tag(0)
                NavigationStack { DiscoveryView().toolbar(.hidden, for: .tabBar) }.tag(1)
                NavigationStack { MyEventsView().safeAreaPadding(.bottom, 92).toolbar(.hidden, for: .tabBar) }.tag(2)
                NavigationStack { ProfileView().safeAreaPadding(.bottom, 92).toolbar(.hidden, for: .tabBar) }.tag(3)
            }.toolbar(.hidden, for: .tabBar)
            PoruchTabBar(items: tabItems, selection: $tab) {
                CreateButton { if model.state?.userId == nil { authenticating = true } else { creating = true } }
            }.padding(.bottom, Space.sm)
        }
        .sheet(isPresented: $creating) { EventEditor(event: nil, app: model.app, home: model.state) }
        .sheet(isPresented: $authenticating) {
            NavigationStack {
                AuthView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { authenticating = false } } }
            }
        }
        .sheet(isPresented: Binding(get: { model.state?.passwordRecovery == true }, set: { _ in })) { NavigationStack { ProfileView() } }
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
    }
}
