import SwiftUI
import Shared

/// The date filters the map offers, in the order they are shown. Both the chip row and the filter
/// sheet read this list, so the two can never drift apart.
var dateFilterKeys: [String] { [DateFilter.shared.ANY, DateFilter.shared.TODAY, DateFilter.shared.WEEKEND] }

func dateLabel(_ key: String) -> String {
    switch key {
    case DateFilter.shared.TODAY: "Сьогодні"
    case DateFilter.shared.WEEKEND: "Вихідні"
    default: "Будь-коли"
    }
}

private let topControlsInset: CGFloat = 196
private let carouselInset: CGFloat = 268
private let tabBarInset: CGFloat = 92

struct DiscoveryView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var location = LocationFinder()
    @State private var citySearch = false
    @State private var details = false
    @State private var filters = false
    @State private var listMode = false
    @State private var mapFailed = false
    @State private var retryToken = 0
    @State private var centerToken = 0
    @State private var query = ""
    @State private var region: MapRegion?
    @State private var carouselID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var events: [Event] { model.state?.events ?? [] }
    private var selectedID: String? { model.state?.selectedEvent?.id }
    private var activeFilters: Int {
        [model.state?.dateFilter != DateFilter.shared.ANY, model.state?.category != AppStateKt.ALL_CATEGORIES, model.state?.onlyAvailable == true]
            .filter { $0 }.count
    }
    var body: some View {
        ZStack(alignment: .top) {
            EventMap(
                events: events, latitude: model.state?.cityLatitude ?? 50.45, longitude: model.state?.cityLongitude ?? 30.52,
                selectedID: selectedID, retryToken: retryToken, centerToken: centerToken,
                topInset: topControlsInset, bottomInset: carouselInset,
                loadFailed: { mapFailed = $0 },
                selected: { model.app.selectEvent(id: $0.id) },
                moved: { region = $0 }
            )
            .ignoresSafeArea()
            LinearGradient(colors: [Palette.canvas.opacity(0.94), Palette.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 230).ignoresSafeArea(edges: .top).allowsHitTesting(false)
            VStack(spacing: Space.md) {
                topControls
                if mapFailed {
                    Button { mapFailed = false; retryToken += 1 } label: {
                        Label("Мапа недоступна · Повторити", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                            .padding(.horizontal, Space.lg).frame(height: 44).cardSurface(radius: 22, elevation: 6)
                    }.buttonStyle(.plain)
                }
                if region != nil {
                    PrimaryButton(title: "Шукати тут", symbol: "arrow.clockwise") {
                        if let region { model.app.searchArea(south: region.south, west: region.west, north: region.north, east: region.east) }
                        region = nil
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                bottomDeck
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .padding(.bottom, tabBarInset)
            if listMode { listOverlay }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: region == nil)
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { query = model.state?.searchText ?? "" }
        .onChange(of: query) { _, value in model.app.setSearchText(query: value) }
        .onChange(of: events.map(\.id)) { _, _ in region = nil }
        .onChange(of: carouselID) { _, value in
            guard let value, value != selectedID else { return }
            model.app.selectEvent(id: value)
        }
        .onChange(of: selectedID) { _, value in
            guard let value, value != carouselID else { return }
            if reduceMotion { carouselID = value } else { withAnimation { carouselID = value } }
        }
        .sheet(isPresented: $citySearch) { CitySearchView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $filters) { FiltersView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $details) {
            NavigationStack { EventDetailView(app: model.app) }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .onReceive(location.$coordinate) { coordinate in
            if let coordinate {
                model.app.selectCity(city: CityResult(name: "Поруч зі мною", latitude: coordinate.latitude, longitude: coordinate.longitude))
                region = nil
            }
        }
        .alert("Геолокація", isPresented: Binding(get: { location.message != nil }, set: { if !$0 { location.message = nil } })) {
            Button("Добре") { location.message = nil }
        } message: { Text(location.message ?? "") }
    }

    private var topControls: some View {
        VStack(spacing: Space.md) {
            SearchField(text: $query, placeholder: "Подія, місце або тема", activeFilters: activeFilters) { filters = true }
            HStack(spacing: Space.sm) {
                Button { citySearch = true } label: {
                    HStack(spacing: Space.sm) {
                        PoruchIcon(glyph: PoruchIcons.pin, size: 16).foregroundStyle(Palette.brand)
                        Text(model.state?.cityName ?? "Київ").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.inkSecondary)
                    }.padding(.horizontal, Space.lg).frame(height: 44).cardSurface(radius: 22, elevation: 6)
                }.buttonStyle(.plain).accessibilityLabel("Змінити місто")
                Spacer(minLength: 0)
                IconPill(symbol: "viewfinder", label: "Повернутися до міста") {
                    model.app.dismissEvent(); carouselID = nil; centerToken += 1
                }
                IconPill(symbol: "location", label: "Поруч зі мною") { location.request() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(dateFilterKeys, id: \.self) { key in
                        Chip(label: dateLabel(key), selected: model.state?.dateFilter == key) { model.app.setDateFilter(filter: key) }
                    }
                    Chip(label: "Є місця", symbol: "checkmark.circle", selected: model.state?.onlyAvailable == true) {
                        model.app.setOnlyAvailable(available: !(model.state?.onlyAvailable ?? false))
                    }
                }.padding(.horizontal, 2)
            }
        }
    }

    /**
     The carousel and the map share one selection: settling on a card focuses its pin, and tapping a
     pin scrolls the carousel back. Both directions bail out when the id already matches.
     */
    private var bottomDeck: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Spacer(minLength: 0)
                HStack(spacing: Space.sm) {
                    if model.state?.loading == true { ProgressView().controlSize(.mini) }
                    else if model.state?.offline == true {
                        Image(systemName: "wifi.slash").font(.system(size: 12)).foregroundStyle(Palette.accent)
                    }
                    Text(model.state?.loading == true ? "Шукаємо події…" : "Знайдено подій: \(events.count)")
                        .font(PoruchFont.label).foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                .cardSurface(radius: 20, elevation: 6)
                IconPill(symbol: listMode ? "map" : "list.bullet", label: listMode ? "Показати на мапі" : "Показати списком") {
                    listMode.toggle()
                }
            }
            if events.isEmpty {
                if model.state?.loading != true {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Тут поки тихо").font(PoruchFont.title3).foregroundStyle(Palette.ink)
                        Text("Змініть область мапи, дату або категорію — і події знайдуться.")
                            .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Space.md) {
                        ForEach(events, id: \.id) { event in
                            EventMapCard(
                                event: event, focused: event.id == selectedID,
                                saved: model.state?.savedIds.contains(event.id) == true,
                                onSave: { model.app.toggleSaved(id: event.id) }
                            ) { model.app.selectEvent(id: event.id); details = true }
                            .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: Space.md)
                            .id(event.id)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $carouselID)
                .frame(height: 124)
            }
        }
    }

    private var listOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Знайдено подій: \(events.count)").font(PoruchFont.title2).foregroundStyle(Palette.ink)
                    Text("Знайдіть, куди піти у місті \(model.state?.cityName ?? "Київ")")
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                Spacer()
                IconPill(symbol: "map", label: "Показати на мапі") { listMode = false }
            }.padding(Space.page)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(categories, id: \.0) { category in
                        CategoryTile(category: category.0, selected: model.state?.category == category.0) {
                            model.app.setCategory(category: model.state?.category == category.0 ? AppStateKt.ALL_CATEGORIES : category.0)
                        }
                    }
                }.padding(.horizontal, Space.page)
            }
            if events.isEmpty {
                EmptyState(
                    symbol: "safari", title: "Тут поки тихо",
                    message: "Змініть область мапи, дату або категорію — і події знайдуться."
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.lg) {
                        ForEach(events, id: \.id) { event in
                            EventCard(
                                event: event, saved: model.state?.savedIds.contains(event.id) == true,
                                waitlisted: model.state?.waitlistedIds.contains(event.id) == true,
                                onSave: { model.app.toggleSaved(id: event.id) }
                            ) { model.app.selectEvent(id: event.id); details = true }
                        }
                    }.padding(.horizontal, Space.page).padding(.top, Space.md).padding(.bottom, 120)
                }
            }
        }.background(Palette.canvas)
    }
}

struct FiltersView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                SectionHeader(title: "Фільтри", actionLabel: "Скинути") {
                    model.app.setDateFilter(filter: DateFilter.shared.ANY); model.app.setCategory(category: AppStateKt.ALL_CATEGORIES); model.app.setOnlyAvailable(available: false)
                }
                Text("Коли").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkSecondary)
                HStack(spacing: Space.sm) {
                    ForEach(dateFilterKeys, id: \.self) { key in
                        Chip(label: dateLabel(key), selected: model.state?.dateFilter == key) { model.app.setDateFilter(filter: key) }
                    }
                }
                Text("Категорії").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkSecondary)
                FlexibleChips(
                    items: [(AppStateKt.ALL_CATEGORIES, "Усі", nil)] + categories.map { ($0.0, $0.1, $0.0) },
                    isSelected: { model.state?.category == $0 }
                ) { model.app.setCategory(category: $0) }
                Toggle(isOn: Binding(
                    get: { model.state?.onlyAvailable ?? false },
                    set: { model.app.setOnlyAvailable(available: $0) }
                )) {
                    Text("Лише події з вільними місцями").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                }.tint(Palette.brand)
                PrimaryButton(title: "Готово") { dismiss() }
            }.padding(Space.page)
        }.background(Palette.canvas)
    }
}

/// Wrapping chip group; SwiftUI has no flow layout on the deployment target, so rows are measured manually.
struct FlexibleChips: View {
    /// Each item is (key, label, category key for the leading dot — nil for a plain chip).
    let items: [(String, String, String?)]
    let isSelected: (String) -> Bool
    let action: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { index in
                HStack(spacing: Space.sm) {
                    ForEach(items[index..<min(index + 2, items.count)], id: \.0) { item in
                        Chip(label: item.1, dot: item.2, selected: isSelected(item.0)) { action(item.0) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct CitySearchView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List(model.state?.cities ?? [], id: \.name) { city in
                Button { model.app.selectCity(city: city); model.app.dismissEvent(); dismiss() } label: {
                    Label(city.name, systemImage: "mappin.and.ellipse").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Місто у світі")
            .onChange(of: query) { _, value in model.app.searchCity(query: value) }
            .navigationTitle("Знайти місто")
            .toolbar { Button("Готово") { dismiss() } }
        }
    }
}
