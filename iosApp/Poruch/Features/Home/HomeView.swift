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
    /// Висота смуги статусу: хедер додає відступ сам. Див. `tracksStatusBarInset`.
    @State private var statusBar: CGFloat = Space.xxl

    private var view: HomePresentation { model.home }

    var body: some View {
        // Стрічка виходить під смугу статусу, щоб градієнт хедера дійшов до краю.
        let view = self.view
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                headerView(view)
                // Поки шукають, дайджест сховано.
                if view.searching {
                    EmptyView()
                } else if !view.signedIn {
                    BannerCard(
                        title: "Ваші люди — поруч",
                        subtitle: "Увійдіть, щоб зберігати події та отримувати нагадування.",
                        symbol: "lock", action: openProfile
                    ).padding(.horizontal, Space.page)
                } else {
                    // Запити вище за плани: на них чекає інша людина.
                    if !view.requests.isEmpty { requestsSection(view) }
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionHeader(title: "Скоро у вас")
                        if view.plans.isEmpty {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("Ще немає планів").font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                                Text("Створіть подію або приєднайтесь до чужої — вона зʼявиться тут із нагадуванням.")
                                    .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                            }
                            .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Space.md) {
                                    ForEach(view.plans.prefix(homePlansLimit), id: \.id) { event in
                                        EventTile(event: event) { model.app.selectEvent(id: event.id); openEvent(event.id) }
                                            .frame(width: 220)
                                    }
                                }
                            }
                            // Поля всередині смуги, тож смуга йде від краю до краю.
                            .railContentPadding()
                            .padding(.horizontal, -Space.page)
                        }
                    }
                    // Горизонтальна стрічка над змінними секціями має ловити дотик раніше за них.
                    .padding(.horizontal, Space.page).zIndex(1)
                }

                if view.isEmpty {
                    if view.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.section)
                    } else if view.searching {
                        // Порожній пошук і порожня околиця ведуть до різних дій.
                        EmptyState(
                            symbol: "magnifyingglass", title: "Нічого не знайшлося",
                            message: "Спробуйте інше слово або пошукайте на мапі — там можна змінити область і фільтри.",
                            actionLabel: "Знайти на мапі", action: openMap
                        )
                    } else {
                        EmptyState(
                            symbol: "safari", title: "Тут поки тихо",
                            message: "Змініть область мапи, дату або категорію — і події знайдуться.",
                            actionLabel: "Знайти на мапі", action: openMap
                        )
                    }
                } else if view.searching {
                    section("Знайдено подій: \(view.results.count)", Array(view.results.prefix(homeResultsLimit)), view)
                } else {
                    if !view.suggested.isEmpty {
                        section("Для вас", view.suggested, view, subtitle: "Дібрано за вашими відповідями")
                    }
                    if !view.today.isEmpty {
                        section("Сьогодні в місті", Array(view.today.prefix(homeTodayLimit)), view)
                    }
                    // Каталог живе на мапі, головна лише каже, який він завбільшки.
                    if !view.rest.isEmpty { allEventsRow(view) }
                }

                if !view.searching {
                    BannerCard(title: "Маєте ідею зустрічі?", subtitle: "Опублікуйте подію за три кроки", action: createEvent)
                        .padding(.horizontal, Space.page)
                }
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .tracksStatusBarInset($statusBar)
    }

    private func headerView(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Що поруч").font(PoruchFont.display).displayTracking().foregroundStyle(Palette.ink)
                    Text(view.areaLabel)
                        .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: Space.sm)
                IconPill(symbol: "person.crop.circle", label: "Профіль", action: openProfile)
            }
            SearchBar(placeholder: "Подія, місце або тема", initial: view.searchText) {
                model.app.setSearchText(query: $0)
            }
            // Поки шукають, ці дії сховано.
            if !view.searching {
                HStack(spacing: Space.sm) {
                    Chip(label: "Створити подію", symbol: "plus", selected: true, action: createEvent)
                    Chip(label: "Знайти на мапі", symbol: "map", selected: false, action: openMap)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.xl)
        .padding(.top, statusBar)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroGradient)
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

    /// «1 запит», «3 запити», «5 запитів».
    private func requestsLabel(_ count: Int) -> String {
        let last = count % 10, tens = count % 100
        if last == 1 && tens != 11 { return "\(count) запит" }
        if (2...4).contains(last) && !(12...14).contains(tens) { return "\(count) запити" }
        return "\(count) запитів"
    }

    /// Кількість подій в області і перехід до каталогу.
    private func allEventsRow(_ view: HomePresentation) -> some View {
        Button(action: openMap) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Усі події поруч").font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                    Text("На мапі можна змінити область, дату й категорію")
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.sm)
                Text("\(view.totalFound)").font(PoruchFont.title2).foregroundStyle(Palette.ink)
                    .monospacedDigit()
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Усі події поруч: \(view.totalFound). Показати на мапі")
        .padding(.horizontal, Space.page)
    }

    @ViewBuilder private func section(
        _ title: String, _ items: [Event], _ view: HomePresentation, subtitle: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionHeader(title: title, actionLabel: subtitle == nil ? "Усі" : nil, action: openMap)
                // Рекомендація каже, чому вона рекомендація.
                if let subtitle {
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                }
            }
            ForEach(items, id: \.id) { event in
                EventCard(
                    event: event, saved: view.isSaved(event), waitlisted: view.isWaitlisted(event),
                    onSave: { model.app.toggleSaved(id: event.id) }
                ) { model.app.selectEvent(id: event.id); openEvent(event.id) }
            }
        }.padding(.horizontal, Space.page)
    }
}
