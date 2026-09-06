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

    private var view: HomePresentation { HomePresentation(state: model.state) }

    var body: some View {
        let view = self.view
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                if !view.signedIn {
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

                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(title: "Категорії").padding(.horizontal, Space.page)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.xs) {
                            ForEach(categories, id: \.0) { category in
                                CategoryTile(category: category.0, selected: view.selectedCategory == category.0) {
                                    model.app.setCategory(category: category.0)
                                    openMap()
                                }
                            }
                        }.padding(.horizontal, Space.page)
                    }
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
                    if !view.today.isEmpty {
                        section("Сьогодні в місті", Array(view.today.prefix(homeTodayLimit)), view)
                    }
                    if !view.rest.isEmpty {
                        section("Усі події поруч", Array(view.rest.prefix(homeRestLimit)), view)
                    }
                }

                BannerCard(title: "Маєте ідею зустрічі?", subtitle: "Опублікуйте подію за три кроки", action: createEvent)
                    .padding(.horizontal, Space.page)
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $details) { EventDetailView(app: model.app) }
    }

    private var header: some View { headerView(HomePresentation(state: model.state)) }

    private func headerView(_ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Що поруч").font(PoruchFont.display).foregroundStyle(Palette.ink)
                    Text("Плани на найближчі дні у місті \(view.cityName)")
                        .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: Space.sm)
                IconPill(symbol: "person.crop.circle", label: "Профіль", action: openProfile)
            }
            HStack(spacing: Space.sm) {
                Chip(label: "Створити подію", symbol: "plus", selected: true, action: createEvent)
                Chip(label: "Знайти на мапі", symbol: "map", selected: false, action: openMap)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvasTint)
    }

    @ViewBuilder private func section(_ title: String, _ items: [Event], _ view: HomePresentation) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: title, actionLabel: "Усі", action: openMap)
            ForEach(items, id: \.id) { event in
                EventCard(
                    event: event, saved: view.isSaved(event), waitlisted: view.isWaitlisted(event),
                    onSave: { model.app.toggleSaved(id: event.id) }
                ) { model.app.selectEvent(id: event.id); details = true }
            }
        }.padding(.horizontal, Space.page)
    }
}
