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
    @State private var region: MapRegion?
    /// Події, що стоять на одній точці. Кеш майданчиків дає всім подіям закладу ті самі
    /// координати, тож без фокуса решта стосу недосяжна з мапи.
    @State private var stackIDs: [String] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Pins are a set and have no order; the carousel and the list do, and it is the same order
    /// home shows — what the answers put first is what the thumb reaches first.
    /// Зібрано в [AppModel] один раз на емісію стану, а не на кожне перемальовування екрана.
    /// Що малює мапа: увесь індекс області. Повний з першої відповіді — картки приїжджають слідом.
    var mapEntries: [EventIndexEntry] { model.mapEntries }
    /// Що показують карусель і список: картки, які вже завантажились, у тому самому порядку.
    var events: [Event] { model.cards }
    private var selectedID: String? { model.state?.selectedEvent?.id }
    /// Скільки подій в області насправді, а не скільки карток встигло завантажитись. Мапа вже
    /// показує саме це число пінами, тож лічильник має казати те саме.
    private var totalFound: Int { Int(model.state?.totalFound ?? 0) }
    private var savedIDs: Set<String> { model.savedIDs }
    /// Що показує карусель: увесь результат або лише місце, у яке щойно тицьнули.
    private var deckEvents: [Event] {
        guard !stackIDs.isEmpty else { return events }
        // Порядок стосу — з індексу, а не з набору ідентифікаторів: він має збігатися з тим, у
        // якому події стоять на мапі й у стрічці.
        let focused = mapEntries.filter { stackIDs.contains($0.id) }.compactMap { model.cardsByID[$0.id] }
        // Після нової видачі від стосу могло лишитись нуль або одна подія — тоді фокус нічого не
        // додає, і карусель має повернутись до повного списку.
        return focused.count > 1 ? focused : events
    }
    private var stackFocused: Bool { !stackIDs.isEmpty && mapEntries.filter { stackIDs.contains($0.id) }.count > 1 }
    private var activeFilters: Int {
        [model.state?.dateFilter != DateFilter.shared.ANY, model.state?.category != AppStateKt.ALL_CATEGORIES, model.state?.onlyAvailable == true]
            .filter { $0 }.count
    }
    var body: some View {
        ZStack(alignment: .top) {
            EventMap(
                events: mapEntries, latitude: model.state?.cityLatitude ?? 50.45, longitude: model.state?.cityLongitude ?? 30.52,
                selectedID: selectedID, eventsRevision: model.eventsRevision,
                retryToken: retryToken, centerToken: centerToken,
                topInset: topControlsInset, bottomInset: carouselInset,
                loadFailed: { mapFailed = $0 },
                selected: { model.app.selectEvent(id: $0.id) },
                selectedStack: { ids in
                    // Одна подія — звичайний вибір; кілька — фокус на місці, інакше решта стосу
                    // лишається недосяжною з мапи.
                    stackIDs = ids.count > 1 ? ids : []
                    // Стос — це не початок стрічки, тож вікно карток його не покриває: у київського
                    // майданчика на 32 події в нього потрапляли дві, і пін казав «32», а карусель
                    // під ним — «Тут подій: 2».
                    if ids.count > 1 { model.app.loadCards(ids: ids) }
                    if let first = ids.first { model.app.selectEvent(id: first) }
                },
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
        .onChange(of: model.eventsRevision) { _, _ in region = nil }
        // Індекс повний з першої відповіді, картки — ні. Коли карусель підходить до краю
        // завантаженого, просимо наступне вікно за вже відомими ідентифікаторами.
        .onChange(of: selectedID) { _, id in
            guard let id, !stackFocused, events.count < mapEntries.count else { return }
            guard let position = events.firstIndex(where: { $0.id == id }) else { return }
            if position >= events.count - cardPrefetchAhead {
                model.app.loadMore(upTo: Int32(events.count + cardPage))
            }
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
            SearchBar(
                placeholder: "Подія, місце або тема",
                initial: model.state?.searchText ?? "",
                activeFilters: activeFilters,
                onFilters: { filters = true }
            ) { model.app.setSearchText(query: $0) }
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
                    model.app.dismissEvent(); centerToken += 1
                }
                IconPill(symbol: "location", label: "Поруч зі мною") { location.request() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(dateFilterKeys, id: \.self) { key in
                        Chip(label: dateLabel(key), selected: model.state?.dateFilter == key) { model.app.setDateFilter(filter: key) }
                    }
                    Chip(label: "Можна приєднатись", symbol: "checkmark.circle", selected: model.state?.onlyAvailable == true) {
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
                    Text(
                        model.state?.loading == true ? "Шукаємо події…"
                            : stackFocused ? "Тут подій: \(deckEvents.count)"
                            : "Знайдено подій: \(totalFound)"
                    )
                    .font(PoruchFont.label).foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                .cardSurface(radius: 20, elevation: 6)
                if stackFocused {
                    IconPill(symbol: "xmark", label: "Показати всі події") { stackIDs = [] }
                }
                IconPill(symbol: listMode ? "map" : "list.bullet", label: listMode ? "Показати на мапі" : "Показати списком") {
                    listMode.toggle()
                }
            }
            if deckEvents.isEmpty {
                if model.state?.loading != true {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Тут поки тихо").font(PoruchFont.title3).foregroundStyle(Palette.ink)
                        Text("Змініть область мапи, дату або категорію — і події знайдуться.")
                            .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                }
            } else {
                EventDeck(
                    events: deckEvents, selectedID: selectedID, savedIDs: savedIDs,
                    resetToken: centerToken,
                    select: { model.app.selectEvent(id: $0) },
                    open: { model.app.selectEvent(id: $0); details = true },
                    toggleSaved: { model.app.toggleSaved(id: $0) }
                )
            }
        }
    }

    private var listOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Знайдено подій: \(totalFound)").font(PoruchFont.title2).foregroundStyle(Palette.ink)
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
                                event: event, saved: model.savedIDs.contains(event.id),
                                waitlisted: model.waitlistedIDs.contains(event.id),
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
    /**
     Вибір накопичується у шторці й летить на сервер один раз, по «Готово».

     Досі кожен тап по чипу був повним пошуком. Обрати категорію й дату — це два запити по
     чотириста рядків, і жодного проміжного результату ніхто не бачить: їх закриває сама шторка.
     А поки вона відкрита, мапа під нею перемальовується двічі.
     */
    @State private var date: String?
    @State private var category: String?
    @State private var available: Bool?

    private var pickedDate: String { date ?? model.state?.dateFilter ?? DateFilter.shared.ANY }
    private var pickedCategory: String { category ?? model.state?.category ?? AppStateKt.ALL_CATEGORIES }
    private var pickedAvailable: Bool { available ?? model.state?.onlyAvailable ?? false }

    private func apply() {
        if pickedDate != model.state?.dateFilter { model.app.setDateFilter(filter: pickedDate) }
        if pickedCategory != model.state?.category { model.app.setCategory(category: pickedCategory) }
        if pickedAvailable != model.state?.onlyAvailable { model.app.setOnlyAvailable(available: pickedAvailable) }
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    section("Коли") {
                        HStack(spacing: Space.sm) {
                            ForEach(dateFilterKeys, id: \.self) { key in
                                Chip(label: dateLabel(key), selected: pickedDate == key) { date = key }
                            }
                        }
                    }
                    section("Категорії") {
                        FlexibleChips(
                            items: [(AppStateKt.ALL_CATEGORIES, "Усі", nil)] + categories.map { ($0.0, $0.1, $0.0) },
                            isSelected: { pickedCategory == $0 }
                        ) { category = $0 }
                    }
                    Toggle(isOn: Binding(get: { pickedAvailable }, set: { available = $0 })) {
                        Text("Лише події, до яких можна приєднатись").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                    }.tint(Palette.brand)
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.lg)
            }
            actions
        }
        .background(Palette.canvas)
    }

    /// The sheet's own title is a title, not an overline: at 11 pt it was smaller than the section
    /// labels underneath it, which inverted the hierarchy of the whole sheet.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Фільтри").font(PoruchFont.title2).foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            Button("Скинути") {
                date = DateFilter.shared.ANY
                category = AppStateKt.ALL_CATEGORIES
                available = false
            }
            .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.lg)
    }

    /// Pinned, not scrolled: at the medium detent the button sat below the fold and the sheet
    /// looked as though it had no way out.
    private var actions: some View {
        PrimaryButton(title: "Готово") { apply() }
            .frame(maxWidth: .infinity)
            .padding(Space.page)
            .background(Palette.surface.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    @ViewBuilder private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: title)
            content()
        }
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

    /**
     Доки нічого не набрано, пропонуємо те, де події справді є.

     Геокодер на порожній запит мовчить, а на перші літери віддає область, район, вокзал і
     аеропорт — тобто місця, де людина побачить порожню мапу й вирішить, що подій немає взагалі.
     */
    private var covered: [HomeLocation] { HomeLocation.companion.covered }

    private func open(_ city: CityResult) {
        model.app.selectCity(city: city)
        model.app.dismissEvent()
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Міста з подіями") {
                        ForEach(covered, id: \.city) { place in
                            Button {
                                open(CityResult(name: place.city, latitude: place.latitude, longitude: place.longitude))
                            } label: {
                                HStack(spacing: Space.md) {
                                    PoruchIcon(glyph: PoruchIcons.pin, size: 18).foregroundStyle(Palette.brand)
                                    Text(place.city).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(model.state?.cities ?? [], id: \.name) { city in
                        Button { open(city) } label: {
                            HStack(spacing: Space.md) {
                                PoruchIcon(glyph: PoruchIcons.pin, size: 18).foregroundStyle(Palette.brand)
                                Text(city.name).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Місто у світі")
            // Автофокуса тут немає свідомо: `searchFocused` зʼявився в iOS 18, а мінімум проєкту —
            // 17. Для пʼяти міст, де є події, він і не потрібен — вони в списку одразу, без
            // жодного символу.
            .onSettled(query, after: .milliseconds(220)) { model.app.searchCity(query: $0) }
            .navigationTitle("Знайти місто")
            .toolbar { Button("Готово") { dismiss() } }
        }
    }
}

/// За скільки карток до кінця завантаженого просити наступні.
private let cardPrefetchAhead = 8
/// Скільки карток додає одне довантаження.
private let cardPage = 24
