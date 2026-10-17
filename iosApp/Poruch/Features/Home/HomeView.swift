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
    /// Шторка вибору категорії з пошуку.
    @State private var categoryPicker = false

    var body: some View {
        let view = self.view
        // У пошуку поле з фільтрами закріплене над стрічкою, а не в ній: `refreshable` стрічки діставався б
        // горизонтальним рядам чипів, і ті отримували власний індикатор оновлення та гойдалися вертикально.
        VStack(spacing: 0) {
            if searchActive(view) { headerView(view) }
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

    private func feed(_ view: HomeScreenState) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Поза пошуком шапка — перший рядок стрічки і прокручується разом з нею.
                if !searchActive(view) { headerView(view) }
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if view.searching {
                        searchResults(view)
                    } else if searchActive(view) {
                        EmptyState(
                            glyph: PoruchIcons.search, title: Copy.search_hint_title,
                            message: Copy.searching_scope("\(view.searchScope)")
                        ).padding(.horizontal, Space.page).padding(.top, Space.section)
                    } else {
                        // Серце продукту — зустрічі від людей, тож вони й порожній квиток «Організувати подію» стоять першими.
                        // Афіша нижче — опора. Активності не вигадуємо: коли зустрічей мало, секцію веде порожній квиток.
                        peopleSection(view)
                        if view.signedIn { personalSection(view) }
                        cityFeed(view)
                        // Кінець стрічки не глухий кут: далі мапа чи власна подія.
                        if !view.feed.isEmpty { moreRows(view) }
                    }
                }.padding(.top, Space.md).padding(.bottom, Space.section)
            }
        }
    }

    private func headerView(_ view: HomeScreenState) -> some View {
        let searchActive = searchActive(view)
        return VStack(alignment: .leading, spacing: Space.lg) {
            // Під час пошуку великий заголовок ховається: місце — фільтрам і результатам.
            if !searchActive {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(Copy.home_title).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                        // Тап міняє місто тут же, без переходу на мапу. Шеврон — частина тексту: довга назва
                        // переноситься разом із ним. Колір темніший за `inkSecondary`: на сяйві той дає лише ≈4:1.
                        Button { citySearch = true } label: {
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
                    .focused($searchFocused)
                    Button(Copy.delete_account_cancel, action: cancelSearch)
                        .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .padding(.horizontal, Space.page)
                searchFilters(view)
            }
        }
        .padding(.top, searchActive ? Space.md : Space.xl).padding(.bottom, Space.md)
        .motion(value: searchActive)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Де й що шукати: місто чи всюди, дата, категорія. Ті самі чипи й підписи, що на мапі.
    private func searchFilters(_ view: HomeScreenState) -> some View {
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

    /// Рядок входу для гостя: плашка вгорі — єдина головна дія, а вхід — для тих, хто вже має профіль, тож без картки й заливки.
    private var guestLoginRow: some View {
        Button(action: openProfile) {
            HStack(spacing: Space.sm) {
                PoruchIcon(glyph: PoruchIcons.lock, size: 16)
                Text(Copy.guest_home_slim).font(PoruchFont.label)
                Spacer(minLength: Space.sm)
                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 15)
            }
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, Space.xs).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityLabel(Copy.guest_home_slim)
    }

    /// «Від людей»: зустрічі з вільним місцем рейкою квитків (коли їх набралось досить, `HomeRules.people`) і під нею
    /// порожній квиток «Організувати подію». Секція є завжди: навіть без зустрічей вона каже, що свою можна зібрати.
    /// Гостю під квитком лише тихий рядок входу (без картки): дві картки поспіль товпились би.
    private func peopleSection(_ view: HomeScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(
                title: Copy.from_people, actionLabel: view.openRooms > 0 ? Copy.home_all_count("\(view.openRooms)") : nil,
                action: view.openRooms > 0 ? showPeople : nil
            ).padding(.horizontal, Space.page)
            if !view.people.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Space.md) {
                        ForEach(view.people, id: \.event.id) { entry in
                            PosterCard(
                                entry: entry, saved: view.isSaved(entry.event), waitlisted: view.isWaitlisted(entry.event),
                                showsOrigin: false, onSave: { model.app.toggleSaved(id: entry.event.id) }
                            ) { open(entry.event.id, from: "home_people") }
                            .frame(width: peopleCardWidth).frame(maxHeight: .infinity)
                        }
                    }
                    // Квитки рейки за найвищим: корінці на одній лінії.
                    .fixedSize(horizontal: false, vertical: true)
                }
                .railContentPadding(spread: 0)
                .zIndex(1)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                CreateEventCard(
                    title: Copy.home_create_title, subtitle: Copy.home_create_subtitle,
                    action: { createEvent("home_top") }
                )
                if !view.signedIn { guestLoginRow }
            }.padding(.horizontal, Space.page)
        }
    }

    /// «Ваше»: найближчий план карткою з діями, решта планів і підписки — рядками під нею. Гостю блоку нема, як і людині без
    /// планів і підписок: створити подію їй пропонує плашка вгорі, а порожній рядок «Планів нема» лише дублював би її.
    @ViewBuilder private func personalSection(_ view: HomeScreenState) -> some View {
        if !view.personal.isEmpty || !view.followed.isEmpty { personalBlock(view) }
    }

    private func personalBlock(_ view: HomeScreenState) -> some View {
        // Велика картка — першому плану, що скоро чи чекає на людину; минула чи далека подія лишається рядком.
        let now = nowInstant()
        let zone = TimeZone.current.identifier
        let leadIndex = view.personal.firstIndex {
            HomeRules.shared.isLead(event: $0.event, waiting: $0.chat != nil || $0.requests > 0, now: now, zoneId: zone)
        }
        let lead = leadIndex.map { view.personal[$0] }
        let rows = view.personal.enumerated().filter { $0.offset != leadIndex }.map(\.element)
        var items: [AnyView] = []
        items += rows.map { row in AnyView(PlanRow(row: row, open: { open(row.event.id, from: "home_your") }, chat: { openChat(row.event) })) }
        if view.moreWaiting > 0 { items.append(AnyView(waitingRow(Int(view.moreWaiting)))) }
        if !view.followed.isEmpty { items.append(AnyView(followsRow(view))) }
        let grouped = items
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(
                title: Copy.home_yours, actionLabel: view.personal.isEmpty ? nil : Copy.my_events,
                action: view.personal.isEmpty ? nil : openMyEvents
            )
            if let lead {
                NextPlanCard(row: lead, open: { open(lead.event.id, from: "home_your") }, chat: { openChat(lead.event) })
            }
            if !grouped.isEmpty {
                GroupedRows {
                    ForEach(grouped.indices, id: \.self) { position in
                        if position > 0 { yourDivider }
                        grouped[position]
                    }
                }
            }
        }.padding(.horizontal, Space.page)
    }

    private var yourDivider: some View {
        Divider().overlay(Palette.hairline).padding(.leading, Space.lg + yourTile + Space.md)
    }

    /// «Ви стежите» і за ким — двома першими іменами, як і веде тап: на екран «Ви стежите». Імен нема (список не доїхав) — назва події.
    private func followsRow(_ view: HomeScreenState) -> some View {
        let names = view.followNames
        let shown = names.isEmpty ? (view.followed.first?.displayTitle ?? "") : names.prefix(2).joined(separator: ", ")
        return YourRow(
            overline: nil, title: Copy.follows_title,
            subtitle: names.count > 2 ? Copy.home_follows_more(shown, "\(names.count - 2)") : shown, open: openFollows
        ) {
            PoruchIcon(glyph: PoruchIcons.bell, size: 20).foregroundStyle(Palette.ink)
                .frame(width: yourTile, height: yourTile)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            // Нове ще не переглянуте — бейдж замість шеврона: рядок тепер про те, що чекає.
            if view.newFollowEvents > 0 {
                StatusBadge(text: Copy.follows_new(Int(view.newFollowEvents)), tone: .accent)
            } else {
                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    /// Ті, що чекають відповіді, але в «Ваше» не влізли: їх видно лише в «Моїх подіях».
    private func waitingRow(_ count: Int) -> some View {
        YourRow(
            overline: nil, title: Copy.home_waiting_more("\(count)"), subtitle: Copy.home_waiting_more_hint, open: openMyEvents
        ) {
            PoruchIcon(glyph: PoruchIcons.chat, size: 20).foregroundStyle(Palette.ink)
                .frame(width: yourTile, height: yourTile)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
        }
    }

    /// «У місті»: три великі картки, що гортаються (сусідня визирає), чипи, далі сітка постерів у дві колонки.
    @ViewBuilder private func cityFeed(_ view: HomeScreenState) -> some View {
        if !view.feed.isEmpty {
            let picks = Array(view.feed.prefix(homeHeroCount))
            // Сітку вже звузив презентер обраним чипом (`view.feedFilter`).
            let shown = Array(view.feed.dropFirst(homeHeroCount))
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(
                    title: Copy.home_in_city, actionLabel: view.totalFound > 0 ? Copy.home_all_count("\(view.totalFound)") : nil,
                    action: view.totalFound > 0 ? showCity : nil
                ).padding(.horizontal, Space.page)
                heroPager(picks, view)
                if !view.chips.isEmpty { feedChips(view.chips, selected: view.feedFilter) }
                if !shown.isEmpty {
                    // Ряди по два квитки однакової висоти: корінці в ряду стоять на одній лінії, хоч би скільки рядків мав підпис.
                    let visible = Array(shown.prefix(feedLimit))
                    LazyVStack(spacing: Space.xl) {
                        ForEach(Array(stride(from: 0, to: visible.count, by: 2)), id: \.self) { index in
                            HStack(alignment: .top, spacing: Space.md) {
                                cityPoster(visible[index], view)
                                if index + 1 < visible.count { cityPoster(visible[index + 1], view) } else { Color.clear }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, Space.page).padding(.top, Space.md)
                    if shown.count > feedLimit {
                        SecondaryButton(title: Copy.show_more) { feedLimit += Int(HomeRules.shared.FEED_PAGE) }
                            .padding(.horizontal, Space.page)
                    }
                }
            }
        } else if view.isEmpty {
            if view.loading {
                PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
            } else {
                EmptyState(
                    glyph: PoruchIcons.compass, title: Copy.nothing_here,
                    message: Copy.nothing_here_hint,
                    actionLabel: Copy.find_on_map, action: openMap
                )
            }
        }
    }

    private func cityPoster(_ entry: FeedEntry, _ view: HomeScreenState) -> some View {
        PosterCard(
            entry: entry, saved: view.isSaved(entry.event), waitlisted: view.isWaitlisted(entry.event),
            onSave: { model.app.toggleSaved(id: entry.event.id) }
        ) {
            open(entry.event.id, from: "home_poster")
        }
        .frame(maxHeight: .infinity)
    }

    /// Ряд чипів над сіткою: час, безкоштовне й найбільші категорії. Звужує лише сітку, великі картки стоять.
    private func feedChips(_ chips: [FeedFilter], selected: FeedFilter) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(chips, id: \.self) { chip in
                    Chip(label: feedChipLabel(chip), dot: chip.category, selected: chip == selected) {
                        withMotion { model.homeScreen.selectFeedFilter(chip) }
                        feedLimit = Int(HomeRules.shared.FEED_PAGE)
                    }
                }
            }
        }.railContentPadding(spread: 0)
    }

    /// Гортана стрічка великих карток: наступна визирає з-за краю, як у Moonly.
    private func heroPager(_ picks: [FeedEntry], _ view: HomeScreenState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.md) {
                ForEach(picks, id: \.event.id) { entry in
                    EventHeroCard(
                        event: entry.event, eyebrow: lane(entry),
                        saved: view.isSaved(entry.event), onSave: { model.app.toggleSaved(id: entry.event.id) }
                    ) { open(entry.event.id, from: "home_hero") }
                    .containerRelativeFrame(.horizontal) { width, _ in picks.count > 1 ? width * 0.86 : width - 2 * Space.page }
                    .frame(maxHeight: .infinity)
                }
            }
            // Великі квитки за найвищим: з великим текстом корінці стоять на одній лінії.
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .railContentPadding(spread: 0)
        .zIndex(1)
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

    private func open(_ id: String, from: String) { model.app.selectEvent(id: id, from: from); openEvent(id) }

    /// «Усі N» біля «У місті» і рядок «Усі події поруч»: мапа з усім містом, а не з фільтрами, що лишились з минулого візиту.
    private func showCity() { model.app.showEverythingOnMap(); openMap() }

    /// «Усі N» біля «Від людей»: мапа лише зі зустрічами від людей з вільним місцем.
    private func showPeople() { model.app.showPeopleOnMap(); openMap() }

    /// Результати пошуку одним списком.
    @ViewBuilder private func searchResults(_ view: HomeScreenState) -> some View {
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
        if view.searchLoading && view.results.isEmpty && view.places.isEmpty && view.artists.isEmpty {
            PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
        } else if view.results.isEmpty && view.places.isEmpty && view.artists.isEmpty {
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
                                    open(event.id, from: "home_search")
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

/// Обкладинка-плитка блоку «Ваше».
private let yourTile: CGFloat = 52

/// Рядок блоку «Ваше»: плитка, надрядок, назва, підпис. `trailing` лежить у тапі рядка, а лічильник чату — окремою кнопкою.
private struct YourRow<Tile: View, Trailing: View>: View {
    let overline: String?
    let title: String
    let subtitle: String?
    let open: () -> Void
    /// Непрочитане: кнопка праворуч, що веде просто в чат. Тоді `trailing` не малюється.
    var chat: (count: Int, open: () -> Void)?
    /// Назва події (а не службового рядка) — засічками, як у постері.
    var brandTitle = false
    @ViewBuilder let tile: Tile
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: open) {
                HStack(spacing: Space.md) {
                    tile
                    VStack(alignment: .leading, spacing: 2) {
                        if let overline {
                            Text(overline).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary).lineLimit(1)
                        }
                        Text(title).font(brandTitle ? PoruchFont.brandTitle3 : PoruchFont.cardName).kerning(brandTitle ? -0.1 : -0.2)
                            .foregroundStyle(Palette.ink).multilineTextAlignment(.leading).lineLimit(2)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if chat == nil { trailing }
                }.contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 1))
            .accessibilityElement(children: .combine)
            if let chat {
                Button(action: chat.open) {
                    CountBadge(count: chat.count).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Copy.home_chat_a11y("\(chat.count)"))
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
    }
}

/// Кнопка-пігулка картки плану. Підсвічена (чорнилом), коли за нею є що робити: нове в чаті, запити.
private struct PlanButton: View {
    let title: String
    let glyph: PoruchGlyph
    var highlight = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                PoruchIcon(glyph: glyph, size: 17)
                Text(title).font(PoruchFont.label).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(highlight ? Palette.onBrand : Palette.ink)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(highlight ? Palette.brand : Palette.brandContainer, in: buttonShape)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Найближчий план великою карткою, як посадковий талон: відлік, назва, місце й дії — маршрут, чат, запити.
private struct NextPlanCard: View {
    let row: PersonalRow
    let open: () -> Void
    let chat: () -> Void

    private var event: Event { row.event }

    private var today: Bool { parseEventDate(event.startsAt).map(Calendar.current.isDateInToday) == true }

    /// Відлік лише для сьогоднішнього: «через 25 год» про завтрашнє нічого не каже.
    private var overline: String { today ? countdownOverline(event) : cardOverline(event) }

    /// Остання репліка чату, коли є нове; інакше моя роль і місце.
    private var chatPreview: String? {
        guard let unread = row.chat, !unread.lastBody.isEmpty else { return nil }
        let author = unread.lastAuthorName.isEmpty ? Copy.chat_member : unread.lastAuthorName
        return "\(author): «\(unread.lastBody.replacingOccurrences(of: "\n", with: " "))»"
    }

    private var subtitle: String {
        chatPreview ?? [row.organizing ? Copy.home_role_organizer : Copy.going, event.placeLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Button(action: open) {
                HStack(alignment: .top, spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(overline).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.accentText).lineLimit(1)
                        Text(event.displayTitle).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(3)
                        // Місце в один рядок: повна адреса живе в «Маршруті», а не в підписі.
                        Text(subtitle).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.leading).lineLimit(chatPreview == nil ? 1 : 2)
                    }
                    Spacer(minLength: 0)
                    EventThumbnail(event: event, glyphSize: 30, maxDimension: 88)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
                }.contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 1))
            .accessibilityElement(children: .combine)
            HStack(spacing: Space.sm) {
                // Маршрут — головна дія, поки подія сьогодні й ще не почалась; далі — звичайна.
                PlanButton(
                    title: Copy.rate_tag_route, glyph: PoruchIcons.myLocation,
                    highlight: today && !event.hasStarted(now: nowInstant())
                ) { SystemActions.openInMaps(event) }
                PlanButton(
                    title: row.chat.map { Copy.chat_short_unread("\($0.unread)") } ?? Copy.chat_short, glyph: PoruchIcons.chat,
                    highlight: row.chat != nil, action: chat
                )
                if row.requests > 0 {
                    PlanButton(title: Copy.home_requests_short("\(row.requests)"), glyph: PoruchIcons.personAdd, highlight: true, action: open)
                }
            }
        }
        .padding(Space.lg)
        .cardSurface(radius: Corner.xl)
    }
}

/// Своя подія: категорія плиткою, час, назва. Праворуч — про що просять: нове в чаті, запити, або просто «Ви йдете».
private struct PlanRow: View {
    let row: PersonalRow
    let open: () -> Void
    let chat: () -> Void

    private var event: Event { row.event }

    /// Моя роль у події; після кінця вона нічого не каже.
    private var role: (String, BadgeTone)? {
        if event.isCancelled { return (Copy.cancelled_short, .danger) }
        if event.hasEnded(now: nowInstant()) { return nil }
        return row.organizing ? (Copy.home_role_organizer, .brand) : (Copy.going, .success)
    }

    /// Праворуч зайнято лічильником чи запитами — роль переїжджає до дати.
    private var overline: String {
        guard row.chat != nil || row.requests > 0, let role else { return cardOverline(event) }
        return cardOverline(event) + " · " + role.0.uppercased(with: Locale(identifier: "uk_UA"))
    }

    private var subtitle: String? {
        guard let chat = row.chat else { return event.placeLabel }
        let author = chat.lastAuthorName.isEmpty ? Copy.chat_member : chat.lastAuthorName
        let body = chat.lastBody.replacingOccurrences(of: "\n", with: " ")
        return body.isEmpty ? Copy.new_messages_count("\(chat.unread)") : "\(author): «\(body)»"
    }

    /// Лічильник — кнопка в чат, поки праворуч не зайняли запити: на них теж чекає людина, і вони важливіші.
    private var chatButton: (count: Int, open: () -> Void)? {
        guard let unread = row.chat, row.requests == 0 else { return nil }
        return (Int(unread.unread), chat)
    }

    var body: some View {
        YourRow(overline: overline, title: event.displayTitle, subtitle: subtitle, open: open, chat: chatButton, brandTitle: true) {
            EventThumbnail(event: event, glyphSize: 24, maxDimension: 52)
                .frame(width: yourTile, height: yourTile)
                .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            if event.isCancelled {
                TicketStamp(text: Copy.cancelled_short, tone: .danger)
            } else if row.requests > 0 {
                StatusBadge(
                    text: Copy.requests_count(Int(row.requests)),
                    tone: .accent, glyph: PoruchIcons.personAdd
                )
            } else if let role {
                StatusBadge(text: role.0, tone: role.1)
            }
        }
    }
}

/// Без фільтра: усе, що є в сітці.

private func feedChipLabel(_ chip: FeedFilter) -> String {
    switch chip.kind {
    case .today: Copy.today
    case .tomorrow: Copy.tomorrow
    case .weekend: Copy.weekend
    case .free: Copy.listing_free
    case .category: chip.category.map(categoryName) ?? Copy.feed_all
    default: Copy.feed_all
    }
}

/// Підпис джерела в стрічці: «Для вас», «Ви стежите · МУР». Афіша міста без підпису.
private func lane(_ entry: FeedEntry) -> String? {
    switch entry.source {
    case .forYou: Copy.picked_for_you
    case .following: entry.followName.map { Copy.follow_via($0) } ?? Copy.following
    default: nil
    }
}

/// Ширина постера в рейці «Від людей»: як в одній колонці сітки, щоб третій визирав із-за краю.
private let peopleCardWidth: CGFloat = 176

/// Вертикальний квиток у сітці «У місті» й рейці «Від людей»: обкладинка 4:5 і назва вгорі, а за перфорацією корінець
/// кольору жанру з годиною, днем і, для зустрічі, місцями «3/8». Ціна — плашкою на фото, стан кімнати («Ви йдете»,
/// «Лишилось 2») — штампом нагорі замість підпису «Для вас».
private struct PosterCard: View {
    let entry: FeedEntry
    let saved: Bool
    let waitlisted: Bool
    /// Підпис «Від людей» на кімнаті без стану: у секції «Від людей» він зайвий.
    var showsOrigin = true
    let onSave: () -> Void
    let open: () -> Void

    private var event: Event { entry.event }

    /// «Від 390 ₴» лише коли джерело сказало ціну. Місця зустрічі — на корінці.
    private var price: String? {
        guard event.gathering == nil, let listing = event.listing,
              listing.isFree?.boolValue == true || listing.priceMin != nil else { return nil }
        return listingPrice(listing)
    }

    /// Стан: скасоване — штампом (корінець тоді погашений), для кімнати — «Ви йдете», «Лишилось 2». Знята афіша сказана підписом.
    private var state: (String, BadgeTone, PoruchGlyph?)? {
        if event.isCancelled { return (Copy.cancelled_short, .danger, nil) }
        return event.gathering == nil ? nil : eventState(event, waitlisted: waitlisted)
    }

    /// Афіша завжди підписана джерелом (docs/event-ingestion.md §8).
    private var note: (String, Color)? {
        guard let listing = event.listing else { return nil }
        return (listing.isWithdrawn ? Copy.listing_withdrawn : Copy.listing_badge("\(listing.sourceName)"), Palette.inkTertiary)
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Друкована сторона без фото дає назві чотири рядки; з великим текстом — на рядок більше, щоб назва не тонула в «…».
    private var titleLines: Int { (event.imageUrl == nil ? 4 : 2) + (typeSize.isAccessibilitySize ? 1 : 0) }

    /// Штамп — лише стан квитка: скасовано, «Ви йдете», «Лишилось 2». Чому квиток тут — [reason], тихим рядком.
    @ViewBuilder private func stampView(onFill: Bool) -> some View {
        if let state { TicketStamp(text: state.0, tone: state.1, glyph: state.2, onFill: onFill) }
    }

    /// Чому квиток у стрічці: за ким стежите (дзвіночок і ім'я), «Для вас», «Від людей». Не штамп, бо нічого з
    /// квитком не сталось — штамп поруч зі «Скасовано» й «Лишилось 2» мав би однакову вагу.
    private var reason: (String, PoruchGlyph)? {
        if entry.source == .following { return (entry.followName ?? Copy.following, PoruchIcons.bell) }
        if let label = lane(entry) { return (label, PoruchIcons.sparkle) }
        if showsOrigin, event.gathering != nil { return (Copy.from_people, PoruchIcons.social) }
        return nil
    }

    var body: some View {
        Button(action: open) {
            // 64: жанр над часом — два рядки, і в 52 вони впирались у перфорацію та нижній край.
            Ticket(vertical: true, stubColor: ticketStub(event), stubLength: 64) {
                VStack(alignment: .leading, spacing: 0) {
                    if event.imageUrl != nil {
                        // Пріоритет: у ряду однакової висоти фото бере свої 4:5 першим, а запас іде полю під назвою.
                        Color.clear.aspectRatio(4.0 / 5.0, contentMode: .fit)
                            .overlay { EventArt(event: event, maxDimension: 420) }
                            .clipped()
                            .layoutPriority(1)
                            .overlay(alignment: .topLeading) {
                                // Поле праворуч — під «Зберегти»: довгий штамп стискається, а не лягає на кнопку.
                                stampView(onFill: true).padding(Space.sm).padding(.trailing, 40)
                            }
                            .overlay(alignment: .topTrailing) { SaveButton(saved: saved, action: onSave).padding(Space.xs) }
                            .overlay(alignment: .bottomLeading) {
                                if let price { StatusBadge(text: price, onPhoto: true).padding(Space.sm) }
                            }
                    } else {
                        // Без фото — друкована сторона квитка: штамп і «Зберегти» вгорі, назва великим кеглем.
                        HStack(alignment: .top) {
                            stampView(onFill: false).padding(.top, Space.xs)
                            Spacer(minLength: Space.xs)
                            SaveButton(saved: saved, action: onSave)
                        }
                        .padding([.top, .horizontal], Space.sm)
                    }
                    // Як на друкованому квитку: місце й підписи притиснуті до перфорації, вільне поле лишається під назвою.
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(event.displayTitle)
                            .font(event.imageUrl == nil ? PoruchFont.brandTitle2 : PoruchFont.brandTitle3).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(titleLines)
                        HostLine(event: event)
                        Spacer(minLength: Space.sm)
                        if let reason { ReasonLine(text: reason.0, glyph: reason.1) }
                        EventDescriptor(event: event, placeFirst: true)
                        if event.imageUrl == nil, let price {
                            Text(price).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                        }
                        if let series = seriesNote(event) {
                            Text(series).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                        }
                        if let note { Text(note.0).font(PoruchFont.overline).foregroundStyle(note.1).lineLimit(1) }
                    }
                    .padding(.horizontal, Space.md).padding(.top, Space.md).padding(.bottom, Space.lg)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            } stub: {
                StubTime(event: event, row: true)
            }
        }
        .buttonStyle(PressableStyle())
        .ticketAccessibility(event, state: [state?.0, reason?.0, price, note?.0].compactMap { $0 }.joined(separator: ", "), saved: saved, onSave: onSave)
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
