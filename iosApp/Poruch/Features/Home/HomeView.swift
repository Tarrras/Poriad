import SwiftUI
import Shared

/**
 Home answers «what is on this week» from data the map already loaded: the plans you joined,
 what starts today, and everything else nearby.
 */
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    var openMap: () -> Void
    var openProfile: () -> Void
    var createEvent: () -> Void
    @State private var details = false

    private var view: HomePresentation { model.home }

    /// Висота смуги статусу. Читається ззовні стрічки — усередині неї її вже не спитати.
    @State private var topInset: CGFloat = 0

    var body: some View {
        // Стрічка виходить під смугу статусу, щоб теплий градієнт хедера дійшов до краю екрана,
        // а відступ під ту саму смугу хедер додає сам. Висоту беремо виміряну, а не вгадану:
        // на різних пристроях вона різна, і константа означала б заголовок під годинником.
        GeometryReader { proxy in
        let view = self.view
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                headerView(view)
                // Поки шукають, дайджест мовчить: план на тиждень і добірка «для вас» — відповіді
                // на інше питання, ніж те, що людина щойно набрала.
                if view.searching {
                    EmptyView()
                } else if !view.signedIn {
                    BannerCard(
                        title: "Ваші люди — поруч",
                        subtitle: "Увійдіть, щоб зберігати події та отримувати нагадування.",
                        symbol: "lock", action: openProfile
                    ).padding(.horizontal, Space.page)
                } else {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionHeader(title: "Скоро у вас")
                        if view.plans.isEmpty {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("Ще немає планів").font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                                Text("Приєднайтесь до події — вона зʼявиться тут із нагадуванням.")
                                    .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                            }
                            .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Space.md) {
                                    ForEach(view.plans.prefix(homePlansLimit), id: \.id) { event in
                                        EventTile(event: event) { model.app.selectEvent(id: event.id); details = true }
                                            .frame(width: 220)
                                    }
                                }.padding(.horizontal, 2)
                            }
                        }
                    }.padding(.horizontal, Space.page)
                }

                if !view.searching { VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(title: "Категорії").padding(.horizontal, Space.page)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.xs) {
                            ForEach(categories, id: \.0) { category in
                                CategoryTile(category: category.0, selected: view.category == category.0) {
                                    model.setHomeCategory(category.0)
                                }
                            }
                        }.padding(.horizontal, Space.page)
                    }
                } }

                if view.isEmpty {
                    if view.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.section)
                    } else if view.searching {
                        // Порожній пошук — не те саме, що порожня околиця: підказка веде до іншої дії.
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
                    if !view.rest.isEmpty {
                        section("Усі події поруч", Array(view.rest.prefix(homeRestLimit)), view)
                    }
                }

                if !view.searching {
                    BannerCard(title: "Маєте ідею зустрічі?", subtitle: "Опублікуйте подію за три кроки", action: createEvent)
                        .padding(.horizontal, Space.page)
                }
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $details) { EventDetailView(app: model.app) }
        .ignoresSafeArea(edges: .top)
        .onAppear { topInset = proxy.safeAreaInsets.top }
        .onChange(of: proxy.safeAreaInsets.top) { _, value in topInset = value }
        }
    }

    private func headerView(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Що поруч").font(PoruchFont.display).displayTracking().foregroundStyle(Palette.ink)
                    Text("Плани на найближчі дні у місті \(view.cityName)")
                        .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: Space.sm)
                IconPill(symbol: "person.crop.circle", label: "Профіль", action: openProfile)
            }
            SearchBar(placeholder: "Подія, місце або тема", initial: view.searchText) {
                model.app.setSearchText(query: $0)
            }
            // Поки шукають, ці дві дії — не про це. Хрестик у полі повертає їх на місце.
            if !view.searching {
                HStack(spacing: Space.sm) {
                    Chip(label: "Створити подію", symbol: "plus", selected: true, action: createEvent)
                    Chip(label: "Знайти на мапі", symbol: "map", selected: false, action: openMap)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.xl)
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroGradient)
    }

    @ViewBuilder private func section(
        _ title: String, _ items: [Event], _ view: HomePresentation, subtitle: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionHeader(title: title, actionLabel: subtitle == nil ? "Усі" : nil, action: openMap)
                // A recommendation says why it is one; a list titled «для вас» with no reason is a
                // claim the reader has to take on trust.
                if let subtitle {
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                }
            }
            ForEach(items, id: \.id) { event in
                EventCard(
                    event: event, saved: view.isSaved(event), waitlisted: view.isWaitlisted(event),
                    onSave: { model.app.toggleSaved(id: event.id) }
                ) { model.app.selectEvent(id: event.id); details = true }
            }
        }.padding(.horizontal, Space.page)
    }
}
