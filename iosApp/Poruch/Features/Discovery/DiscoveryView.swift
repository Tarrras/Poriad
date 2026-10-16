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
    /// «Створити» з порожньої шторки: той самий шлях, що в кнопки біля таббару (гостя — на вхід).
    var createEvent: (String) -> Void = { _ in }
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
    /// Що скинула кнопка порожньої картки: кілька секунд їх можна повернути одним тапом.
    @State private var undoFilters: FilterSnapshot?
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
                if let undo = undoFilters {
                    // Скидання з порожньої картки прибирає одразу кілька фільтрів: повернути їх — тим самим жестом, без пошуку.
                    Button { restore(undo) } label: {
                        HStack(spacing: Space.sm) {
                            Text(Copy.filters_reset).font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                            Text(Copy.undo).font(PoruchFont.label.weight(.semibold)).foregroundStyle(Palette.ink)
                        }
                        .padding(.horizontal, Space.lg).frame(minHeight: 44).cardSurface(radius: 22, elevation: 6)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .task(id: undo) {
                        try? await Task.sleep(for: .seconds(6))
                        if undoFilters == undo { undoFilters = nil }
                    }
                }
                if region != nil {
                    PrimaryButton(title: Copy.search_here, glyph: PoruchIcons.refresh) {
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
        .motion(value: undoFilters == nil)
        // Підказка першого знайомства: де список і що таке пін із числом. Лише над згорнутою шторкою з картками,
        // коли поверх мапи нічого не відкрито.
        .coachMarks([.sheet], enabled: !expanded && !deckEvents.isEmpty && detail == nil && !filters && !citySearch && !auth)
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
            PromptSheet(title: Copy.location_title, message: location.message ?? "", primary: Copy.ok, onPrimary: {})
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
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        Chip(label: view.cityName, glyph: PoruchIcons.pin, trailingGlyph: PoruchIcons.chevronDown, selected: false) { citySearch = true }
                            .accessibilityLabel(Copy.a11y_change_city)
                        // Одразу після міста, а не за датами: з «Усі N» головної мапа приходить із цим фільтром, і його має бути видно.
                        Chip(label: Copy.from_people, glyph: PoruchIcons.social, selected: view.onlyAvailable) {
                            model.app.setOnlyAvailable(available: !view.onlyAvailable)
                        }
                        // Категорію з «Фільтрів» чи плиток видно тут, а не лише цифрою на кнопці фільтрів. Тап знімає її. Поруч із датами:
                        // коли ряд доїжджає до обраної дати, категорія лишається видно.
                        if let category {
                            Chip(label: categoryName(category), dot: category, trailingGlyph: PoruchIcons.close, selected: true) {
                                model.app.setCategory(category: nil)
                            }
                            .accessibilityLabel(Copy.a11y_clear_category(categoryName(category)))
                        }
                        // «Будь-коли» лише у «Фільтрах»: тут повторний тап і так знімає дату, а зайвий чип виштовхував обрану за край.
                        ForEach(dateFilterKeys.filter { $0 != DateFilter.any }, id: \.self) { key in
                            Chip(label: dateLabel(key), selected: view.dateFilter == key) {
                                model.app.setDateFilter(filter: view.dateFilter == key ? DateFilter.any : key)
                            }
                            .id(key)
                        }
                    }
                }
                // Поля всередині смуги, тож смуга йде від краю до краю.
                .railContentPadding()
                .padding(.horizontal, -Space.page)
                // Дата, обрана у «Фільтрах», лягала за край ряду, і видно було лише цифру на кнопці.
                .onChange(of: view.dateFilter, initial: true) { _, key in
                    guard key != DateFilter.any else { return }
                    if reduceMotion { proxy.scrollTo(key) } else { withAnimation { proxy.scrollTo(key) } }
                }
            }
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
    @ScaledMetric(relativeTo: .body) private var cardHeight = mapCardHeight
    private var peekHeight: CGFloat { 44 + deckGap + Space.sm + scaledMapCardHeight(cardHeight) + tabBarInset }

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
            // До міста — без стосу піна: інакше мапа стояла на місті, а шторка далі казала «Тут подій: 10».
            IconPill(glyph: PoruchIcons.recenter, label: Copy.recenter, size: 40) {
                explore.clearStack(); centerToken += 1
            }
            IconPill(glyph: PoruchIcons.myLocation, label: Copy.nearby, size: 40) { location.request() }
            Spacer(minLength: 0)
            // Не `Button`: кнопка забирає дотик, і протягнути шторку за неї не виходить.
            HStack(spacing: Space.sm) {
                if view.loading { ProgressView().controlSize(.mini) }
                else if view.offline {
                    PoruchIcon(glyph: PoruchIcons.wifiOff, size: 15).foregroundStyle(Palette.accent)
                }
                // Зі «Стежити» чи на великому шрифті «Тут подій: 12» не влазить: лишається число, а не «Тут по…».
                // Повний текст VoiceOver чує з підпису кнопки.
                ViewThatFits(in: .horizontal) {
                    Text(countLabel).lineLimit(1)
                    Text(view.loading ? countLabel : view.offline ? Copy.offline_count("\(view.listCount)") : "\(view.listCount)")
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .font(PoruchFont.label).foregroundStyle(Palette.ink)
                PoruchIcon(glyph: PoruchIcons.chevronUp, size: 14).foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, Space.lg).frame(height: 40)
            .cardSurface(radius: 20, elevation: 6)
            .contentShape(Capsule())
            .onTapGesture { open(.half) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Copy.a11y_show_list("\(countLabel)"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(.half) }
            .coachTarget(.sheet)
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
                // Стос закладу — це заклад: назва заголовком, а не «усе, що стоїть на обраному піні». Кондензом, як
                // заголовки решти шторок.
                Text(stackPlace?.name ?? countLabel).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink).lineLimit(2)
                Text(stackPlace != nil ? countLabel : areaLabel).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                // Під підписом, а не в ряду: лічильник і дві кнопки праворуч не лишають йому місця.
                if stackPlace != nil { followButton(iconOnly: false).padding(.top, Space.sm) }
            }
            Spacer(minLength: Space.sm)
            if stackFocused { clearStackButton }
            IconPill(glyph: PoruchIcons.chevronDown, label: Copy.show_map) { open(.peek) }
        }
        .padding(.bottom, Space.md)
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
    }

    /// Вихід із фокуса на піні знімає і підсвітку, інакше мапа й список розходились.
    private var clearStackButton: some View {
        IconPill(glyph: PoruchIcons.close, label: Copy.show_all_events) {
            explore.clearStack()
        }
    }

    /// «Стежити» за закладом стосу. Гостя ведемо на вхід: пуш прив'язаний до акаунта.
    @ViewBuilder private func followButton(iconOnly: Bool) -> some View {
        if let place = stackPlace {
            FollowPill(following: view.stackFollowing, iconOnly: iconOnly) {
                if !explore.toggleFollowStack() { auth = true }
            }
            // Дзвінок без підпису в згорнутій шапці: VoiceOver має чути, за чим стежити.
            .accessibilityLabel(view.stackFollowing ? Copy.a11y_unfollow_name(place.name) : Copy.a11y_follow_name(place.name))
        }
    }

    private var sheetList: some View {
        VStack(spacing: 0) {
            // У стосі закладу плиток нема: категорія — фільтр міста, і тап по ній виводив із закладу в усе місто.
            if !stackFocused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) {
                        ForEach(categories, id: \.0) { entry in
                            // Та сама категорія, що у «Фільтрах»: звужує й мапу.
                            CategoryTile(category: entry.0, selected: category == entry.0) {
                                explore.toggleCategory(entry.0)
                            }
                        }
                    }
                }.railContentPadding()
            }
            if shownEvents.isEmpty && places.isEmpty && artists.isEmpty {
                if view.loading {
                    PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
                } else {
                    quietCard.padding(Space.page)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.sm) {
                        // Заклади — над подіями: список подій довгий, під ним їх ніхто б не побачив.
                        if !places.isEmpty {
                            PlacesGroup(places: places) { focusPlace($0) }.padding(.bottom, Space.md)
                        }
                        if !artists.isEmpty { ArtistsGroup(artists: artists).padding(.bottom, Space.md) }
                        // Рядки з малим корінцем, як у пошуку головної: список відкривають, щоб зіставити варіанти, і
                        // картка з фото 180 давала півтори події на екран. Фото й «Зберегти» — на картці каруселі й у деталях.
                        ForEach(Array(shownEvents.enumerated()), id: \.element.id) { position, event in
                            EventResultRow(event: event, waitlisted: explore.waitlistedIDs.contains(event.id)) {
                                model.app.selectEvent(id: event.id); detail = EventRoute(id: event.id)
                            }
                            .cardSurface()
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

    /// Порожньо: називаємо те, що справді звужує видачу, і даємо одну дію — прибрати це або зібрати своїх.
    private var quietCard: some View {
        let query = view.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Дія — у рядку заголовка: у згорнутій шторці картка має висоту каруселі, і під текстом дія зрізала підказку.
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(Copy.nothing_here).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                if !query.isEmpty {
                    quietAction(Copy.clear_search) { model.app.setSearchText(query: "") }
                } else if activeFilters > 0 {
                    quietAction(Copy.reset_filters_action) { resetFilters() }
                } else {
                    quietAction(Copy.create) { createEvent("map") }
                }
            }
            Text(query.isEmpty ? Copy.nothing_here_hint : Copy.nothing_for_query(query))
                .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /// Текстова дія порожньої картки: картка лежить над мапою в згорнутій шторці, повна кнопка 52 її б не вмістила.
    private func quietAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(PoruchFont.button).foregroundStyle(Palette.ink)
        }
        .tapTarget()
    }

    private func resetFilters() {
        undoFilters = FilterSnapshot(date: view.dateFilter, category: category, available: view.onlyAvailable)
        apply(FilterSnapshot(date: DateFilter.any, category: nil, available: false))
    }

    private func restore(_ snapshot: FilterSnapshot) {
        undoFilters = nil
        apply(snapshot)
    }

    /// Лише те, що відрізняється: кожен зайвий виклик — ще один запит до сервера.
    private func apply(_ target: FilterSnapshot) {
        if view.dateFilter != target.date { model.app.setDateFilter(filter: target.date) }
        if category != target.category { model.app.setCategory(category: target.category) }
        if view.onlyAvailable != target.available { model.app.setOnlyAvailable(available: target.available) }
    }

    /// Лічильник шторки: з індексу, а не з `totalFound` чи завантажених карток.
    private var countLabel: String {
        if view.loading { return Copy.searching }
        let count = stackFocused ? Copy.events_here("\(view.listCount)") : Copy.events_found("\(view.listCount)")
        // Офлайн словами, а не лише гліфом: видача — збережена, і це треба знати.
        return view.offline ? Copy.offline_count(count) : count
    }

    /// Що показує екран: пін, область рукою чи ціле місто.
    private var areaLabel: String {
        if stackFocused { return Copy.area_stack }
        return view.customArea ? Copy.area_custom : Copy.area_city("\(view.cityName)")
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

/// Кожен вибір діє одразу, як чипи над мапою: за шторкою видно, що змінилось, а кнопка каже, скільки знайдеться.
/// Скасування не треба — вибір знімається тим самим тапом, «Скинути» прибирає все.
struct FiltersView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    private var explore: ExploreScreenState { model.exploreScreen.state }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    section(Copy.date) {
                        FlowLayout(spacing: Space.sm) {
                            ForEach(dateFilterKeys, id: \.self) { key in
                                Chip(label: dateLabel(key), selected: explore.dateFilter == key) {
                                    model.app.setDateFilter(filter: explore.dateFilter == key ? DateFilter.any : key)
                                }
                            }
                        }
                    }
                    section(Copy.categories) {
                        // Ті самі плитки, що в шторці мапи й у редакторі: жанр обирають однаково скрізь. Повторний тап знімає вибір.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Space.sm)], spacing: Space.md) {
                            ForEach(categories, id: \.0) { entry in
                                CategoryTile(category: entry.0, selected: explore.category == entry.0) {
                                    model.exploreScreen.toggleCategory(entry.0)
                                }
                            }
                        }
                    }
                    // Та сама назва, що в чипа над мапою: один фільтр — одне ім'я, а що він робить — підписом.
                    Toggle(isOn: Binding(get: { explore.onlyAvailable }, set: { model.app.setOnlyAvailable(available: $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Copy.from_people).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                            Text(Copy.from_people_hint).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        }
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
            Text(Copy.filters).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            Button(Copy.reset_filters) { reset() }
                .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                .disabled(explore.activeFilters == 0)
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.lg)
    }

    private func reset() {
        if explore.dateFilter != DateFilter.any { model.app.setDateFilter(filter: DateFilter.any) }
        if explore.category != nil { model.app.setCategory(category: nil) }
        if explore.onlyAvailable { model.app.setOnlyAvailable(available: false) }
    }

    /// Кнопка каже, що вийде: «Показати 23 події», а не «Готово» навмання. Прикріплена, не в скролі: у середньому
    /// положенні вона ховалась за згином.
    private var actions: some View {
        PrimaryButton(title: resultTitle, loading: explore.loading) { dismiss() }
            .frame(maxWidth: .infinity)
            .padding(Space.page)
            .background(Palette.surface.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private var resultTitle: String {
        if explore.loading { return Copy.searching }
        let count = Int(explore.listCount)
        return count == 0 ? Copy.show_nothing : Copy.show_events(count)
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
                    Section(Copy.cities_with_events) {
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
            .searchable(text: $query, prompt: Text(Copy.city_search_prompt))
            // Без автофокуса: `searchFocused` з iOS 18, мінімум проєкту — 17.
            .onSettled(query, after: .milliseconds(220)) { model.app.searchCity(query: $0) }
            .navigationTitle(Copy.find_city)
            .toolbar { Button(Copy.apply) { dismiss() } }
        }
    }
}

/// Фільтри мапи, які скинула порожня картка: щоб повернути їх одним тапом.
private struct FilterSnapshot: Equatable {
    let date: DateFilter
    let category: EventCategory?
    let available: Bool
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
    func toggleCategory(_ category: EventCategory) { presenter.toggleCategory(category: category) }
    func loadHead(_ count: Int) { presenter.loadHead(count: Int32(count)) }
    /// False для гостя: його ведуть на вхід.
    func toggleFollowStack() -> Bool { presenter.toggleFollowStack() }
    // Без `deinit`: модель живе стільки, скільки `AppModel`.
}
