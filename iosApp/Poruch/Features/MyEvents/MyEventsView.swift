import SwiftUI
import Shared

/// «Мої події» is one list under three lenses.
enum MyEventsTab: Int, CaseIterable, Identifiable {
    case attending, organizing, saved
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .attending: "Відвідую"
        case .organizing: "Організовую"
        case .saved: "Збережені"
        }
    }
}

struct MyEventsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = MyEventsTab.attending
    @State private var detail = false
    @State private var creating = false

    private var signedIn: Bool { model.state?.signedIn == true }

    /// «Saved» draws on the same list: an event can be saved without being joined or organised.
    private var visible: [Event] {
        guard let state = model.state else { return [] }
        return state.myEvents.filter { event in
            switch tab {
            case .attending: event.joined
            case .organizing: state.organizes(event: event)
            case .saved: state.isSaved(id: event.id)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task { model.app.loadMyEvents() }
        .refreshable { model.app.loadMyEvents() }
        .navigationDestination(isPresented: $detail) { EventDetailView(app: model.app) }
        .sheet(isPresented: $creating) { EventEditor(event: nil, app: model.app, home: model.state) }
    }

    private var header: some View {
        VStack(spacing: Space.sm) {
            PageHeader(title: "Мої події") {
                IconPill(symbol: "arrow.clockwise", label: "Оновити") { model.app.loadMyEvents() }
            }
            if signedIn {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        ForEach(MyEventsTab.allCases) { entry in
                            Chip(label: entry.title, selected: tab == entry) { tab = entry }
                        }
                    }.padding(.horizontal, Space.page)
                }
            }
        }
        .padding(.bottom, Space.md)
        .background(LinearGradient(colors: [Palette.canvasTint, Palette.canvas], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder private var content: some View {
        if !signedIn {
            EmptyState(
                symbol: "lock", title: "Увійдіть, щоб бачити свої події",
                message: "Зберігайте цікаве, приєднуйтесь і створюйте власні зустрічі."
            )
            Spacer()
        } else if visible.isEmpty {
            EmptyState(
                symbol: "calendar", title: "Тут з’являться ваші плани",
                message: "Приєднуйтесь до подій або створіть власну — усе буде на цій вкладці."
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: Space.lg) {
                    BannerCard(title: "Маєте ідею зустрічі?", subtitle: "Опублікуйте подію за три кроки") { creating = true }
                    ForEach(visible, id: \.id) { event in
                        EventCard(
                            event: event,
                            saved: model.state?.isSaved(id: event.id) == true,
                            waitlisted: model.state?.isWaitlisted(id: event.id) == true
                        ) {
                            model.app.selectEvent(id: event.id); detail = true
                        }
                    }
                }.padding(.horizontal, Space.page).padding(.vertical, Space.md)
            }
        }
    }
}
