import SwiftUI
import Shared

/// Головна: плани, сьогодні і все поруч з даних, які вже завантажила мапа.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    var openMap: () -> Void
    var openProfile: () -> Void
    var createEvent: () -> Void
    /// Відкрити деталі. Шлях стосу тримає корінь (`RootView.homePath`).
    var openEvent: (String) -> Void
    /// Прямо в чат події, минаючи деталі.
    var openChat: (Event) -> Void

    private var view: HomePresentation { model.home }
    @FocusState private var searchFocused: Bool
    /// Режим пошуку: вмикає тап у поле, вимикає лише «Скасувати». Стрічка головної і фільтри
    /// пошуку ніколи не видно разом, тож стертий текст лишає в режимі з підказкою, а не повертає стрічку.
    @State private var searchMode = false
    /// Нове поле після «Скасувати»: набране, але ще не віддане нагору, інакше повернулося б за паузу.
    @State private var searchEpoch = 0
    /// Скільки результатів пошуку показано. «Показати ще» додає шматок.
    @State private var resultsLimit = homeResultsLimit
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
        .background(Palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $citySearch) { CitySearchView().presentationDetents([.medium, .large]) }
        .onChange(of: view.searchKey) { _, _ in resultsLimit = homeResultsLimit }
        .onChange(of: searchFocused) { _, focused in
            if focused && !searchMode { withAnimation(.snappy) { searchMode = true } }
        }
    }

    /// Текст, що лишився зі спільного стану, теж тримає режим: інакше фільтри діяли б невидимо.
    private func searchActive(_ view: HomePresentation) -> Bool { searchMode || view.searching }

    /// Тап у поле стрічки: поле в ній лише показує, де шукати, а вводять уже в закріпленому зверху.
    /// Так фокус не перескакує між двома полями і клавіатура з'являється один раз.
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
                VStack(alignment: .leading, spacing: Space.section) {
                    if view.searching {
                        searchResults(view)
                    } else if searchActive(view) {
                        EmptyState(
                            symbol: "magnifyingglass", title: "Шукайте за назвою, місцем чи виконавцем",
                            message: "Шукаємо \(view.searchScope)"
                        ).padding(.horizontal, Space.page).padding(.top, Space.section)
                    } else {
                        quickActions
                        if !view.signedIn {
                            BannerCard(
                                title: "Ваші люди — поруч",
                                subtitle: "Увійдіть, щоб зберігати події та отримувати нагадування.",
                                symbol: "lock", action: openProfile
                            ).padding(.horizontal, Space.page)
                        } else {
                            // Запити вище за плани: на них чекає інша людина.
                            if !view.requests.isEmpty { requestsSection(view) }
                            if !view.unread.isEmpty { unreadSection(view) }
                            if !view.plans.isEmpty { plansRail(view) }
                        }
                        if view.isEmpty {
                            if view.loading {
                                PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
                            } else {
                                EmptyState(
                                    symbol: "safari", title: "Тут поки тихо",
                                    message: "Змініть область мапи, дату або категорію — і події знайдуться.",
                                    actionLabel: "Знайти на мапі", action: openMap
                                )
                            }
                        } else {
                            digest(view)
                        }
                        // Категорії нижче за дайджест: спершу що є, потім чим звузити. Тап відкриває мапу з фільтром.
                        categoryRail
                        moreRows(view)
                    }
                }.padding(.top, Space.md).padding(.bottom, Space.section)
                .background(Palette.canvas)
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
                        Text("Що поруч").font(PoruchFont.display).displayTracking().foregroundStyle(Palette.ink)
                        // Тап міняє місто тут же, без переходу на мапу.
                        Button { citySearch = true } label: {
                            HStack(spacing: Space.xs) {
                                Text(view.areaLabel).multilineTextAlignment(.leading)
                                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                            }
                            .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Змінити місто")
                    }
                    Spacer(minLength: Space.sm)
                    IconPill(symbol: "person.crop.circle", label: "Профіль", action: openProfile)
                }
                .padding(.horizontal, Space.page)
            }
            HStack(spacing: Space.md) {
                if searchActive {
                    SearchBar(placeholder: "Пошук \(view.searchScope)", initial: view.searchText) {
                        model.app.setHomeSearchText(query: $0)
                    }
                    .id(searchEpoch)
                    .focused($searchFocused)
                    Button("Скасувати", action: cancelSearch)
                        .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Button(action: startSearch) {
                        SearchBar(placeholder: "Пошук \(view.searchScope)", initial: "") { _ in }
                            .allowsHitTesting(false).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Пошук \(view.searchScope)")
                }
            }
            .padding(.horizontal, Space.page)
            if searchActive { searchFilters(view) }
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
                            model.app.setHomeSearchDate(filter: view.searchDate == key ? DateFilter.shared.ANY : key)
                        }
                    }
                }
            }.railContentPadding(spread: 0)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    Chip(label: "Усі категорії", selected: view.searchCategory == DiscoveryStateKt.ALL_CATEGORIES) {
                        model.app.setHomeSearchCategory(category: DiscoveryStateKt.ALL_CATEGORIES)
                    }
                    ForEach(categories, id: \.0) { entry in
                        Chip(label: entry.1, dot: entry.0, selected: view.searchCategory == entry.0) {
                            model.app.setHomeSearchCategory(category: view.searchCategory == entry.0 ? DiscoveryStateKt.ALL_CATEGORIES : entry.0)
                        }
                    }
                }
            }.railContentPadding(spread: 0)
        }
    }

    /// Плитки категорій від краю до краю, як ряд продуктів в Apple Store.
    private var categoryRail: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Категорії").padding(.horizontal, Space.page)
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                ForEach(categories, id: \.0) { entry in
                    CategoryTile(category: entry.0, selected: false) {
                        model.app.setCategory(category: entry.0)
                        openMap()
                    }
                }
            }
            }
            .railContentPadding(spread: 0)
        }.zIndex(1)
    }

    /// Дві дії на пів ширини: створити й дослідити.
    private var quickActions: some View {
        HStack(spacing: Space.md) {
            QuickActionCard(eyebrow: "Організувати", title: "Створити подію", symbol: "plus", filled: true, action: createEvent)
            QuickActionCard(eyebrow: "Дослідити", title: "На мапі", symbol: "map", action: openMap)
        }.padding(.horizontal, Space.page)
    }

    /// Дайджест: перша рекомендація — велика афіша, решта — горизонтальні стрічки.
    @ViewBuilder private func digest(_ view: HomePresentation) -> some View {
        let featured = view.suggested.first ?? view.today.first
        let suggested = view.suggested.filter { $0.id != featured?.id }
        let today = view.today.filter { $0.id != featured?.id }.prefix(homeTodayLimit)
        if let featured {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: view.suggested.isEmpty ? "Сьогодні в місті" : "Для вас")
                EventHeroCard(
                    event: featured, eyebrow: view.suggested.isEmpty ? "Сьогодні" : "Дібрано за вашими відповідями",
                    saved: view.isSaved(featured), onSave: { model.app.toggleSaved(id: featured.id) }
                ) { model.app.selectEvent(id: featured.id); openEvent(featured.id) }
            }.padding(.horizontal, Space.page)
        }
        if !suggested.isEmpty { rail("Ще для вас", Array(suggested), view) }
        if !today.isEmpty { rail("Сьогодні в місті", Array(today), view, action: openMap) }
    }

    /// Горизонтальна стрічка широких карток; сусідня визирає з-за краю.
    private func rail(_ title: String, _ items: [Event], _ view: HomePresentation, action: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: title, actionLabel: action == nil ? nil : "Усі", action: action).padding(.horizontal, Space.page)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.md) {
                    ForEach(items, id: \.id) { event in
                        EventRailCard(event: event, saved: view.isSaved(event), onSave: { model.app.toggleSaved(id: event.id) }) {
                            model.app.selectEvent(id: event.id); openEvent(event.id)
                        }
                    }
                }
            }
            .railContentPadding(spread: 0)
        }
        // Горизонтальна стрічка має ловити дотик раніше за сусідів.
        .zIndex(1)
    }

    private func plansRail(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Скоро у вас").padding(.horizontal, Space.page)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.md) {
                    ForEach(view.plans.prefix(homePlansLimit), id: \.id) { event in
                        EventTile(event: event) { model.app.selectEvent(id: event.id); openEvent(event.id) }
                            .frame(width: 220)
                    }
                }
            }
            .railContentPadding(spread: 0)
        }.zIndex(1)
    }

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
        if view.searchLoading && view.results.isEmpty {
            PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
        } else if view.results.isEmpty {
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
            let total = max(view.resultsTotal, view.results.count)
            VStack(alignment: .leading, spacing: Space.md) {
                // «На мапі» несе запит на мапу явно: інакше пошуки екранів незалежні. Мапа — лише обране місто,
                // тож для пошуку всюди вона показала б менше.
                SectionHeader(
                    title: "Знайдено \(total) \(ukrainianPlural(total, "подію", "події", "подій")) \(view.searchScope)",
                    actionLabel: view.searchEverywhere ? nil : "На мапі",
                    action: { model.app.setSearchText(query: view.searchText); openMap() }
                )
                ForEach(view.results(limit: resultsLimit), id: \.id) { event in
                    EventCard(
                        event: event, saved: view.isSaved(event), waitlisted: view.isWaitlisted(event),
                        withCity: view.searchEverywhere,
                        onSave: { model.app.toggleSaved(id: event.id) }
                    ) { model.app.selectEvent(id: event.id); openEvent(event.id) }
                }
                // Наступний шматок: картки, яких ще немає, довантажуються; решта приїде в `found`.
                if view.resultIDs.count > resultsLimit {
                    SecondaryButton(title: "Показати ще") {
                        resultsLimit += homeResultsLimit
                        model.app.loadCards(ids: Array(view.resultIDs.prefix(resultsLimit)))
                    }
                }
            }.padding(.horizontal, Space.page)
        }
    }

    /// Каталог і створення одним груповим списком: головна лише каже, куди далі.
    private func moreRows(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Далі")
            GroupedRows {
                LinkRow(
                    symbol: "map", title: "Усі події поруч",
                    subtitle: "На мапі можна змінити область, дату й категорію",
                    value: view.totalFound > 0 ? "\(view.totalFound)" : nil, action: openMap
                )
                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                LinkRow(symbol: "sparkles", title: "Маєте ідею зустрічі?", subtitle: "Опублікуйте подію за три кроки", action: createEvent)
            }
        }.padding(.horizontal, Space.page)
    }

    /// Мої події, де хтось проситься. Тап веде на подію: відповідають там, дивлячись на неї.
    private func requestsSection(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionHeader(title: "Запити на участь")
                Text("Відкрийте подію, щоб прийняти або відхилити.")
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
            }
            ForEach(view.requests) { pending in
                let label = requestsLabel(pending.count)
                Button { model.app.selectEvent(id: pending.event.id); openEvent(pending.event.id) } label: {
                    HStack(spacing: Space.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pending.event.title).font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(label).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer(minLength: Space.sm)
                        StatusBadge(text: "\(pending.count)", tone: .accent)
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(pending.event.title), \(label)")
            }
        }.padding(.horizontal, Space.page)
    }

    /// Чати з непрочитаним: назва події, хто й що написав останнім. Тап веде одразу в чат.
    private func unreadSection(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionHeader(title: "Нові повідомлення")
                Text("Відкрийте чат, щоб відповісти.").font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
            }
            ForEach(view.unread) { chat in
                let author = chat.summary.lastAuthorName.isEmpty ? "Учасник" : chat.summary.lastAuthorName
                Button { openChat(chat.event) } label: {
                    HStack(spacing: Space.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.summary.eventTitle).font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(1)
                            Text("\(author): \(chat.summary.lastBody)").font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: Space.sm)
                        StatusBadge(text: "\(chat.summary.unread)", tone: .accent)
                    }
                    .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(chat.summary.eventTitle), нових: \(chat.summary.unread). \(author): \(chat.summary.lastBody)")
            }
        }.padding(.horizontal, Space.page)
    }

    /// «1 запит», «3 запити», «5 запитів».
    private func requestsLabel(_ count: Int) -> String {
        let last = count % 10, tens = count % 100
        if last == 1 && tens != 11 { return "\(count) запит" }
        if (2...4).contains(last) && !(12...14).contains(tens) { return "\(count) запити" }
        return "\(count) запитів"
    }
}
