import SwiftUI
import Shared

@main struct PoruchApplication: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).accentColor(Color(red: 0.12, green: 0.39, blue: 0.28)).tint(Color(red: 0.12, green: 0.39, blue: 0.28))
                .onOpenURL { model.app.handleAuthCallback(url: $0.absoluteString) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.start(); model.app.refresh() }
                    if phase == .background { model.stop() }
                }
        }
    }
}
struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabView {
            NavigationStack { DiscoveryView() }.tabItem { Label("Мапа", systemImage: "map") }
            NavigationStack { MyEventsView() }.tabItem { Label("Мої події", systemImage: "calendar") }
            NavigationStack { ProfileView() }.tabItem { Label("Профіль", systemImage: "person.crop.circle") }
        }
        .sheet(isPresented: Binding(get: { model.state?.passwordRecovery == true }, set: { _ in })) { NavigationStack { ProfileView() } }
        .alert("Поруч", isPresented: Binding(get: { model.state?.message != nil }, set: { if !$0 { model.app.clearMessage() } })) {
            Button("Зрозуміло") { model.app.clearMessage() }
        } message: { Text(model.state?.message ?? "") }
    }
}
struct EventRow: View {
    let event: Event
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: categories.first { $0.0 == event.category }?.2 ?? "mappin").font(.title2).foregroundStyle(.tint).frame(width: 52, height: 58).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(categoryName(event.category).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(event.title).font(.headline)
                Text(eventDate(event)).font(.subheadline).foregroundStyle(.secondary)
                Text(event.status == "cancelled" ? "Подію скасовано" : "\(max(0, event.capacity - event.attendeeCount)) вільних місць").font(.caption)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}
