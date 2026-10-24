import SwiftUI
import Shared
import CoreLocation

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

/// Мапа з пошуком і фільтрами зверху та шторкою (`DiscoverySheet`) знизу. Тут — те, що їх зв'язує: положення шторки,
/// камера, «Шукати тут», скинуті фільтри й шторки поверх мапи.
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
    /// Положення для «Ближче до мене»: без міста, бо порядок списку не має перемикати місто на екрані.
    @StateObject private var position = LocationFinder(resolvesCity: false)
    /// «Ближче до мене» натиснули, положення ще їде: чип уже вибраний, порядок — коли приїде.
    @State private var locating = false
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
    private var stackFocused: Bool { view.stackFocused }
    private var listEntries: [EventIndexEntry] { view.listEntries }
    /// Завантажені картки шторки. Може бути менше за `listEntries`: решту список просить сам.
    private var shownEvents: [Event] { view.deckEvents }

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
                moved: { region = $0 },
                // Що видно: фільтр, що лишив екран порожнім, веде до найближчої події (`ExplorePresenter.revealNearest`).
                visibleChanged: { explore.viewport($0) }
            )
            .ignoresSafeArea()
            // Під повною шторкою мапу не видно: VoiceOver не має ходити її пінами.
            .accessibilityHidden(detent == .full)
            LinearGradient(colors: [Palette.canvas.opacity(0.94), Palette.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 175).ignoresSafeArea(edges: .top).allowsHitTesting(false)
            VStack(spacing: Space.md) {
                TopControls(openFilters: { filters = true }, openCitySearch: { citySearch = true })
                AreaPrompts(mapFailed: $mapFailed, retryToken: $retryToken, undoFilters: $undoFilters, region: $region, restore: restore)
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Пошук і чипи під повною шторкою невидимі: фокус VoiceOver їх оминає.
            .accessibilityHidden(detent == .full)
            DiscoverySheet(
                detent: detent, drag: drag, expanded: $expanded, screen: screen, centerToken: centerToken,
                open: open, openDetail: { detail = EventRoute(id: $0) },
                recenter: { explore.clearStack(); centerToken += 1 }, locate: { location.request() },
                askAuth: { auth = true }, resetFilters: resetFilters, createEvent: createEvent,
                locating: locating, toggleNear: toggleNear
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
        .coachMarks([.sheet], enabled: !expanded && !shownEvents.isEmpty && detail == nil && !filters && !citySearch && !auth)
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
        // Вхід тут питають лише за «Стежити» на стосі закладу.
        .sheet(isPresented: $auth) { NavigationStack { AuthView(reason: .follow) } }
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
        // Перше положення після тапу — і список від нього. Наступні виміри порядок не смикають.
        .onReceive(position.$point) { point in
            guard locating, let point else { return }
            locating = false
            explore.nearMe(point, accuracy: position.accuracy)
        }
        .onReceive(position.$message) { message in
            guard locating, message != nil else { return }
            locating = false
            explore.nearMeUnavailable()
        }
        // Чесно: без геолокації «ближче» не порахувати, список лишився «для вас». Вихід — дозвіл у налаштуваннях.
        .sheet(isPresented: Binding(get: { position.message != nil }, set: { if !$0 { position.message = nil } })) {
            PromptSheet(
                title: Copy.location_title, message: Copy.nearer_me_denied, primary: Copy.open_settings, secondary: Copy.close,
                onPrimary: { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            )
        }
    }

    /// «Ближче до мене»: увімкнення питає положення наявним потоком геолокації, вимкнення повертає порядок «для вас».
    private func toggleNear() {
        if view.nearMe || locating {
            locating = false
            explore.clearNearMe()
        } else {
            locating = true
            position.request()
        }
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

    /// Картки початку показаного списку.
    private func loadHead(_ count: Int) { explore.loadHead(count) }
}

/// Пошук і ряд чипів над мапою. Один ряд замість двох: місто веде стрічку фільтрів. Керування мапою — над каруселлю,
/// під пальцем.
private struct TopControls: View {
    let openFilters: () -> Void
    let openCitySearch: () -> Void
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    private var view: ExploreScreenState { model.exploreScreen.state }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.md) {
            SearchBar(
                placeholder: Copy.search_placeholder,
                initial: view.searchText,
                activeFilters: Int(view.activeFilters),
                onFilters: openFilters
            ) { text in
                // Набраний пошук виводить із закладу в місто, як на Android. Луна тексту, який стер сам застосунок
                // (заклад з пошуку), — ні: інакше вона знімала б щойно відкритий стос цього закладу.
                if text != view.searchText { model.exploreScreen.resetStack() }
                model.app.setSearchText(query: text)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        Chip(label: view.cityName, glyph: PoruchIcons.pin, trailingGlyph: PoruchIcons.chevronDown, selected: false, action: openCitySearch)
                            // Назва — видимий текст (голосове «Натисни Київ»), а що робить — підказкою.
                            .accessibilityHint(Copy.a11y_change_city)
                        // Одразу після міста, а не за датами: з «Усі N» головної мапа приходить із цим фільтром, і його має бути видно.
                        Chip(label: Copy.from_people, glyph: PoruchIcons.social, selected: view.onlyAvailable) {
                            model.app.setOnlyAvailable(available: !view.onlyAvailable)
                        }
                        // Категорію з «Фільтрів» чи плиток видно тут, а не лише цифрою на кнопці фільтрів. Тап знімає її. Поруч із датами:
                        // коли ряд доїжджає до обраної дати, категорія лишається видно.
                        if let category = view.category {
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
}

/// Пігулки під пошуком: мапа не завантажилась, скинуті фільтри можна повернути, «Шукати тут».
private struct AreaPrompts: View {
    @Binding var mapFailed: Bool
    @Binding var retryToken: Int
    @Binding var undoFilters: FilterSnapshot?
    @Binding var region: MapRegion?
    let restore: (FilterSnapshot) -> Void
    @Environment(\.appModel) private var appModel

    var body: some View {
        if mapFailed {
            // Свій гліф, а не SF Symbol (DESIGN.md: SF Symbol лише для знака Apple). Пігулка — як решта над мапою.
            Button { mapFailed = false; retryToken += 1 } label: {
                HStack(spacing: Space.sm) {
                    PoruchIcon(glyph: PoruchIcons.refresh, size: 16)
                    Text(Copy.map_error_short).font(PoruchFont.label.weight(.semibold))
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, Space.lg).frame(minHeight: 44).cardSurface(radius: Corner.pill, elevation: Elevation.raised)
            }.buttonStyle(.plain)
        }
        if let undo = undoFilters {
            // Скидання з порожньої картки прибирає одразу кілька фільтрів: повернути їх — тим самим жестом, без пошуку.
            Button { restore(undo) } label: {
                HStack(spacing: Space.sm) {
                    Text(Copy.filters_reset).font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                    Text(Copy.undo).font(PoruchFont.label.weight(.semibold)).foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, Space.lg).frame(minHeight: 44).cardSurface(radius: Corner.pill, elevation: Elevation.raised)
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
                if let region { appModel!.app.searchArea(south: region.south, west: region.west, north: region.north, east: region.east) }
                region = nil
            }
            .fixedSize(horizontal: true, vertical: false)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}

/// Фільтри мапи, які скинула порожня картка: щоб повернути їх одним тапом.
private struct FilterSnapshot: Equatable {
    let date: DateFilter
    let category: EventCategory?
    let available: Bool
}

/// За скільки карток до кінця завантаженого просити наступні.
let cardPrefetchAhead = 8
/// Скільки карток додає одне довантаження.
let cardPage = 24

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
    func viewport(_ area: MapRegion) { presenter.viewport(south: area.south, west: area.west, north: area.north, east: area.east) }
    func clearStack() { presenter.clearStack() }
    func focusEvent(_ id: String) { presenter.focusEvent(id: id) }
    func focusPlace(_ place: Place) { presenter.focusPlace(place: place) }
    func toggleCategory(_ category: EventCategory) { presenter.toggleCategory(category: category) }
    func nearMe(_ point: CLLocationCoordinate2D, accuracy: Double) {
        presenter.nearMe(latitude: point.latitude, longitude: point.longitude, accuracy: accuracy)
    }
    func nearMeUnavailable() { presenter.nearMeUnavailable() }
    func clearNearMe() { presenter.clearNearMe() }
    func loadHead(_ count: Int) { presenter.loadHead(count: Int32(count)) }
    /// False для гостя: його ведуть на вхід.
    func toggleFollowStack() -> Bool { presenter.toggleFollowStack() }
    // Без `deinit`: модель живе стільки, скільки `AppModel`.
}
