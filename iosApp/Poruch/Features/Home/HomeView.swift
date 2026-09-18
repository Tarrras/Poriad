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

    var body: some View {
        let view = self.view
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                headerView(view)
                if view.searching {
                    searchResults(view)
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
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.section)
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
            }.padding(.bottom, Space.section)
            .background(Palette.canvas)
        }
        .refreshable { await model.reloadAll() }
        .background(Palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func headerView(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Що поруч").font(PoruchFont.display).displayTracking().foregroundStyle(Palette.ink)
                    Text(view.areaLabel).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: Space.sm)
                IconPill(symbol: "person.crop.circle", label: "Профіль", action: openProfile)
            }
            SearchBar(placeholder: "Подія, місце або тема", initial: view.searchText) {
                model.app.setSearchText(query: $0)
            }
        }
        .padding(.horizontal, Space.page).padding(.top, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        if view.loading && view.results.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.section)
        } else if view.results.isEmpty {
            EmptyState(
                symbol: "magnifyingglass", title: "Нічого не знайшлося",
                message: "Спробуйте інше слово або пошукайте на мапі — там можна змінити область і фільтри.",
                actionLabel: "Знайти на мапі", action: openMap
            )
        } else {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Знайдено подій: \(view.results.count)")
                ForEach(view.results.prefix(homeResultsLimit), id: \.id) { event in
                    EventCard(
                        event: event, saved: view.isSaved(event), waitlisted: view.isWaitlisted(event),
                        onSave: { model.app.toggleSaved(id: event.id) }
                    ) { model.app.selectEvent(id: event.id); openEvent(event.id) }
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
