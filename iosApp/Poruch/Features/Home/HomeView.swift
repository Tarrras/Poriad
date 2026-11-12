import SwiftUI
import Shared

/// Головна з двох зон: «Ваше» (плани, чати, підписки) і «У місті» (одна стрічка з даних, які вже завантажила мапа).
///
/// `Equatable` без полів: входи — лише замикання навігації від `RootView`, а той перемальовується на кожну
/// емісію стору й дає нові замикання. Без `.equatable()` SwiftUI вважав би їх зміною і перераховував тіло
/// головної на кожну емісію, хоч стан їй дає `HomeScreenModel` окремо.
struct HomeView: View, Equatable {
    static func == (lhs: HomeView, rhs: HomeView) -> Bool { true }

    /// Без підписки на весь `AppModel`: головна перемальовується зі своїм `HomeScreenState`, не з кожною емісією стору.
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    var openMap: () -> Void
    var openProfile: () -> Void
    /// Вкладка «Мої події»: посилання біля блоку «Ваше».
    var openMyEvents: () -> Void
    /// Редактор нової події; аргумент — звідки тап (`home_top`) для аналітики. Гостя спершу веде до входу.
    var createEvent: (String) -> Void
    /// Відкрити деталі; другий аргумент — квиток, з якого деталі виростають (`morphSource`). Шлях стосу тримає корінь
    /// (`RootView.homePath`).
    /// Деталі: id, квиток-джерело морфа й чи одразу до запитів («Запити · N»).
    var openEvent: (String, String?, Bool) -> Void
    /// Прямо в чат події, минаючи деталі.
    var openChat: (Event) -> Void
    /// Екран підписок: рядок у «Ваше».
    var openFollows: () -> Void

    private var view: HomeScreenState { model.homeScreen.state }
    @FocusState private var searchFocused: Bool
    /// Режим пошуку: вмикає тап по іконці, вимикає лише «Скасувати». Стрічка головної і фільтри
    /// пошуку ніколи не видно разом, тож стертий текст лишає в режимі з підказкою, а не повертає стрічку.
    @State private var searchMode = false
    /// Нове поле після «Скасувати»: набране, але ще не віддане нагору, інакше повернулося б за паузу.
    @State private var searchEpoch = 0
    /// Скільки результатів пошуку показано. «Показати ще» додає шматок.
    @State private var resultsLimit = homeResultsLimit
    /// Скільки рядків «У місті» показано.
    @State private var feedLimit = Int(HomeRules.shared.FEED_PAGE)
    /// Шторка вибору міста з шапки: та сама, що на мапі.
    @State private var citySearch = false
    /// Стос «Ваш тиждень» з головної: раз на тиждень, якщо цього тижня його не відкривали (docs/return-hooks.md).
    @AppStorage("poruch.deckWeek") private var deckWeek = ""
    @State private var deck: DeckCards?
    /// Ряд чипів «У місті» за верхом екрана, а сітка ще видна: він закріплений угорі.
    @State private var chipsPinned = false

    var body: some View {
        let view = self.view
        // У пошуку поле з фільтрами закріплене над стрічкою, а не в ній: `refreshable` стрічки діставався б
        // горизонтальним рядам чипів, і ті отримували власний індикатор оновлення та гойдалися вертикально.
        VStack(spacing: 0) {
            if searchActive(view) { header(view) }
            feed(view).refreshable { await model.reloadAll() }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .statusBarBand()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $citySearch) { CitySearchView().presentationDetents([.medium, .large]) }
        .fullScreenCover(item: $deck) { DeckView(cards: $0.events) { deck = nil } }
        .onChange(of: view.searchKey) { _, _ in resultsLimit = homeResultsLimit }
    }

    /// Текст, що лишився зі спільного стану, теж тримає режим: інакше фільтри діяли б невидимо.
    private func searchActive(_ view: HomeScreenState) -> Bool { searchMode || view.searching }

    /// Тап по іконці пошуку: поле з'являється закріпленим зверху, курсор одразу в ньому.
    private func startSearch() {
        withMotion { searchMode = true }
        searchFocused = true
    }

    /// «Скасувати»: текст і фільтри скидаються, фокус знімається, повертається стрічка.
    private func cancelSearch() {
        searchFocused = false
        searchEpoch += 1
        model.app.cancelHomeSearch()
        withMotion { searchMode = false }
    }

    private func header(_ view: HomeScreenState) -> some View {
        HomeHeader(
            view: view, searchActive: searchActive(view), searchEpoch: searchEpoch, focus: $searchFocused,
            startSearch: startSearch, cancelSearch: cancelSearch, openCitySearch: { citySearch = true }, selectTime: narrow
        )
    }

    private func feed(_ view: HomeScreenState) -> some View {
        ScrollViewReader { proxy in ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: 0).id(homeTop)
                // Поза пошуком шапка — перший рядок стрічки і прокручується разом з нею.
                if !searchActive(view) { header(view) }
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if view.searching {
                        SearchResults(view: view, resultsLimit: $resultsLimit, open: open, openMap: openMap)
                    } else if searchActive(view) {
                        EmptyState(
                            glyph: PoruchIcons.search, title: Copy.search_hint_title,
                            message: Copy.searching_scope("\(view.searchScope)")
                        ).padding(.horizontal, Space.page).padding(.top, Space.section)
                    } else {
                        // День події: квиток — перше, що відкривають на вході.
                        if !view.todayTickets.isEmpty { TodayTickets(tickets: view.todayTickets) }
                        // До першої видачі — один лоадер: секції, що приходили по черзі, штовхали одна одну (`HomeScreenState.ready`).
                        if view.ready {
                            // Серце продукту — з ким піти: зустрічі від людей і афіші, на які шукають компанію, однією рейкою,
                            // під нею порожній квиток «Організувати подію». Але першою лише тоді, коли їх досить
                            // (`peopleFirst`): інакше перший екран нової людини віддавали найтоншому шару, і вона йшла, не
                            // відкривши жодної події (критика 06.11). Тоді першою йде афіша, а «З ким піти» — рядками під нею.
                            let people: HomePeopleSection? = view.withWhomPending ? nil : HomePeopleSection(
                                view: view, open: open, showPeople: showPeople, createEvent: createEvent, openProfile: openProfile,
                                compact: !view.peopleFirst
                            )
                            if view.peopleFirst, let people { people }
                            // «Ваше» одразу після: непрочитаний чат і запит на участь не мають губитися під афішею. Усе особисте —
                            // плани, «Ваш тиждень», дати артистів, підписки — одним блоком у чотири рядки (критика довжини 28.10).
                            HomePersonalSection(
                                view: view, deckDue: deckWeek != view.deckWeek, open: open,
                                openRequests: openRequests, openChat: openChat,
                                openMyEvents: openMyEvents, openFollows: openFollows,
                                openDeck: {
                                    deckWeek = view.deckWeek
                                    deck = DeckCards(events: view.deck)
                                }
                            )
                            // Стрічки ще нема (порожнє місто, без мережі) — рядки над її станом, а не між квитками.
                            if !view.peopleFirst, view.feed.isEmpty, let people { people }
                            HomeCityFeed(
                                view: view, feedLimit: $feedLimit, open: open, showCity: showCity, openMap: openMap,
                                chipsPinned: $chipsPinned, selectChip: { selectChip($0, proxy: proxy) },
                                afterHeroes: view.peopleFirst ? nil : people.map { AnyView($0) }
                            )
                        } else {
                            PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
                        }
                    }
                }.padding(.top, Space.md).padding(.bottom, Space.section)
                .motion(value: view.ready)
            }
        }
        .morphScrollable()
        // Чипи «Сьогодні / Вихідні» під рукою, поки гортається сітка: п'ятничний вибір не за два екрани вгору.
        .overlay(alignment: .top) {
            if chipsPinned && !searchActive(view) {
                // Зверху на згасання смуги статусу (`statusBarBand`): чипи починаються там, де воно скінчилось.
                FeedChipsRow(chips: view.chips, selected: view.feedFilter) { selectChip($0, proxy: proxy) }
                    .padding(.top, Space.md).padding(.bottom, Space.sm)
                    .background(Palette.canvas)
                    .overlay(alignment: .bottom) { Divider().overlay(Palette.hairline) }
                    .transition(.opacity)
            }
        }
        // Повторний тап «Головна» в таббарі: сторінка на кілька екранів, а свій таббар системного «вгору» не має.
        .onReceive(NotificationCenter.default.publisher(for: .homeScrollToTop)) { _ in
            withMotion { proxy.scrollTo(homeTop, anchor: .top) }
        }
        }
    }

    /// Чип «У місті»: звузити сітку з першої сторінки; з закріпленого ряду — ще й на початок сітки, бо вона змінилась.
    private func selectChip(_ chip: FeedFilter, proxy: ScrollViewProxy) {
        let pinned = chipsPinned
        narrow(chip)
        if pinned { withMotion { proxy.scrollTo(homeFeedChips, anchor: .top) } }
    }

    /// Чип часу з шапки чи сітки: афіша з першої сторінки.
    private func narrow(_ chip: FeedFilter) {
        withMotion { model.homeScreen.selectFeedFilter(chip) }
        feedLimit = Int(HomeRules.shared.FEED_PAGE)
    }

    /// Відкрити деталі події; `from` — звідки тап, для аналітики й морфа: квиток з `morphSource("\(from)/\(id)")` розгортається
    /// в деталі. Без такого джерела на екрані zoom виростав би з центру, тож джерело мають усі квитки, що кличуть `open`.
    private func open(_ id: String, from: String) {
        model.app.selectEvent(id: id, from: from)
        openEvent(id, "\(from)/\(id)", false)
    }

    /// «Запити · N» на квитку найближчого плану: ті самі деталі, але одразу на запитах.
    private func openRequests(_ id: String) {
        model.app.selectEvent(id: id, from: "home_your")
        openEvent(id, "home_your/\(id)", true)
    }

    /// «Усі N» біля «У місті»: мапа з усім містом, а не з фільтрами, що лишились з минулого візиту.
    private func showCity() { model.app.showEverythingOnMap(); openMap() }

    /// «Усі N» біля «Від людей»: мапа лише зі зустрічами від людей з вільним місцем.
    private func showPeople() { model.app.showPeopleOnMap(); openMap() }
}

/// Шапка головної. Поза пошуком — місто заголовком і кнопка пошуку (профіль — вкладка таббару, другого входу не треба),
/// під ними чипи часу; у пошуку — поле, «Скасувати» і фільтри.
private struct HomeHeader: View {
    let view: HomeScreenState
    let searchActive: Bool
    /// Нове поле після «Скасувати» (`HomeView.searchEpoch`).
    let searchEpoch: Int
    let focus: FocusState<Bool>.Binding
    let startSearch: () -> Void
    let cancelSearch: () -> Void
    let openCitySearch: () -> Void
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    /// Шторка вибору категорії з пошуку.
    @State private var categoryPicker = false
    /// Чип часу під містом (`HomeView.narrow`).
    let selectTime: (FeedFilter) -> Void

    /// Місто заголовком: назва в один рядок і дрібнішає до половини, бо у два рядки шеврон відставав від останнього
    /// слова («…міська громада      ⌄»): гліф — шлях, а не символ тексту.
    private var cityButton: some View {
        Button(action: openCitySearch) {
            HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                Text(view.cityName.isEmpty ? Copy.home_title : view.cityName)
                    .font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                PoruchIcon(glyph: PoruchIcons.chevronDown, size: 20).foregroundStyle(Palette.ink.opacity(0.6))
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityLabel(Copy.a11y_city("\(view.cityName)"))
        .accessibilityHint(Copy.a11y_change_city)
        .accessibilityAddTraits(.isHeader)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            // Під час пошуку великий заголовок ховається: місце — фільтрам і результатам.
            if !searchActive {
                // Заголовок — саме місто: «Що поруч» над ним нічого не казав і забирав рядок першого екрана, а єдине
                // корисне в шапці, місто, було найдрібнішим (критика шапки 07.11). Тап міняє місто тут же, без мапи.
                // Під містом — коли: «Сьогодні / Вихідні» на першому екрані, а не на дні його над сіткою (вибір власника 07.11).
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .center) {
                        cityButton
                        Spacer(minLength: Space.sm)
                        IconPill(glyph: PoruchIcons.search, label: Copy.search_scope("\(view.searchScope)"), action: startSearch)
                    }
                    .padding(.horizontal, Space.page)
                    if !view.timeChips.isEmpty {
                        FeedChipsRow(chips: view.timeChips, selected: view.feedTime, select: selectTime)
                    }
                }
            } else {
                HStack(spacing: Space.md) {
                    SearchBar(placeholder: Copy.search_scope("\(view.searchScope)"), initial: view.searchText) {
                        model.app.setHomeSearchText(query: $0)
                    }
                    .id(searchEpoch)
                    .focused(focus)
                    Button(action: cancelSearch) { Text(Copy.delete_account_cancel).tapTarget() }
                        .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .padding(.horizontal, Space.page)
                searchFilters
            }
        }
        .padding(.top, searchActive ? Space.md : Space.xl).padding(.bottom, Space.md)
        .motion(value: searchActive)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Де й що шукати: місто чи всюди, дата, категорія. Ті самі чипи й підписи, що на мапі.
    private var searchFilters: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    Chip(label: view.cityName, glyph: PoruchIcons.pin, selected: !view.searchEverywhere) {
                        model.app.setHomeSearchEverywhere(everywhere: false)
                    }
                    Chip(label: Copy.everywhere, glyph: PoruchIcons.globe, selected: view.searchEverywhere) {
                        model.app.setHomeSearchEverywhere(everywhere: true)
                    }
                    Divider().frame(height: 24).overlay(Palette.hairline)
                    ForEach(dateFilterKeys, id: \.self) { key in
                        // Повторний тап знімає вибір, як на мапі.
                        Chip(label: dateLabel(key), selected: view.searchDate == key) {
                            model.app.setHomeSearchDate(filter: view.searchDate == key ? DateFilter.any : key)
                        }
                    }
                    // Категорії — одним чипом зі шторкою: дванадцять чипів другим рядом були стіною вибору.
                    Chip(
                        label: view.searchCategory.map { categoryName($0) } ?? Copy.category_single,
                        dot: view.searchCategory, trailingGlyph: PoruchIcons.chevronDown,
                        selected: view.searchCategory != nil
                    ) { categoryPicker = true }
                }
            }.railContentPadding(spread: 0)
        }
        .sheet(isPresented: $categoryPicker) {
            CategoryPickerSheet(selected: view.searchCategory) { category in
                categoryPicker = false
                model.app.setHomeSearchCategory(category: category)
            }
        }
    }
}

/// Результати пошуку одним списком.
private struct SearchResults: View {
    let view: HomeScreenState
    /// Скільки результатів показано (`HomeView.resultsLimit`).
    @Binding var resultsLimit: Int
    let open: (String, String) -> Void
    let openMap: () -> Void
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }

    var body: some View {
        if let city = view.cityMatch {
            BannerCard(
                title: Copy.home_switch_city("\(city.city)"),
                subtitle: Copy.home_switch_city_hint("\(view.cityName)"),
                glyph: PoruchIcons.pin
            ) {
                // Спершу текст: інакше «Харків» лишився б фільтром і в новому місті.
                model.app.setHomeSearchText(query: "")
                model.app.selectCity(city: CityResult(name: city.city, latitude: city.latitude, longitude: city.longitude))
            }.padding(.horizontal, Space.page)
        }
        if view.searchLoading && view.results.isEmpty && view.districts.isEmpty && view.places.isEmpty && view.artists.isEmpty {
            PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
        } else if view.results.isEmpty && view.districts.isEmpty && view.places.isEmpty && view.artists.isEmpty {
            if view.searchEverywhere {
                EmptyState(
                    glyph: PoruchIcons.search, title: Copy.nothing_found,
                    message: Copy.nothing_found_hint
                )
            } else {
                EmptyState(
                    glyph: PoruchIcons.search, title: Copy.nothing_found,
                    message: Copy.nothing_found_city("\(view.cityName)"),
                    actionLabel: Copy.search_everywhere, action: { model.app.setHomeSearchEverywhere(everywhere: true) }
                )
            }
        } else {
            // Події, під ними — заклади з тим самим словом. Групові списки: видача пошуку — перелік, а не стрічка.
            VStack(alignment: .leading, spacing: Space.xl) {
                // Район — першим, як на мапі: це рядок-два, і «Київський» найчастіше саме про нього.
                let localities = view.districts.filter { $0.district.isLocality }
                let adminDistricts = view.districts.filter { !$0.district.isLocality }
                if !adminDistricts.isEmpty {
                    DistrictsGroup(districts: adminDistricts) { hit in
                        model.app.selectDistrict(hit: hit, fromHome: true)
                        openMap()
                    }
                }
                if !localities.isEmpty {
                    DistrictsGroup(districts: localities, title: Copy.search_localities_group) { hit in
                        model.app.selectDistrict(hit: hit, fromHome: true)
                        openMap()
                    }
                }
                if !view.results.isEmpty {
                    let total = max(Int(view.resultsTotal), view.results.count)
                    let shown = view.results(limit: resultsLimit)
                    VStack(alignment: .leading, spacing: Space.sm) {
                        // «На мапі» несе запит на мапу явно: інакше пошуки екранів незалежні. Мапа — лише обране місто,
                        // тож для пошуку всюди вона показала б менше.
                        GroupLabel(
                            title: Copy.search_events_group("\(total)"),
                            actionLabel: view.searchEverywhere ? nil : Copy.on_map,
                            action: { model.app.setSearchText(query: view.searchText); openMap() }
                        )
                        GroupedRows {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { position, event in
                                if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, resultRowInset) }
                                EventResultRow(event: event, waitlisted: view.isWaitlisted(event), withCity: view.searchEverywhere) {
                                    open(event.id, "home_search")
                                }
                                .morphSource("home_search/\(event.id)")
                            }
                        }
                        // Наступний шматок: картки, яких ще немає, довантажуються; решта приїде в `found`.
                        if view.resultIDs.count > resultsLimit {
                            SecondaryButton(title: Copy.show_more) {
                                resultsLimit += homeResultsLimit
                                model.app.loadCards(ids: Array(view.resultIDs.prefix(resultsLimit)))
                            }
                        }
                    }
                }
                if !view.places.isEmpty {
                    PlacesGroup(places: view.places, withCity: view.searchEverywhere) { place in
                        model.app.focusPlace(place: place)
                        openMap()
                    }
                }
                if !view.artists.isEmpty { ArtistsGroup(artists: view.artists) }
            }.padding(.horizontal, Space.page)
        }
    }
}

/// Шторка категорії для пошуку: плитки всіх категорій і «Усі категорії». Відповідь спершу закриває шторку, потім діє.
private struct CategoryPickerSheet: View {
    let selected: EventCategory?
    let select: (EventCategory?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(Copy.categories).font(PoruchFont.brandTitle2).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Space.sm)], spacing: Space.lg) {
                ForEach(categories, id: \.0) { entry in
                    CategoryTile(category: entry.0, selected: selected == entry.0) {
                        select(selected == entry.0 ? nil : entry.0)
                    }
                }
            }
            SecondaryButton(title: Copy.all_categories) { select(nil) }
        }
        .padding(.horizontal, Space.page).padding(.top, Space.xl).padding(.bottom, Space.lg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvas)
    }
}

/// Мітка початку стрічки головної: туди веде повторний тап «Головна».
private let homeTop = "home-top"

extension Notification.Name {
    /// Повторний тап «Головна» в таббарі, коли стос уже на корені: головна гортає вгору.
    static let homeScrollToTop = Notification.Name("poruch.homeScrollToTop")
}
