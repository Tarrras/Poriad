import SwiftUI
import Shared

/// Фільтри дати в порядку показу. Читають і рядок чипів, і шторка фільтрів.
let dateFilterKeys: [DateFilter] = [.any, .today, .tomorrow, .weekend]

func dateLabel(_ filter: DateFilter) -> String {
    switch filter {
    case .today: Copy.today
    case .tomorrow: Copy.tomorrow
    case .weekend: Copy.weekend
    default: Copy.any_date
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

/// Живий зсув шторки: міняється щокадру, тож живе поза `@State` кореня. Його читає лише `SheetFrame`,
/// а мапа, карусель і фільтри над нею не перемальовуються на кожен кадр жесту.
final class SheetDrag: ObservableObject {
    @Published var value: CGFloat = 0
    /// Прокрутка списку від початку; потрібна лише жесту, тож без публікації.
    var listOffset: CGFloat = 0
}

/// Висота шторки йде за пальцем: перемальовується цей view, а не корінь мапи.
private struct SheetFrame<Content: View>: View {
    @ObservedObject var drag: SheetDrag
    let detent: SheetDetent
    let heights: (SheetDetent) -> CGFloat
    /// Шторка вже більша за згорнуту. Від живої висоти, а не від положення: вміст стає списком, щойно є місце.
    @Binding var expanded: Bool
    @ViewBuilder let content: Content

    private var height: CGFloat { min(max(heights(detent) - drag.value, heights(.peek)), heights(.full)) }

    var body: some View {
        content
            .frame(height: height, alignment: .top)
            .onChange(of: height, initial: true) { _, height in
                let now = height > heights(.peek) + Space.section
                if now != expanded { expanded = now }
            }
    }
}

struct DiscoveryView: View, Equatable {
    static func == (lhs: DiscoveryView, rhs: DiscoveryView) -> Bool { lhs.openToken == rhs.openToken }
    /// Росте з кожним переходом на мапу (`openMap`): деталі й список закриваються, лишається пін і його картка.
    var openToken = 0
    /// Без підписки на весь `AppModel`: мапа перемальовується зі своїм `ExploreScreenState`.
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    private var explore: ExploreScreenModel { model.exploreScreen }
    @StateObject private var location = LocationFinder()
    @State private var citySearch = false
    /// Подія з відкритими деталями. Значення, а не прапорець, щоб не читати id з асинхронного стану.
    @State private var detail: EventRoute?
    @State private var filters = false
    /// Вхід для гостя, що натиснув «Стежити».
    @State private var auth = false
    @State private var mapFailed = false
    @State private var retryToken = 0
    @State private var centerToken = 0
    @State private var region: MapRegion?
    /// Наскільки піднята шторка зі списком.
    @State private var detent: SheetDetent = .peek
    /// Зсув пальця по ручці шторки, вниз додатний, і прокрутка списку. Клас у `@State`, а не два `@State`-числа:
    /// корінь їх не спостерігає, тож кадр жесту перемальовує лише `SheetFrame`. Не `@GestureState`: той
    /// скидається окремим оновленням, і шторка стрибала до старого положення перед новим.
    @State private var drag = SheetDrag()
    /// Шторка вже більша за згорнуту; ставить `SheetFrame` на перетині порога.
    @State private var expanded = false
    /// Зсув пальця по списку в момент, коли протягування перейшло від списку до шторки. `nil` — список сам по собі.
    @State private var listDrag: CGFloat?
    /// Розмір екрана під контролами: з нього рахуються висоти шторки.
    @State private var screen: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Стан екрана зі спільного `ExplorePresenter`: індекс для пінів, вміст шторки, фільтри, місто.
    private var view: ExploreScreenState { explore.state }
    /// Категорія мапи. Головна має свою.
    private var category: EventCategory? { view.category }
    /// Що малює мапа: індекс, звужений до категорії, плюс обрана подія, якщо її там нема.
    var mapEntries: [EventIndexEntry] { view.mapEvents }
    private var selectedID: String? { view.selectedId }
    private var savedIDs: Set<String> { explore.savedIDs }
    private var stackFocused: Bool { view.stackFocused }
    private var stackPlace: PlaceRef? { view.stackPlace }
    private var listEntries: [EventIndexEntry] { view.listEntries }
    /// Завантажені картки шторки: для каруселі й списку. Може бути менше за `listEntries`: решту список просить сам.
    private var shownEvents: [Event] { view.deckEvents }
    private var deckEvents: [Event] { view.deckEvents }
    private var places: [Place] { view.places }
    private var artists: [ArtistHit] { view.artists }
    private var activeFilters: Int { Int(view.activeFilters) }
    var body: some View {
        ZStack(alignment: .top) {
            EventMap(
                events: mapEntries, latitude: view.cityLatitude, longitude: view.cityLongitude,
                selectedID: selectedID, eventsRevision: Int(view.indexVersion), filterKey: category?.key ?? "",
                retryToken: retryToken, centerToken: centerToken,
                topInset: topControlsInset, bottomInset: carouselInset,
                loadFailed: { mapFailed = $0 },
                // Тап по піну: шторка згортається і показує картку цієї події.
                selected: { model.app.selectEvent(id: $0.id); open(.peek) },
                selectedStack: { ids in
                    // Пін — це місце: у фокус іде все, що на ньому стоїть.
                    explore.showStack(ids); open(.peek)
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
                        Label(Copy.map_error_short, systemImage: "arrow.clockwise")
                            .font(PoruchFont.label.weight(.semibold)).foregroundStyle(Palette.ink)
                            .padding(.horizontal, Space.lg).frame(minHeight: 44).cardSurface(radius: 22, elevation: 6)
                    }.buttonStyle(.plain)
                }
                if region != nil {
                    PrimaryButton(title: Copy.search_here, symbol: "arrow.clockwise") {
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
        .motion(value: region == nil)
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: view.indexVersion) { _, _ in region = nil }
        // Вибір, зроблений до появи мапи (перший перехід на вкладку), `onChange` не бачить.
        .onAppear { reveal(selectedID) }
        .onChange(of: selectedID) { _, id in reveal(id) }
        // Заклад з пошуку: презентер відкрив його стос — шторку опускаємо, щоб бачити пін.
        .onChange(of: view.focusToken) { _, _ in open(.peek) }
        // Шторка деталей закривається разом зі своїм стеком, навіть коли «На мапі» натиснули в запушених деталях.
        .onChange(of: openToken) { _, _ in
            detail = nil
            open(.peek)
        }
        // «Усі N» з головної приносить мапу з чистими фільтрами й областю: камера, стос, плитки списку й «Шукати тут» — з чистого аркуша.
        .onChange(of: view.arrivals) { _, _ in
            region = nil
            centerToken += 1
        }
        // Картки просимо під категорію, яку показуємо: під фільтром вони лежать за краєм вікна.
        .onChange(of: view.listCategory) { _, _ in loadHead(cardPage) }
        .onChange(of: category) { _, _ in loadHead(cardPage) }
        .onChange(of: view.indexVersion) { _, _ in loadHead(cardPage) }
        .sheet(isPresented: $citySearch) { CitySearchView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $filters) { FiltersView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $auth) { NavigationStack { AuthView() } }
        .sheet(item: $detail) { route in
            NavigationStack {
                EventDetailView(app: model.app, eventID: route.id).equatable()
                    .navigationDestination(for: EventRoute.self) { EventDetailView(app: model.app, eventID: $0.id).equatable() }
                    .navigationDestination(for: ChatRoute.self) { ChatView(eventID: $0.id) }
            }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .onReceive(location.$city) { city in
            if let city {
                model.app.followLocation(city: city)
                region = nil
            }
        }
        .sheet(isPresented: Binding(get: { location.message != nil }, set: { if !$0 { location.message = nil } })) {
            PromptSheet(title: "Геолокація", message: location.message ?? "", primary: "Добре", onPrimary: {})
        }
    }

    private var topControls: some View {
        VStack(spacing: Space.md) {
            SearchBar(
                placeholder: Copy.search_placeholder,
                initial: view.searchText,
                activeFilters: activeFilters,
                onFilters: { filters = true }
            ) { model.app.setSearchText(query: $0) }
            // Один ряд замість двох: місто веде стрічку фільтрів. Керування мапою — над каруселлю, під пальцем.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    Chip(label: view.cityName, symbol: "mappin.and.ellipse", trailingSymbol: "chevron.down", selected: false) { citySearch = true }
                        .accessibilityLabel("Змінити місто")
                    // Одразу після міста, а не за датами: з «Усі N» головної мапа приходить із цим фільтром, і його має бути видно.
                    Chip(label: Copy.from_people, symbol: "person.2", selected: view.onlyAvailable) {
                        model.app.setOnlyAvailable(available: !view.onlyAvailable)
                    }
                    ForEach(dateFilterKeys, id: \.self) { key in
                        // Повторний тап знімає вибір, щоб не шукати «Будь-коли» за краєм рядка.
                        Chip(label: dateLabel(key), selected: view.dateFilter == key) {
                            model.app.setDateFilter(filter: view.dateFilter == key ? DateFilter.any : key)
                        }
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
        SheetFrame(drag: drag, detent: detent, heights: height(of:), expanded: $expanded) {
        VStack(spacing: 0) {
            sheetHandle
            if !expanded {
                if deckEvents.isEmpty {
                    if !view.loading { quietCard.padding(.horizontal, Space.page) }
                } else {
                    EventDeck(
                        events: deckEvents, selectedID: selectedID, savedIDs: savedIDs,
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
        }
        .background {
            // Згорнутій шторці підкладка не потрібна. Прозорий фон ловив би дотики замість мапи.
            if expanded {
                RoundedRectangle(cornerRadius: Corner.xl, style: .continuous)
                    .fill(Palette.canvas)
                    .lifted(Elevation.overlay)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .motion(Motion.spring, value: detent)
    }

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
            .onChanged { value in drag.value = value.translation.height }
            .onEnded { value in
                settle(translation: value.translation.height, predicted: value.predictedEndTranslation.height)
            }
    }

    private var peekHeader: some View {
        HStack(spacing: Space.sm) {
            // Керування мапою в зоні великого пальця. Це кнопки, тож за них шторку не тягнуть — лише за решту ряду.
            IconPill(symbol: "viewfinder", label: Copy.recenter, size: 40) {
                model.app.dismissEvent(); centerToken += 1
            }
            IconPill(symbol: "location", label: Copy.nearby, size: 40) { location.request() }
            Spacer(minLength: 0)
            // Не `Button`: кнопка забирає дотик, і протягнути шторку за неї не виходить.
            HStack(spacing: Space.sm) {
                if view.loading { ProgressView().controlSize(.mini) }
                else if view.offline {
                    Image(systemName: "wifi.slash").font(.system(size: 12)).foregroundStyle(Palette.accent)
                }
                // Зі «Стежити» ряд на вузькому екрані тісний: лічильник стискається, а не переноситься.
                Text(countLabel).font(PoruchFont.label).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.75)
                PoruchIcon(glyph: PoruchIcons.chevronUp, size: 14).foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, Space.lg).frame(height: 40)
            .cardSurface(radius: 20, elevation: 6)
            .contentShape(Capsule())
            .onTapGesture { open(.half) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(countLabel). Показати списком")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(.half) }
            if stackFocused {
                followButton(iconOnly: true)
                clearStackButton
            }
        }
        .frame(height: 44)
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(countLabel).font(PoruchFont.title2).foregroundStyle(Palette.ink)
                Text(areaLabel).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                // Під підписом, а не в ряду: лічильник і дві кнопки праворуч не лишають йому місця.
                if stackPlace != nil { followButton(iconOnly: false).padding(.top, Space.sm) }
            }
            Spacer(minLength: Space.sm)
            if stackFocused { clearStackButton }
            IconPill(symbol: "chevron.down", label: Copy.show_map) { open(.peek) }
        }
        .padding(.bottom, Space.md)
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
    }

    /// Вихід із фокуса на піні знімає і підсвітку, інакше мапа й список розходились.
    private var clearStackButton: some View {
        IconPill(symbol: "xmark", label: Copy.show_all_events) {
            explore.clearStack()
        }
    }

    /// «Стежити» за закладом стосу. Гостя ведемо на вхід: пуш прив'язаний до акаунта.
    @ViewBuilder private func followButton(iconOnly: Bool) -> some View {
        if let place = stackPlace {
            let _ = place
            FollowPill(following: view.stackFollowing, iconOnly: iconOnly) {
                if !explore.toggleFollowStack() { auth = true }
            }
        }
    }

    private var sheetList: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(categories, id: \.0) { entry in
                        CategoryTile(category: entry.0, selected: view.listCategory == entry.0) {
                            explore.toggleListCategory(entry.0)
                        }
                    }
                }
            }.railContentPadding()
            if shownEvents.isEmpty && places.isEmpty && artists.isEmpty {
                if view.loading {
                    PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
                } else {
                    quietCard.padding(Space.page)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.lg) {
                        // Заклади — над подіями: список подій довгий, під ним їх ніхто б не побачив.
                        if !places.isEmpty {
                            PlacesGroup(places: places) { focusPlace($0) }
                        }
                        if !artists.isEmpty { ArtistsGroup(artists: artists) }
                        ForEach(Array(shownEvents.enumerated()), id: \.element.id) { position, event in
                            EventCard(
                                event: event, saved: savedIDs.contains(event.id),
                                waitlisted: explore.waitlistedIDs.contains(event.id),
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
                .listOffset(Binding(get: { drag.listOffset }, set: { drag.listOffset = $0 }))
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

    /// Заклад з пошуку: шторку опускаємо, щоб бачити мапу, а стос відкриє `showPlace`, коли приїде видача.
    private func focusPlace(_ place: Place) {
        open(.peek)
        explore.focusPlace(place)
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
                    guard detent != .full || (drag.listOffset <= 0.5 && dy > 0) else { return }
                    listDrag = dy
                }
                guard let origin = listDrag else { return }
                let shift = dy - origin
                // Нижче порога список зникає разом із жестом, тож сідаємо на згорнуту звідси.
                if height(of: detent) - shift <= height(of: .peek) + Space.section {
                    listDrag = nil
                    open(.peek)
                    return
                }
                drag.value = shift
            }
            .onEnded { value in
                guard let origin = listDrag else { return }
                listDrag = nil
                settle(translation: value.translation.height - origin, predicted: value.predictedEndTranslation.height - origin)
            }
    }

    private var quietCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(Copy.nothing_here).font(PoruchFont.serifTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
            Text(Copy.nothing_here_hint)
                .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /// Лічильник шторки: з індексу, а не з `totalFound` чи завантажених карток.
    private var countLabel: String {
        if view.loading { return Copy.searching }
        return stackFocused ? Copy.events_here("\(view.listCount)") : Copy.events_found("\(view.listCount)")
    }

    /// Що показує екран: пін, область рукою чи ціле місто.
    private var areaLabel: String {
        if stackFocused { return Copy.area_stack }
        return view.customArea ? Copy.area_custom : "Знайдіть, куди піти у місті \(view.cityName)"
    }

    /// Перевести шторку в положення.
    private func open(_ target: SheetDetent) {
        if reduceMotion {
            drag.value = 0
            detent = target
        } else {
            withMotion(Motion.spring) {
                drag.value = 0
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

    /// Вибрана подія має бути в каруселі на своєму місці. Стос іншого піна її не покаже, тож його знімаємо;
    /// картку за краєм вікна довантажуємо; біля краю завантаженого просимо наступне вікно.
    private func reveal(_ id: String?) {
        guard let id else { return }
        if stackFocused, !view.stackIds.contains(id) { explore.resetStack() }
        guard !stackFocused, shownEvents.count < listEntries.count else { return }
        guard let position = shownEvents.firstIndex(where: { $0.id == id }) else {
            if listEntries.contains(where: { $0.id == id }) { model.app.loadCards(ids: [id]) }
            return
        }
        if position >= shownEvents.count - cardPrefetchAhead { loadHead(shownEvents.count + cardPage) }
    }

    /// Наступне вікно карток біля краю завантаженого.
    private func loadMore(reaching position: Int) {
        guard shownEvents.count < listEntries.count else { return }
        guard position >= shownEvents.count - cardPrefetchAhead else { return }
        loadHead(shownEvents.count + cardPage)
    }

    /// Картки початку показаного списку.
    private func loadHead(_ count: Int) { explore.loadHead(count) }
}

/// Ключ чипа «Усі»: не категорія, тож окремо від словника.
private let allKey = "*"

struct FiltersView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    /// Вибір накопичується і летить на сервер один раз по «Готово»: проміжних результатів за шторкою не видно.
    @State private var date: DateFilter?
    @State private var category: EventCategory?
    /// Категорію чіпали: nil у [category] тоді — «усі», а не «як було».
    @State private var categoryTouched = false
    @State private var available: Bool?

    private var pickedDate: DateFilter { date ?? model.state?.map.dateFilter ?? DateFilter.any }
    private var pickedCategory: EventCategory? { categoryTouched ? category : model.state?.map.category }
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
                    section(Copy.date) {
                        FlowLayout(spacing: Space.sm) {
                            ForEach(dateFilterKeys, id: \.self) { key in
                                Chip(label: dateLabel(key), selected: pickedDate == key) {
                                    date = pickedDate == key ? DateFilter.any : key
                                }
                            }
                        }
                    }
                    section(Copy.categories) {
                        FlexibleChips(
                            items: [(allKey, Copy.all, nil)] + categories.map { ($0.0.key, $0.1, $0.0) },
                            isSelected: { $0 == (pickedCategory?.key ?? allKey) }
                        ) { key in
                            let tapped = key == allKey ? nil : EventCategory.companion.fromKey(key: key)
                            category = pickedCategory == tapped ? nil : tapped
                            categoryTouched = true
                        }
                    }
                    Toggle(isOn: Binding(get: { pickedAvailable }, set: { available = $0 })) {
                        Text(Copy.only_available).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
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
            Text(Copy.filters).font(PoruchFont.serifTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            Button(Copy.reset_filters) {
                date = DateFilter.any
                category = nil
                categoryTouched = true
                available = false
            }
            .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.lg)
    }

    /// Прикріплена, не в скролі: у середньому положенні кнопка ховалась за згином.
    private var actions: some View {
        PrimaryButton(title: Copy.apply) { apply() }
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

/// Чипи з переносом за шириною, як `FlowRow` на Android.
struct FlexibleChips: View {
    /// (ключ, підпис, категорія для крапки або nil).
    let items: [(String, String, EventCategory?)]
    let isSelected: (String) -> Bool
    let action: (String) -> Void
    var body: some View {
        FlowLayout(spacing: Space.sm) {
            ForEach(items, id: \.0) { item in
                Chip(label: item.1, dot: item.2, selected: isSelected(item.0)) { action(item.0) }
            }
        }
    }
}

/// Рядки зліва направо; що не влазить — з нового рядка. Вбудованого flow layout у SwiftUI нема.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
        }
        return frames
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
            .toolbar { Button(Copy.apply) { dismiss() } }
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
/// Стан мапи складає спільний `ExplorePresenter` — та сама згортка, що й на Android. Тут лише спостережувана
/// обгортка: `@Observable` стежить за `state` поштучно, тож `DiscoveryView` перемальовується зі своїм станом.
@MainActor @Observable final class ExploreScreenModel {
    private(set) var state = ExploreScreenState.companion.Empty
    /// Набори, а не списки: кожна картка питає «я збережена?», і список був би лінійним пошуком через міст.
    private(set) var savedIDs: Set<String> = []
    private(set) var waitlistedIDs: Set<String> = []
    private let presenter: ExplorePresenter
    private var subscription: Subscription?

    init(app: PoruchApp) {
        presenter = ExplorePresenter(app: app)
        subscription = presenter.observe { [weak self] state in
            guard let self else { return }
            self.state = state
            let saved = Set(state.savedIds)
            if saved != savedIDs { savedIDs = saved }
            let waitlisted = Set(state.waitlistedIds)
            if waitlisted != waitlistedIDs { waitlistedIDs = waitlisted }
        }
    }

    func showStack(_ ids: [String]) { presenter.showStack(ids: ids) }
    func resetStack() { presenter.resetStack() }
    func clearStack() { presenter.clearStack() }
    func focusEvent(_ id: String) { presenter.focusEvent(id: id) }
    func focusPlace(_ place: Place) { presenter.focusPlace(place: place) }
    func toggleListCategory(_ category: EventCategory) { presenter.toggleListCategory(category: category) }
    func loadHead(_ count: Int) { presenter.loadHead(count: Int32(count)) }
    /// False для гостя: його ведуть на вхід.
    func toggleFollowStack() -> Bool { presenter.toggleFollowStack() }
    // Без `deinit`: модель живе стільки, скільки `AppModel`.
}
