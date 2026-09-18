import SwiftUI
import Shared

/// «Мої події» — один список у трьох розрізах.
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
    /// Відкрити деталі. Шлях стосу тримає корінь (`RootView.minePath`).
    var openEvent: (String) -> Void
    @State private var tab = MyEventsTab.attending
    @State private var creating = false

    private var signedIn: Bool { model.state?.signedIn == true }

    /// «Збережені» з того ж списку: зберегти можна, не приєднуючись.
    private var visible: [Event] {
        guard let state = model.state else { return [] }
        return state.myEvents.filter { event in
            switch tab {
            case .attending: event.gathering?.joined == true
            case .organizing: state.organizes(event: event)
            // Набір із моделі, а не `isSaved` через міст: там лінійний пошук на кожен рядок.
            case .saved: model.savedIDs.contains(event.id)
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
        // Потяг ловлять стрічка й порожній стан нижче; гостю оновлювати нічого, і його екран не прокручується.
        .refreshable { await model.reloadMyEvents() }
        .sheet(isPresented: $creating) { EventEditor(event: nil, app: model.app, home: model.state) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Мої події").font(PoruchFont.display).displayTracking().foregroundStyle(Palette.ink)
                    Text(signedIn ? "Плани, власні зустрічі й збережене в одному місці" : "Увійдіть, щоб бачити свої плани")
                        .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: Space.sm)
                if signedIn { IconPill(symbol: "arrow.clockwise", label: "Оновити") { model.app.loadMyEvents() } }
            }.padding(.horizontal, Space.page)
            if signedIn {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        ForEach(MyEventsTab.allCases) { entry in
                            Chip(label: entry.title, selected: tab == entry) { tab = entry }
                        }
                    }
                }.railContentPadding(spread: 0)
            }
        }
        .padding(.top, Space.xl).padding(.bottom, Space.md)
    }

    @ViewBuilder private var content: some View {
        if !signedIn {
            EmptyState(
                symbol: "lock", title: "Увійдіть, щоб бачити свої події",
                message: "Зберігайте цікаве, приєднуйтесь і створюйте власні зустрічі."
            )
            Spacer()
        } else if visible.isEmpty {
            // У стрічці, щоб потяг мав за що зачепитись.
            ScrollView {
                EmptyState(
                    symbol: "calendar", title: "Тут з’являться ваші плани",
                    message: "Приєднуйтесь до подій або створіть власну — усе буде на цій вкладці."
                )
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    // Один груповий список компактних рядків: тут переглядають своє, а не обирають чуже.
                    GroupedRows {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { position, event in
                            Button { model.app.selectEvent(id: event.id); openEvent(event.id) } label: {
                                EventRow(event: event).padding(.horizontal, Space.lg)
                            }.buttonStyle(PressableStyle(pressedScale: 1))
                            if position < visible.count - 1 {
                                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 60 + Space.md)
                            }
                        }
                    }
                    GroupedRows {
                        LinkRow(symbol: "sparkles", title: "Маєте ідею зустрічі?", subtitle: "Опублікуйте подію за три кроки") { creating = true }
                    }
                }.padding(.horizontal, Space.page).padding(.vertical, Space.md)
            }
        }
    }
}
