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
    /// Редактор нової події; аргумент — звідки тап (`home_top`, `home_footer`) для аналітики. Гостя спершу веде до входу.
    var createEvent: (String) -> Void
    /// Відкрити деталі. Шлях стосу тримає корінь (`RootView.homePath`).
    var openEvent: (String) -> Void
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
            startSearch: startSearch, cancelSearch: cancelSearch, openProfile: openProfile, openCitySearch: { citySearch = true }
        )
    }

    private func feed(_ view: HomeScreenState) -> some View {
        ScrollView {
            VStack(spacing: 0) {
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
                        // Серце продукту — зустрічі від людей, тож вони й порожній квиток «Організувати подію» стоять першими.
                        // Афіша нижче — опора. Активності не вигадуємо: коли зустрічей мало, секцію веде порожній квиток.
                        HomePeopleSection(view: view, open: open, showPeople: showPeople, createEvent: createEvent, openProfile: openProfile)
                        if !view.company.isEmpty { HomeCompanySection(view: view, open: open) }
                        if view.signedIn {
                            HomePersonalSection(view: view, open: open, openChat: openChat, openMyEvents: openMyEvents, openFollows: openFollows)
                        }
                        HomeCityFeed(view: view, feedLimit: $feedLimit, open: open, showCity: showCity, openMap: openMap)
                        // Кінець стрічки не глухий кут: далі мапа чи власна подія.
                        if !view.feed.isEmpty { moreRows(view) }
                    }
                }.padding(.top, Space.md).padding(.bottom, Space.section)
            }
        }
    }

    /// Куди далі, коли стрічку переглянуто: мапа з усім, що є, і створення власної події.
    private func moreRows(_ view: HomeScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.next)
            GroupedRows {
                LinkRow(
                    glyph: PoruchIcons.map, title: Copy.all_events_section,
                    subtitle: Copy.all_events_hint,
                    value: view.totalFound > 0 ? "\(view.totalFound)" : nil, action: showCity
                )
                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                LinkRow(glyph: PoruchIcons.sparkle, title: Copy.create_banner_title, subtitle: Copy.create_banner_subtitle) { createEvent("home_footer") }
            }
        }.padding(.horizontal, Space.page)
    }

    /// Відкрити деталі події; `from` — звідки тап, для аналітики.
    private func open(_ id: String, from: String) { model.app.selectEvent(id: id, from: from); openEvent(id) }

    /// «Усі N» біля «У місті» і рядок «Усі події поруч»: мапа з усім містом, а не з фільтрами, що лишились з минулого візиту.
    private func showCity() { model.app.showEverythingOnMap(); openMap() }

    /// «Усі N» біля «Від людей»: мапа лише зі зустрічами від людей з вільним місцем.
    private func showPeople() { model.app.showPeopleOnMap(); openMap() }
}

/// Шапка головної. Поза пошуком — заголовок, місто й кнопки пошуку та профілю; у пошуку — поле, «Скасувати» і фільтри.
private struct HomeHeader: View {
    let view: HomeScreenState
    let searchActive: Bool
    /// Нове поле після «Скасувати» (`HomeView.searchEpoch`).
    let searchEpoch: Int
    let focus: FocusState<Bool>.Binding
    let startSearch: () -> Void
    let cancelSearch: () -> Void
    let openProfile: () -> Void
    let openCitySearch: () -> Void
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    /// Шторка вибору категорії з пошуку.
    @State private var categoryPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            // Під час пошуку великий заголовок ховається: місце — фільтрам і результатам.
            if !searchActive {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(Copy.home_title).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                        // Тап міняє місто тут же, без переходу на мапу. Шеврон — частина тексту: довга назва
                        // переноситься разом із ним. Колір темніший за `inkSecondary`: на сяйві той дає лише ≈4:1.
                        Button(action: openCitySearch) {
                            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                                Text(view.cityName).font(PoruchFont.subhead).multilineTextAlignment(.leading)
                                PoruchIcon(glyph: PoruchIcons.chevronDown, size: 14)
                            }
                            .foregroundStyle(Palette.ink.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Copy.a11y_city("\(view.cityName)"))
                        .accessibilityHint(Copy.a11y_change_city)
                        .coachTarget(.city)
                    }
                    Spacer(minLength: Space.sm)
                    HStack(spacing: Space.sm) {
                        IconPill(glyph: PoruchIcons.search, label: Copy.search_scope("\(view.searchScope)"), action: startSearch)
                        IconPill(glyph: PoruchIcons.person, label: Copy.profile, action: openProfile)
                    }
                }
                .padding(.horizontal, Space.page)
            } else {
                HStack(spacing: Space.md) {
                    SearchBar(placeholder: Copy.search_scope("\(view.searchScope)"), initial: view.searchText) {
                        model.app.setHomeSearchText(query: $0)
                    }
                    .id(searchEpoch)
                    .focused(focus)
                    Button(Copy.delete_account_cancel, action: cancelSearch)
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
