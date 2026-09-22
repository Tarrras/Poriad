import SwiftUI
import Shared

/// Фільтри дати в порядку показу. Читають і рядок чипів, і шторка фільтрів.
var dateFilterKeys: [String] { [DateFilter.shared.ANY, DateFilter.shared.TODAY, DateFilter.shared.WEEKEND] }

func dateLabel(_ key: String) -> String {
    switch key {
    case DateFilter.shared.TODAY: "Сьогодні"
    case DateFilter.shared.WEEKEND: "Вихідні"
    default: "Будь-коли"
    }
}

private let topControlsInset: CGFloat = 140
private let carouselInset: CGFloat = 280
private let tabBarInset: CGFloat = 92
/// Повітря між рядком лічильника і каруселлю.
private let deckGap: CGFloat = Space.md
/// Скільки мапи лишаємо над повністю піднятою шторкою. Фільтри повертаються в половинному положенні.
private let sheetTopInset: CGFloat = Space.sm

/// Положення шторки: згорнута (карусель), половина, повний екран. Окремого режиму списку нема.
private enum SheetDetent {
    case peek, half, full
}

/// Прокрутка списку в шторці від його початку.
private struct ListOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private extension View {
    /// Зсув ScrollView від початку, вниз додатний, у `offset`. На iOS 18+ від самої прокрутки: GeometryReader
    /// у фоні вмісту на новіших системах не оновлюється, і зсув застрягав на нулі. На iOS 17 читає
    /// preference `ListOffsetKey`, який вміст має виставити сам у просторі "sheetList".
    @ViewBuilder
    func listOffset(_ offset: Binding<CGFloat>) -> some View {
        if #available(iOS 18, *) {
            onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, new in
                offset.wrappedValue = new
            }
        } else {
            coordinateSpace(name: "sheetList")
                .onPreferenceChange(ListOffsetKey.self) { offset.wrappedValue = $0 }
        }
    }
}

struct DiscoveryView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var location = LocationFinder()
    @State private var citySearch = false
    /// Подія з відкритими деталями. Значення, а не прапорець, щоб не читати id з асинхронного стану.
    @State private var detail: EventRoute?
    @State private var filters = false
    @State private var mapFailed = false
    @State private var retryToken = 0
    @State private var centerToken = 0
    @State private var region: MapRegion?
    /// Події на одній точці (всі події закладу): без стосу решта недосяжна з мапи.
    @State private var stackIDs: [String] = []
    /// Наскільки піднята шторка зі списком.
    @State private var detent: SheetDetent = .peek
    /// Зсув пальця по ручці шторки, вниз додатний. Не `@GestureState`: той скидається окремим
    /// оновленням, і шторка стрибала до старого положення перед новим.
    @State private var sheetDrag: CGFloat = 0
    /// Зсув пальця по списку в момент, коли протягування перейшло від списку до шторки. `nil` — список сам по собі.
    @State private var listDrag: CGFloat?
    /// Прокрутка списку від його початку; від'ємна, коли список відтягнуто нижче верху.
    @State private var listOffset: CGFloat = 0
    /// Розмір екрана під контролами: з нього рахуються висоти шторки.
    @State private var screen: CGSize = .zero
    /// Категорія, обрана плитками в шторці. Звужує список, а не мапу.
    @State private var listCategory = DiscoveryStateKt.ALL_CATEGORIES
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Категорія мапи. Головна має свою.
    private var category: String { model.state?.map.category ?? DiscoveryStateKt.ALL_CATEGORIES }

    /// Похідні списки, пораховані раз на зміну входів. Тіло перераховується на кожен кадр
    /// протягування шторки, а кожен прохід по індексу — тисячі звертань через міст.
    @State private var memo = DeckMemo()

    private var derived: DeckMemo {
        memo.update(DeckMemo.Key(
            entries: model.entriesRevision, cards: model.cardsRevision,
            category: category, listCategory: listCategory, stack: stackIDs
        ), model: model)
        return memo
    }

    /// Що малює мапа: індекс, звужений до категорії. Фільтр тут, а не в запиті, щоб не звужувати й головну.
    var mapEntries: [EventIndexEntry] { derived.mapEntries }
    private var selectedID: String? { model.state?.detail.event?.id }
    private var savedIDs: Set<String> { model.savedIDs }

    /// Стос обраного піна не порожній. Порожньо, якщо після нової видачі стосу не лишилось.
    private var stackFocused: Bool { derived.stackFocused }

    /// Вміст шторки: стос обраного піна або вся видача, звужені категорією плиток. Плитки звужують список, а не мапу.
    private var listEntries: [EventIndexEntry] { derived.listEntries }
    /// Завантажені картки списку. Може бути менше за `listEntries`: решту список просить сам.
    private var shownEvents: [Event] { derived.shownEvents }
    private var activeFilters: Int {
        [model.state?.map.dateFilter != DateFilter.shared.ANY, model.state?.map.category != DiscoveryStateKt.ALL_CATEGORIES, model.state?.map.onlyAvailable == true]
            .filter { $0 }.count
    }
    var body: some View {
        ZStack(alignment: .top) {
            EventMap(
                events: mapEntries, latitude: model.state?.city.latitude ?? 50.45, longitude: model.state?.city.longitude ?? 30.52,
                selectedID: selectedID, eventsRevision: model.eventsRevision, filterKey: category,
                retryToken: retryToken, centerToken: centerToken,
                topInset: topControlsInset, bottomInset: carouselInset,
                loadFailed: { mapFailed = $0 },
                // Тап по піну: шторка згортається і показує картку цієї події.
                selected: { model.app.selectEvent(id: $0.id); open(.peek) },
                selectedStack: { ids in
                    // Пін — це місце: у фокус іде все, що на ньому стоїть.
                    stackIDs = ids
                    // Стос — не початок стрічки, вікно карток його не покриває.
                    model.app.loadCards(ids: ids)
                    if let first = ids.first { model.app.selectEvent(id: first); open(.peek) }
                },
                moved: { region = $0 }
            )
            .ignoresSafeArea()
            LinearGradient(colors: [Palette.canvas.opacity(0.94), Palette.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 175).ignoresSafeArea(edges: .top).allowsHitTesting(false)
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
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            sheet.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background {
            // Вимір, а не обгортка: екран у GeometryReader не загортаємо, див. statusBarInset.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { screen = proxy.size }
                    .onChange(of: proxy.size) { _, value in screen = value }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: region == nil)
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: model.eventsRevision) { _, _ in region = nil }
        // Біля краю завантаженого просимо наступне вікно карток.
        .onChange(of: selectedID) { _, id in
            guard let id, !stackFocused, shownEvents.count < listEntries.count else { return }
            guard let position = shownEvents.firstIndex(where: { $0.id == id }) else {
                // Вибір ззовні (кнопка «На мапі» в деталях) може бути за краєм вікна карток.
                if listEntries.contains(where: { $0.id == id }) { model.app.loadCards(ids: [id]) }
                return
            }
            if position >= shownEvents.count - cardPrefetchAhead { loadHead(shownEvents.count + cardPage) }
        }
        // Картки просимо під категорію, яку показуємо: під фільтром вони лежать за краєм вікна.
        .onChange(of: listCategory) { _, _ in loadHead(cardPage) }
        .onChange(of: category) { _, _ in loadHead(cardPage) }
        .onChange(of: model.eventsRevision) { _, _ in loadHead(cardPage) }
        .sheet(isPresented: $citySearch) { CitySearchView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $filters) { FiltersView().presentationDetents([.medium, .large]) }
        .sheet(item: $detail) { route in
            NavigationStack {
                EventDetailView(app: model.app, eventID: route.id)
                    .navigationDestination(for: EventRoute.self) { EventDetailView(app: model.app, eventID: $0.id) }
                    .navigationDestination(for: ChatRoute.self) { ChatView(eventID: $0.id) }
            }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .onReceive(location.$city) { city in
            if let city {
                model.app.selectCity(city: city)
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
                initial: model.state?.map.searchText ?? "",
                activeFilters: activeFilters,
                onFilters: { filters = true }
            ) { model.app.setSearchText(query: $0) }
            // Один ряд замість двох: місто веде стрічку фільтрів. Керування мапою — над каруселлю, під пальцем.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    Chip(label: model.state?.city.name ?? "Київ", symbol: "mappin.and.ellipse", trailingSymbol: "chevron.down", selected: false) { citySearch = true }
                        .accessibilityLabel("Змінити місто")
                    ForEach(dateFilterKeys, id: \.self) { key in
                        // Повторний тап знімає вибір, щоб не шукати «Будь-коли» за краєм рядка.
                        Chip(label: dateLabel(key), selected: model.state?.map.dateFilter == key) {
                            model.app.setDateFilter(filter: model.state?.map.dateFilter == key ? DateFilter.shared.ANY : key)
                        }
                    }
                    Chip(label: "Можна приєднатись", symbol: "checkmark.circle", selected: model.state?.map.onlyAvailable == true) {
                        model.app.setOnlyAvailable(available: !(model.state?.map.onlyAvailable ?? false))
                    }
                }
            }
            // Поля всередині смуги, тож смуга йде від краю до краю.
            .railContentPadding()
            .padding(.horizontal, -Space.page)
        }
    }

    // ---- Шторка зі списком

    /// Шторка над мапою: згорнута — карусель, піднята — список тієї ж видачі. Карусель і мапа ділять один вибір.
    private var sheet: some View {
        VStack(spacing: 0) {
            sheetHandle
            if !expanded {
                if shownEvents.isEmpty {
                    if model.state?.map.loading != true { quietCard.padding(.horizontal, Space.page) }
                } else {
                    EventDeck(
                        events: shownEvents, selectedID: selectedID, savedIDs: savedIDs,
                        resetToken: centerToken,
                        select: { model.app.selectEvent(id: $0) },
                        open: { model.app.selectEvent(id: $0); detail = EventRoute(id: $0) },
                        toggleSaved: { model.app.toggleSaved(id: $0) }
                    )
                    .padding(.top, deckGap)
                }
            } else {
                sheetList
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, tabBarInset)
        // Висота йде за пальцем, а не за положенням, інакше під час жесту над вмістом порожнеча.
        .frame(height: sheetHeight, alignment: .top)
        .background {
            // Згорнутій шторці підкладка не потрібна. Прозорий фон ловив би дотики замість мапи.
            if expanded {
                RoundedRectangle(cornerRadius: Corner.xl, style: .continuous)
                    .fill(Palette.canvas)
                    .lifted(Elevation.overlay)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: detent)
    }

    /// Поточна висота шторки: положення плюс зсув пальця.
    private var sheetHeight: CGFloat {
        min(max(height(of: detent) - sheetDrag, height(of: .peek)), height(of: .full))
    }

    /// Шторка вже більша за згорнуту. Від живої висоти, а не від положення: вміст стає списком, щойно є місце.
    private var expanded: Bool { sheetHeight > height(of: .peek) + Space.section }

    private func height(of detent: SheetDetent) -> CGFloat {
        switch detent {
        case .peek: return peekHeight
        case .half: return max(screen.height * 0.55, peekHeight)
        case .full: return max(screen.height - sheetTopInset, peekHeight)
        }
    }

    /// Згорнута шторка: рядок лічильника, карусель і місце під таббар.
    private var peekHeight: CGFloat { 44 + deckGap + Space.sm + mapCardHeight + tabBarInset }

    /// Ручка шторки: тягнеться і натискається, тож список доступний і для VoiceOver.
    private var sheetHandle: some View {
        // Один контейнер на всі положення, жест на ньому. Дві гілки `if` перебудовували
        // подання під час жесту, і протягування вмирало на півдорозі.
        VStack(spacing: Space.sm) {
            Capsule().fill(Palette.inkTertiary)
                .frame(width: 36, height: expanded ? 4 : 0)
                .opacity(expanded ? 1 : 0)
                .padding(.top, expanded ? Space.sm : 0)
            if expanded { listHeader } else { peekHeader }
        }
        .padding(.horizontal, Space.page)
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
    }

    /// Протягування шторки на шапці. Список має свій жест: `listDragGesture`.
    private var sheetDragGesture: some Gesture {
        // Екранні координати: у власних шапка їде разом зі шторкою, і відліки тремтять.
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in sheetDrag = value.translation.height }
            .onEnded { value in
                settle(translation: value.translation.height, predicted: value.predictedEndTranslation.height)
            }
    }

    private var peekHeader: some View {
        HStack(spacing: Space.sm) {
            // Керування мапою в зоні великого пальця. Це кнопки, тож за них шторку не тягнуть — лише за решту ряду.
            IconPill(symbol: "viewfinder", label: "Повернутися до міста", size: 40) {
                model.app.dismissEvent(); centerToken += 1
            }
            IconPill(symbol: "location", label: "Поруч зі мною", size: 40) { location.request() }
            Spacer(minLength: 0)
            // Не `Button`: кнопка забирає дотик, і протягнути шторку за неї не виходить.
            HStack(spacing: Space.sm) {
                if model.state?.map.loading == true { ProgressView().controlSize(.mini) }
                else if model.state?.map.offline == true {
                    Image(systemName: "wifi.slash").font(.system(size: 12)).foregroundStyle(Palette.accent)
                }
                Text(countLabel).font(PoruchFont.label).foregroundStyle(Palette.ink)
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, Space.lg).frame(height: 40)
            .cardSurface(radius: 20, elevation: 6)
            .contentShape(Capsule())
            .onTapGesture { open(.half) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(countLabel). Показати списком")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(.half) }
            if stackFocused { clearStackButton }
        }
        .frame(height: 44)
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(countLabel).font(PoruchFont.title2).foregroundStyle(Palette.ink)
                Text(areaLabel).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            if stackFocused { clearStackButton }
            IconPill(symbol: "chevron.down", label: "Показати на мапі") { open(.peek) }
        }
        .padding(.bottom, Space.md)
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
    }

    /// Вихід із фокуса на піні знімає і підсвітку, інакше мапа й список розходились.
    private var clearStackButton: some View {
        IconPill(symbol: "xmark", label: "Показати всі події") {
            stackIDs = []
            model.app.dismissEvent()
        }
    }

    private var sheetList: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(categories, id: \.0) { entry in
                        CategoryTile(category: entry.0, selected: listCategory == entry.0) {
                            listCategory = listCategory == entry.0 ? DiscoveryStateKt.ALL_CATEGORIES : entry.0
                        }
                    }
                }
            }.railContentPadding()
            if shownEvents.isEmpty {
                if model.state?.map.loading == true {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.section)
                } else {
                    quietCard.padding(Space.page)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.lg) {
                        ForEach(Array(shownEvents.enumerated()), id: \.element.id) { position, event in
                            EventCard(
                                event: event, saved: savedIDs.contains(event.id),
                                waitlisted: model.waitlistedIDs.contains(event.id),
                                onSave: { model.app.toggleSaved(id: event.id) }
                            ) { model.app.selectEvent(id: event.id); detail = EventRoute(id: event.id) }
                            // Список довантажує картки сам, а не лише карусель.
                            .onAppear { loadMore(reaching: position) }
                        }
                        if shownEvents.count < listEntries.count {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.lg)
                        }
                    }
                    .padding(.horizontal, Space.page).padding(.top, Space.md).padding(.bottom, Space.section)
                    .background {
                        // Запасний вимір для iOS 17; на 18+ його не читають.
                        GeometryReader { proxy in
                            Color.clear.preference(key: ListOffsetKey.self, value: -proxy.frame(in: .named("sheetList")).minY)
                        }
                    }
                }
                .listOffset($listOffset)
                // Список гортається лише в повній шторці; нижче протягування піднімає її. Вимкнення
                // під час жесту скасовує прокрутку UIKit, і шторка їде замість гумового краю.
                .scrollDisabled(detent != .full || listDrag != nil)
                // Нижче повної список не гортається, і жест має перебити натискання картки, інакше
                // протягування відкривало її. У повній він лише йде поруч із прокруткою UIKit.
                .highPriorityGesture(listDragGesture, including: detent == .full ? .subviews : .all)
                .simultaneousGesture(listDragGesture, including: detent == .full ? .all : .subviews)
            }
        }
    }

    /// Прокрутка списку тягне шторку: угору — доки не повна, униз від верху списку — опускає її.
    private var listDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dy = value.translation.height
                if listDrag == nil {
                    // Після сідання на згорнуту список зникає, а жест ще шле оновлення.
                    guard detent != .peek else { return }
                    // У повній шторці список гортається сам; беремо жест, лише коли він на початку і палець іде вниз.
                    guard detent != .full || (listOffset <= 0.5 && dy > 0) else { return }
                    listDrag = dy
                }
                guard let origin = listDrag else { return }
                let drag = dy - origin
                // Нижче порога список зникає разом із жестом, тож сідаємо на згорнуту звідси.
                if height(of: detent) - drag <= height(of: .peek) + Space.section {
                    listDrag = nil
                    open(.peek)
                    return
                }
                sheetDrag = drag
            }
            .onEnded { value in
                guard let origin = listDrag else { return }
                listDrag = nil
                settle(translation: value.translation.height - origin, predicted: value.predictedEndTranslation.height - origin)
            }
    }

    private var quietCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Тут поки тихо").font(PoruchFont.title3).foregroundStyle(Palette.ink)
            Text("Змініть область мапи, дату або категорію — і події знайдуться.")
                .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /// Лічильник шторки: з індексу, а не з `totalFound` чи завантажених карток.
    private var countLabel: String {
        if model.state?.map.loading == true { return "Шукаємо події…" }
        if stackFocused { return "Тут подій: \(listEntries.count)" }
        let whole = category == DiscoveryStateKt.ALL_CATEGORIES && listCategory == DiscoveryStateKt.ALL_CATEGORIES
        return "Знайдено подій: \(whole ? Int(model.state?.map.totalFound ?? 0) : listEntries.count)"
    }

    /// Що показує екран: пін, область рукою чи ціле місто.
    private var areaLabel: String {
        if stackFocused { return "Усе, що стоїть на обраному піні" }
        return model.state?.city.custom == true
            ? "В області, яку ви обрали на мапі"
            : "Знайдіть, куди піти у місті \(model.state?.city.name ?? "Київ")"
    }

    /// Перевести шторку в положення.
    private func open(_ target: SheetDetent) {
        if reduceMotion {
            sheetDrag = 0
            detent = target
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                sheetDrag = 0
                detent = target
            }
        }
    }

    /// Куди відпустити шторку: до найближчого положення. Інерція лише схиляє вибір (`coastShare`).
    private func settle(translation: CGFloat, predicted: CGFloat) {
        let released = height(of: detent) - translation
        let target = released - (predicted - translation) * coastShare
        let nearest = [SheetDetent.peek, .half, .full]
            .min { abs(height(of: $0) - target) < abs(height(of: $1) - target) } ?? .peek
        // Нове положення і скидання зсуву в одному оновленні, інакше стрибок.
        open(nearest)
    }

    /// Наступне вікно карток біля краю завантаженого.
    private func loadMore(reaching position: Int) {
        guard shownEvents.count < listEntries.count else { return }
        guard position >= shownEvents.count - cardPrefetchAhead else { return }
        loadHead(shownEvents.count + cardPage)
    }

    /// Картки початку показаного списку.
    private func loadHead(_ count: Int) {
        let ids = listEntries.prefix(count).map(\.id)
        guard !ids.isEmpty else { return }
        model.app.loadCards(ids: ids)
    }
}

struct FiltersView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    /// Вибір накопичується і летить на сервер один раз по «Готово»: проміжних результатів за шторкою не видно.
    @State private var date: String?
    @State private var category: String?
    @State private var available: Bool?

    private var pickedDate: String { date ?? model.state?.map.dateFilter ?? DateFilter.shared.ANY }
    private var pickedCategory: String { category ?? model.state?.map.category ?? DiscoveryStateKt.ALL_CATEGORIES }
    private var pickedAvailable: Bool { available ?? model.state?.map.onlyAvailable ?? false }

    private func apply() {
        if pickedDate != model.state?.map.dateFilter { model.app.setDateFilter(filter: pickedDate) }
        if pickedCategory != model.state?.map.category { model.app.setCategory(category: pickedCategory) }
        if pickedAvailable != model.state?.map.onlyAvailable { model.app.setOnlyAvailable(available: pickedAvailable) }
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
                                Chip(label: dateLabel(key), selected: pickedDate == key) {
                                    date = pickedDate == key ? DateFilter.shared.ANY : key
                                }
                            }
                        }
                    }
                    section("Категорії") {
                        FlexibleChips(
                            items: [(DiscoveryStateKt.ALL_CATEGORIES, "Усі", nil)] + categories.map { ($0.0, $0.1, $0.0) },
                            isSelected: { pickedCategory == $0 }
                        ) { category = pickedCategory == $0 ? DiscoveryStateKt.ALL_CATEGORIES : $0 }
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

    /// Заголовок шторки — заголовок, а не надрядок, інакше він менший за секції під ним.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Фільтри").font(PoruchFont.title2).foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            Button("Скинути") {
                date = DateFilter.shared.ANY
                category = DiscoveryStateKt.ALL_CATEGORIES
                available = false
            }
            .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.lg)
    }

    /// Прикріплена, не в скролі: у середньому положенні кнопка ховалась за згином.
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

/// Чипи з переносом: у SwiftUI на цільовій версії нема flow layout, рядки міряються вручну.
struct FlexibleChips: View {
    /// (ключ, підпис, категорія для крапки або nil).
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

    /// Поки нічого не набрано, пропонуємо міста, де події справді є.
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
                    ForEach(model.state?.city.suggestions ?? [], id: \.name) { city in
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
            // Без автофокуса: `searchFocused` з iOS 18, мінімум проєкту — 17.
            .onSettled(query, after: .milliseconds(220)) { model.app.searchCity(query: $0) }
            .navigationTitle("Знайти місто")
            .toolbar { Button("Готово") { dismiss() } }
        }
    }
}

/// Частка інерції пальця, що схиляє вибір положення шторки.
private let coastShare: CGFloat = 0.25
/// За скільки карток до кінця завантаженого просити наступні.
private let cardPrefetchAhead = 8
/// Скільки карток додає одне довантаження.
private let cardPage = 24

/// Кеш похідних списків мапи. Клас, щоб оновлення в тілі не було зміною стану подання.
private final class DeckMemo {
    struct Key: Equatable {
        let entries: Int
        let cards: Int
        let category: String
        let listCategory: String
        let stack: [String]
    }

    private var key: Key?
    private(set) var mapEntries: [EventIndexEntry] = []
    private(set) var stackFocused = false
    private(set) var listEntries: [EventIndexEntry] = []
    private(set) var shownEvents: [Event] = []

    @MainActor func update(_ next: Key, model: AppModel) {
        guard next != key else { return }
        key = next
        let all = DiscoveryStateKt.ALL_CATEGORIES
        mapEntries = next.category == all ? model.mapEntries : model.mapEntries.filter { $0.category == next.category }
        let stack = Set(next.stack)
        let stackEntries = stack.isEmpty ? [] : mapEntries.filter { stack.contains($0.id) }
        stackFocused = !stackEntries.isEmpty
        let base = stackFocused ? stackEntries : mapEntries
        listEntries = next.listCategory == all ? base : base.filter { $0.category == next.listCategory }
        let cards = model.cardsByID
        shownEvents = listEntries.compactMap { cards[$0.id] }
    }
}
