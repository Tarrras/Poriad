import SwiftUI
import Shared

/// Головна з двох зон: «Ваше» (плани, чати, підписки) і «У місті» (одна стрічка з даних, які вже завантажила мапа).
struct HomeView: View {
    @EnvironmentObject var model: AppModel
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

    private var view: HomePresentation { model.home }
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
    /// Обраний чип над сіткою; якщо його вже нема в ряду (дані оновились), стрічка лишається цілою.
    @State private var feedFilter = allFeed
    /// Шторка вибору міста з шапки: та сама, що на мапі.
    @State private var citySearch = false

    var body: some View {
        let view = self.view
        // У пошуку поле з фільтрами закріплене над стрічкою, а не в ній: `refreshable` стрічки діставався б
        // горизонтальним рядам чипів, і ті отримували власний індикатор оновлення та гойдалися вертикально.
        VStack(spacing: 0) {
            if searchActive(view) { headerView(view) }
            feed(view).refreshable { await model.reloadAll() }
        }
        // Першим сяйво, потім полотно: пізніший `background` лягає позаду.
        .background(alignment: .top) {
            if !searchActive(view) {
                LinearGradient(colors: [Palette.glow, Palette.canvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: 460).ignoresSafeArea()
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $citySearch) { CitySearchView().presentationDetents([.medium, .large]) }
        .onChange(of: view.searchKey) { _, _ in resultsLimit = homeResultsLimit }
    }

    /// Текст, що лишився зі спільного стану, теж тримає режим: інакше фільтри діяли б невидимо.
    private func searchActive(_ view: HomePresentation) -> Bool { searchMode || view.searching }

    /// Тап по іконці пошуку: поле з'являється закріпленим зверху, курсор одразу в ньому.
    private func startSearch() {
        withAnimation(.snappy) { searchMode = true }
        searchFocused = true
    }

    /// «Скасувати»: текст і фільтри скидаються, фокус знімається, повертається стрічка.
    private func cancelSearch() {
        searchFocused = false
        searchEpoch += 1
        model.app.cancelHomeSearch()
        withAnimation(.snappy) { searchMode = false }
    }

    private func feed(_ view: HomePresentation) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Поза пошуком шапка — перший рядок стрічки і прокручується разом з нею.
                if !searchActive(view) { headerView(view) }
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if view.searching {
                        searchResults(view)
                    } else if searchActive(view) {
                        EmptyState(
                            symbol: "magnifyingglass", title: "Шукайте за назвою, місцем чи виконавцем",
                            message: "Шукаємо \(view.searchScope)"
                        ).padding(.horizontal, Space.page).padding(.top, Space.section)
                    } else {
                        // Головна одиниця застосунку — зустріч від людини: заклик створити її стоїть першим, як колись «Організувати».
                        // Гостю під плашкою лише тихий рядок входу (без картки): дві картки поспіль товпились би.
                        VStack(alignment: .leading, spacing: Space.xs) {
                            CreateEventCard(
                                title: "Організувати подію", subtitle: "Зберіть людей на настолки, пробіжку чи кіно",
                                action: { createEvent("home_top") }
                            )
                            if !view.signedIn { guestLoginRow }
                        }.padding(.horizontal, Space.page)
                        if view.signedIn { personalSection(view) }
                        peopleSection(view)
                        cityFeed(view)
                        // Кінець стрічки не глухий кут: далі мапа чи власна подія.
                        if !view.feed.isEmpty { moreRows(view) }
                    }
                }.padding(.top, Space.md).padding(.bottom, Space.section)
            }
        }
    }

    private func headerView(_ view: HomePresentation) -> some View {
        let searchActive = searchActive(view)
        return VStack(alignment: .leading, spacing: Space.lg) {
            // Під час пошуку великий заголовок ховається: місце — фільтрам і результатам.
            if !searchActive {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Що поруч").font(PoruchFont.serifDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                        // Тап міняє місто тут же, без переходу на мапу. Шеврон — частина тексту: довга назва
                        // переноситься разом із ним. Колір темніший за `inkSecondary`: на сяйві той дає лише ≈4:1.
                        Button { citySearch = true } label: {
                            Text("\(view.cityName) \(Image(systemName: "chevron.down"))")
                                .font(PoruchFont.subhead).foregroundStyle(Palette.ink.opacity(0.7)).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Місто \(view.cityName)")
                        .accessibilityHint("Змінити місто")
                    }
                    Spacer(minLength: Space.sm)
                    HStack(spacing: Space.sm) {
                        IconPill(symbol: "magnifyingglass", label: "Пошук \(view.searchScope)", action: startSearch)
                        IconPill(symbol: "person.crop.circle", label: "Профіль", action: openProfile)
                    }
                }
                .padding(.horizontal, Space.page)
            } else {
                HStack(spacing: Space.md) {
                    SearchBar(placeholder: "Пошук \(view.searchScope)", initial: view.searchText) {
                        model.app.setHomeSearchText(query: $0)
                    }
                    .id(searchEpoch)
                    .focused($searchFocused)
                    Button("Скасувати", action: cancelSearch)
                        .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .padding(.horizontal, Space.page)
                searchFilters(view)
            }
        }
        .padding(.top, searchActive ? Space.md : Space.xl).padding(.bottom, Space.md)
        .animation(.snappy, value: searchActive)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Де й що шукати: місто чи всюди, дата, категорія. Ті самі чипи й підписи, що на мапі.
    private func searchFilters(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    Chip(label: view.cityName, symbol: "mappin.and.ellipse", selected: !view.searchEverywhere) {
                        model.app.setHomeSearchEverywhere(everywhere: false)
                    }
                    Chip(label: "Усюди", symbol: "globe", selected: view.searchEverywhere) {
                        model.app.setHomeSearchEverywhere(everywhere: true)
                    }
                    Divider().frame(height: 24).overlay(Palette.hairline)
                    ForEach(dateFilterKeys, id: \.self) { key in
                        // Повторний тап знімає вибір, як на мапі.
                        Chip(label: dateLabel(key), selected: view.searchDate == key) {
                            model.app.setHomeSearchDate(filter: view.searchDate == key ? DateFilter.any : key)
                        }
                    }
                }
            }.railContentPadding(spread: 0)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    Chip(label: "Усі категорії", selected: view.searchCategory == nil) {
                        model.app.setHomeSearchCategory(category: nil)
                    }
                    ForEach(categories, id: \.0) { entry in
                        Chip(label: entry.1, dot: entry.0, selected: view.searchCategory == entry.0) {
                            model.app.setHomeSearchCategory(category: view.searchCategory == entry.0 ? nil : entry.0)
                        }
                    }
                }
            }.railContentPadding(spread: 0)
        }
    }

    /// Рядок входу для гостя: плашка вгорі — єдина головна дія, а вхід — для тих, хто вже має профіль, тож без картки й заливки.
    private var guestLoginRow: some View {
        Button(action: openProfile) {
            HStack(spacing: Space.sm) {
                Image(systemName: "lock").font(.system(size: 13, weight: .semibold))
                Text("Увійти й зберігати події").font(PoruchFont.label)
                Spacer(minLength: Space.sm)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, Space.xs).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityLabel("Увійти й зберігати події")
    }

    /// «Від людей»: зустрічі з вільним місцем окремою рейкою, коли їх набралось досить (`HomeRules.people`). Ті самі постери,
    /// що в сітці міста, але без підпису походження: заголовок секції вже каже, що це люди.
    @ViewBuilder private func peopleSection(_ view: HomePresentation) -> some View {
        if !view.people.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(
                    title: "Від людей", actionLabel: view.openRooms > 0 ? "Усі \(view.openRooms)" : nil,
                    action: view.openRooms > 0 ? showPeople : nil
                ).padding(.horizontal, Space.page)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Space.md) {
                        ForEach(view.people, id: \.event.id) { entry in
                            PosterCard(
                                entry: entry, saved: view.isSaved(entry.event), waitlisted: view.isWaitlisted(entry.event),
                                showsOrigin: false, onSave: { model.app.toggleSaved(id: entry.event.id) }
                            ) { open(entry.event.id, from: "home_people") }
                            .frame(width: peopleCardWidth)
                        }
                    }
                }
                .railContentPadding(spread: 0)
                .zIndex(1)
            }
        }
    }

    /// «Ваше»: найближчий план карткою з діями, решта планів і підписки — рядками під нею. Гостю блоку нема, як і людині без
    /// планів і підписок: створити подію їй пропонує плашка вгорі, а порожній рядок «Планів нема» лише дублював би її.
    @ViewBuilder private func personalSection(_ view: HomePresentation) -> some View {
        if !view.personal.isEmpty || !view.followed.isEmpty { personalBlock(view) }
    }

    private func personalBlock(_ view: HomePresentation) -> some View {
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
        if view.moreWaiting > 0 { items.append(AnyView(waitingRow(view.moreWaiting))) }
        if !view.followed.isEmpty { items.append(AnyView(followsRow(view.followed))) }
        let grouped = items
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(
                title: "Ваше", actionLabel: view.personal.isEmpty ? nil : "Мої події",
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

    /// «Підписки: 3 події» і, що саме, — першою назвою. Тап веде на екран підписок.
    private func followsRow(_ events: [Event]) -> some View {
        let count = events.count
        let more = count - 1
        return YourRow(
            overline: nil, title: "Підписки: \(count) \(ukrainianPlural(count, "подія", "події", "подій"))",
            subtitle: (events.first?.displayTitle ?? "") + (more > 0 ? " та ще \(more)" : ""), open: openFollows
        ) {
            Image(systemName: "bell").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink)
                .frame(width: yourTile, height: yourTile)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
        }
    }

    /// Ті, що чекають відповіді, але в «Ваше» не влізли: їх видно лише в «Моїх подіях».
    private func waitingRow(_ count: Int) -> some View {
        YourRow(
            overline: nil, title: "Чекають відповіді: ще \(count)", subtitle: "Чати й запити — у «Моїх подіях»", open: openMyEvents
        ) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink)
                .frame(width: yourTile, height: yourTile)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
        }
    }

    /// «У місті»: три великі картки, що гортаються (сусідня визирає), чипи, далі сітка постерів у дві колонки.
    @ViewBuilder private func cityFeed(_ view: HomePresentation) -> some View {
        if !view.feed.isEmpty {
            let picks = Array(view.feed.prefix(homeHeroCount))
            let rest = Array(view.feed.dropFirst(homeHeroCount))
            let filter = view.chips.contains(feedFilter) ? feedFilter : allFeed
            let shown = filter.kind == .all
                ? rest : HomeRules.shared.apply(entries: rest, filter: filter, now: nowInstant(), zoneId: TimeZone.current.identifier)
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(
                    title: "У місті", actionLabel: view.totalFound > 0 ? "Усі \(view.totalFound)" : nil,
                    action: view.totalFound > 0 ? showCity : nil
                ).padding(.horizontal, Space.page)
                heroPager(picks, view)
                if !view.chips.isEmpty { feedChips(view.chips, selected: filter) }
                if !shown.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: Space.md, alignment: .top), GridItem(.flexible(), alignment: .top)],
                        spacing: Space.xl
                    ) {
                        ForEach(shown.prefix(feedLimit), id: \.event.id) { entry in
                            PosterCard(
                                entry: entry, saved: view.isSaved(entry.event), waitlisted: view.isWaitlisted(entry.event),
                                onSave: { model.app.toggleSaved(id: entry.event.id) }
                            ) {
                                open(entry.event.id, from: "home_poster")
                            }
                        }
                    }
                    .padding(.horizontal, Space.page).padding(.top, Space.md)
                    if shown.count > feedLimit {
                        SecondaryButton(title: "Показати ще") { feedLimit += Int(HomeRules.shared.FEED_PAGE) }
                            .padding(.horizontal, Space.page)
                    }
                }
            }
        } else if view.isEmpty {
            if view.loading {
                PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
            } else {
                EmptyState(
                    symbol: "safari", title: "Тут поки тихо",
                    message: "Змініть область мапи, дату або категорію — і події знайдуться.",
                    actionLabel: "Знайти на мапі", action: openMap
                )
            }
        }
    }

    /// Ряд чипів над сіткою: час, безкоштовне й найбільші категорії. Звужує лише сітку, великі картки стоять.
    private func feedChips(_ chips: [FeedFilter], selected: FeedFilter) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(chips, id: \.self) { chip in
                    Chip(label: feedChipLabel(chip), dot: chip.category, selected: chip == selected) {
                        withAnimation(.snappy) { feedFilter = chip }
                        feedLimit = Int(HomeRules.shared.FEED_PAGE)
                    }
                }
            }
        }.railContentPadding(spread: 0)
    }

    /// Гортана стрічка великих карток: наступна визирає з-за краю, як у Moonly.
    private func heroPager(_ picks: [FeedEntry], _ view: HomePresentation) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.md) {
                ForEach(picks, id: \.event.id) { entry in
                    EventHeroCard(
                        event: entry.event, eyebrow: lane(entry.source),
                        saved: view.isSaved(entry.event), onSave: { model.app.toggleSaved(id: entry.event.id) }
                    ) { open(entry.event.id, from: "home_hero") }
                    .containerRelativeFrame(.horizontal) { width, _ in picks.count > 1 ? width * 0.86 : width - 2 * Space.page }
                }
            }.scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .railContentPadding(spread: 0)
        .zIndex(1)
    }

    /// Куди далі, коли стрічку переглянуто: мапа з усім, що є, і створення власної події.
    private func moreRows(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Далі")
            GroupedRows {
                LinkRow(
                    symbol: "map", title: "Усі події поруч",
                    subtitle: "На мапі можна змінити область, дату й категорію",
                    value: view.totalFound > 0 ? "\(view.totalFound)" : nil, action: showCity
                )
                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                LinkRow(symbol: "sparkles", title: "Маєте ідею зустрічі?", subtitle: "Опублікуйте подію за три кроки") { createEvent("home_footer") }
            }
        }.padding(.horizontal, Space.page)
    }

    private func open(_ id: String, from: String) { model.app.selectEvent(id: id, from: from); openEvent(id) }

    /// «Усі N» біля «У місті» і рядок «Усі події поруч»: мапа з усім містом, а не з фільтрами, що лишились з минулого візиту.
    private func showCity() { model.app.showEverythingOnMap(); openMap() }

    /// «Усі N» біля «Від людей»: мапа лише зі зустрічами від людей з вільним місцем.
    private func showPeople() { model.app.showPeopleOnMap(); openMap() }

    /// Результати пошуку одним списком.
    @ViewBuilder private func searchResults(_ view: HomePresentation) -> some View {
        if let city = view.cityMatch {
            BannerCard(
                title: "Показати події в місті \(city.city)",
                subtitle: "Пошук за словом іде лише в межах міста \(view.cityName).",
                symbol: "mappin.and.ellipse"
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
                    symbol: "magnifyingglass", title: "Нічого не знайшлося",
                    message: "Спробуйте інше слово або зніміть фільтри дати й категорії."
                )
            } else {
                EmptyState(
                    symbol: "magnifyingglass", title: "Нічого не знайшлося",
                    message: "У місті \(view.cityName) такого поки немає. Пошукайте в усіх містах або спробуйте інше слово.",
                    actionLabel: "Шукати усюди", action: { model.app.setHomeSearchEverywhere(everywhere: true) }
                )
            }
        } else {
            // Події, під ними — заклади з тим самим словом. Групові списки: видача пошуку — перелік, а не стрічка.
            VStack(alignment: .leading, spacing: Space.xl) {
                if !view.results.isEmpty {
                    let total = max(view.resultsTotal, view.results.count)
                    let shown = view.results(limit: resultsLimit)
                    VStack(alignment: .leading, spacing: Space.sm) {
                        // «На мапі» несе запит на мапу явно: інакше пошуки екранів незалежні. Мапа — лише обране місто,
                        // тож для пошуку всюди вона показала б менше.
                        GroupLabel(
                            title: "Події · \(total)",
                            actionLabel: view.searchEverywhere ? nil : "На мапі",
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
                            SecondaryButton(title: "Показати ще") {
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
    var serifTitle = false
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
                        Text(title).font(serifTitle ? PoruchFont.serifTitle3 : PoruchFont.cardName).kerning(serifTitle ? -0.1 : -0.2)
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
                .accessibilityLabel("Чат, нових повідомлень: \(chat.count)")
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
    }
}

/// Кнопка-пігулка картки плану. Підсвічена (чорнилом), коли за нею є що робити: нове в чаті, запити.
private struct PlanButton: View {
    let title: String
    let symbol: String
    var highlight = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(PoruchFont.label).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(highlight ? Palette.onBrand : Palette.ink)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(highlight ? Palette.brand : Palette.brandContainer, in: Capsule())
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
        let author = unread.lastAuthorName.isEmpty ? "Учасник" : unread.lastAuthorName
        return "\(author): «\(unread.lastBody.replacingOccurrences(of: "\n", with: " "))»"
    }

    private var subtitle: String {
        chatPreview ?? [row.organizing ? "Ваша подія" : "Ви йдете", event.placeLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Button(action: open) {
                HStack(alignment: .top, spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(overline).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.accentText).lineLimit(1)
                        Text(event.displayTitle).font(PoruchFont.serifTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
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
                    title: "Маршрут", symbol: "location",
                    highlight: today && !event.hasStarted(now: nowInstant())
                ) { SystemActions.openInMaps(event) }
                PlanButton(
                    title: row.chat.map { "Чат · \($0.unread)" } ?? "Чат", symbol: "bubble.left.and.bubble.right",
                    highlight: row.chat != nil, action: chat
                )
                if row.requests > 0 {
                    PlanButton(title: "Запити · \(row.requests)", symbol: "person.badge.plus", highlight: true, action: open)
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
        if event.isCancelled { return ("Скасовано", .danger) }
        if event.hasEnded(now: nowInstant()) { return nil }
        return row.organizing ? ("Ваша подія", .brand) : ("Ви йдете", .success)
    }

    /// Праворуч зайнято лічильником чи запитами — роль переїжджає до дати.
    private var overline: String {
        guard row.chat != nil || row.requests > 0, let role else { return cardOverline(event) }
        return cardOverline(event) + " · " + role.0.uppercased(with: Locale(identifier: "uk_UA"))
    }

    private var subtitle: String? {
        guard let chat = row.chat else { return event.placeLabel }
        let author = chat.lastAuthorName.isEmpty ? "Учасник" : chat.lastAuthorName
        let body = chat.lastBody.replacingOccurrences(of: "\n", with: " ")
        return body.isEmpty ? "Нових повідомлень: \(chat.unread)" : "\(author): «\(body)»"
    }

    /// Лічильник — кнопка в чат, поки праворуч не зайняли запити: на них теж чекає людина, і вони важливіші.
    private var chatButton: (count: Int, open: () -> Void)? {
        guard let unread = row.chat, row.requests == 0 else { return nil }
        return (Int(unread.unread), chat)
    }

    var body: some View {
        YourRow(overline: overline, title: event.displayTitle, subtitle: subtitle, open: open, chat: chatButton, serifTitle: true) {
            EventThumbnail(event: event, glyphSize: 24, maxDimension: 52)
                .frame(width: yourTile, height: yourTile)
                .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            if row.requests > 0 {
                StatusBadge(
                    text: "\(row.requests) \(ukrainianPlural(row.requests, "запит", "запити", "запитів"))",
                    tone: .accent, symbol: "person.badge.plus"
                )
            } else if let role {
                StatusBadge(text: role.0, tone: role.1)
            }
        }
        .opacity(event.isCancelled ? 0.6 : 1)
    }
}

/// Без фільтра: усе, що є в сітці.
private let allFeed = FeedFilter(kind: .all, category: nil)

private func feedChipLabel(_ chip: FeedFilter) -> String {
    switch chip.kind {
    case .today: "Сьогодні"
    case .tomorrow: "Завтра"
    case .weekend: "Вихідні"
    case .free: "Безкоштовно"
    case .category: chip.category.map(categoryName) ?? "Усе"
    default: "Усе"
    }
}

/// Підпис джерела в стрічці: «Для вас», «Підписки». Афіша міста без підпису.
private func lane(_ source: FeedSource) -> String? {
    switch source {
    case .forYou: "Для вас"
    case .following: "Підписки"
    default: nil
    }
}

/// Ширина постера в рейці «Від людей»: як в одній колонці сітки, щоб третій визирав із-за краю.
private let peopleCardWidth: CGFloat = 176

/// Постер у сітці «У місті»: обкладинка 4:5 без коробки, підпис просто на полотні. Ціна чи «3 з 8» — плашкою на фото,
/// стан кімнати («Ви йдете», «Лишилось 2») — плашкою нагорі замість підпису «Для вас».
private struct PosterCard: View {
    let entry: FeedEntry
    let saved: Bool
    let waitlisted: Bool
    /// Підпис «Від людей» на кімнаті без стану: у секції «Від людей» він зайвий.
    var showsOrigin = true
    let onSave: () -> Void
    let open: () -> Void

    private var event: Event { entry.event }

    /// «Від 390 ₴» лише коли джерело сказало ціну; для кімнати — «3/8» з гліфом людей. Не «3 з 8»: бейдж набраний капсом,
    /// а кирилична «З» майже не відрізняється від цифри 3 («3 З 8» читалось як «3 3 8»).
    private var chip: (text: String, symbol: String?)? {
        if let room = event.gathering { return ("\(room.attendeeCount)/\(room.capacity)", "person.2") }
        if let listing = event.listing, listing.isFree?.boolValue == true || listing.priceMin != nil { return (listingPrice(listing), nil) }
        return nil
    }

    /// Стан кімнати. Скасоване й знята афіша вже сказані підписом внизу, двічі не пишемо.
    private var state: (String, BadgeTone, String?)? {
        event.gathering == nil || event.isCancelled ? nil : eventState(event, waitlisted: waitlisted)
    }

    /// Афіша завжди підписана джерелом (docs/event-ingestion.md §8); скасоване — теж словами.
    private var note: (String, Color)? {
        if event.isCancelled { return ("Скасовано", Palette.danger) }
        guard let listing = event.listing else { return nil }
        return (listing.isWithdrawn ? "Більше не проводиться" : "Афіша · \(listing.sourceName)", Palette.inkTertiary)
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Space.md) {
                Color.clear.aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .overlay { EventArt(event: event, maxDimension: 420, glyphSize: 130) }
                    .overlay(alignment: .topLeading) {
                        if let state {
                            StatusBadge(text: state.0, tone: state.1, symbol: state.2, onPhoto: true).padding(Space.sm)
                        } else if let label = lane(entry.source) {
                            StatusBadge(text: label, onPhoto: true).padding(Space.sm)
                        } else if showsOrigin, let community = communityBadge(event) {
                            StatusBadge(text: community.0, symbol: community.2, onPhoto: true).padding(Space.sm)
                        }
                    }
                    .overlay(alignment: .topTrailing) { SaveButton(saved: saved, action: onSave).padding(Space.xs) }
                    .overlay(alignment: .bottomLeading) {
                        if let chip { StatusBadge(text: chip.text, symbol: chip.symbol, onPhoto: true).padding(Space.sm) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
                VStack(alignment: .leading, spacing: Space.xs) {
                    // Коли — найважливіше в афіші, тож і найтемніше в підписі, а не найблідіше.
                    Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.ink).lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(event.displayTitle).font(PoruchFont.serifTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2, reservesSpace: true)
                    EventDescriptor(event: event, placeFirst: true)
                    if let note { Text(note.0).font(PoruchFont.overline).foregroundStyle(note.1).lineLimit(1) }
                }.padding(.horizontal, Space.xs)
            }
            .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}
