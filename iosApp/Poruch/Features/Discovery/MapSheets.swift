import SwiftUI
import Shared

/// Кожен вибір діє одразу, як чипи над мапою: за шторкою видно, що змінилось, а кнопка каже, скільки знайдеться.
/// Скасування не треба — вибір знімається тим самим тапом, «Скинути» прибирає все.
struct FiltersView: View {
    /// Без підписки на весь `AppModel`: шторка стежить лише за `ExploreScreenState`, як і мапа.
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    @Environment(\.dismiss) var dismiss
    private var explore: ExploreScreenState { model.exploreScreen.state }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    section(Copy.date) {
                        FlowLayout(spacing: Space.sm) {
                            ForEach(dateFilterKeys, id: \.self) { key in
                                Chip(label: dateLabel(key), selected: explore.dateFilter == key) {
                                    model.app.setDateFilter(filter: explore.dateFilter == key ? DateFilter.any : key)
                                }
                            }
                        }
                    }
                    section(Copy.categories) {
                        // Ті самі плитки, що в шторці мапи й у редакторі: жанр обирають однаково скрізь. Повторний тап знімає вибір.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Space.sm)], spacing: Space.md) {
                            ForEach(categories, id: \.0) { entry in
                                CategoryTile(category: entry.0, selected: explore.category == entry.0) {
                                    model.exploreScreen.toggleCategory(entry.0)
                                }
                            }
                        }
                    }
                    // Та сама назва, що в чипа над мапою: один фільтр — одне ім'я, а що він робить — підписом.
                    Toggle(isOn: Binding(get: { explore.onlyAvailable }, set: { model.app.setOnlyAvailable(available: $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Copy.from_people).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                            Text(Copy.from_people_hint).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        }
                    }.tint(Palette.brand)
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.lg)
            }
            actions
        }
        .background(Palette.canvas)
    }

    /// Заголовок шторки — заголовок, а не надрядок, інакше він менший за секції під ним.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Copy.filters).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.sm)
            // Лише коли є що скидати (DESIGN.md), як на Android; ціль 44, а не висота рядка тексту.
            if explore.activeFilters > 0 {
                Button(Copy.reset_filters) { reset() }
                    .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                    .tapTarget()
            }
        }
        // Висота цілі «Скинути» і без неї: інакше рядок підскакував, щойно з'являвся перший фільтр.
        .frame(minHeight: 44)
        .padding(.horizontal, Space.page)
        .padding(.top, Space.lg)
    }

    private func reset() {
        if explore.dateFilter != DateFilter.any { model.app.setDateFilter(filter: DateFilter.any) }
        if explore.category != nil { model.app.setCategory(category: nil) }
        if explore.onlyAvailable { model.app.setOnlyAvailable(available: false) }
    }

    /// Кнопка каже, що вийде: «Показати 23 події», а не «Готово» навмання. Прикріплена, не в скролі: у середньому
    /// положенні вона ховалась за згином.
    private var actions: some View {
        // Під час пошуку кнопка каже «Шукаємо…», але закриває: після кожного тапу у «Фільтрах» вона на мить глухла.
        PrimaryButton(title: resultTitle) { dismiss() }
            .frame(maxWidth: .infinity)
            .padding(Space.page)
            .background(Palette.surface.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private var resultTitle: String {
        if explore.loading { return Copy.searching }
        let count = Int(explore.listCount)
        return count == 0 ? Copy.show_nothing : Copy.show_events(count)
    }

    @ViewBuilder private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: title)
            content()
        }
    }
}

/// Чипи з переносом за шириною, як `FlowRow` на Android.
struct FlexibleChips: View {
    /// (ключ, підпис, категорія для крапки або nil).
    let items: [(String, String, EventCategory?)]
    let isSelected: (String) -> Bool
    let action: (String) -> Void
    var body: some View {
        FlowLayout(spacing: Space.sm) {
            ForEach(items, id: \.0) { item in
                Chip(label: item.1, dot: item.2, selected: isSelected(item.0)) { action(item.0) }
            }
        }
    }
}

/// Рядки зліва направо; що не влазить — з нового рядка. Вбудованого flow layout у SwiftUI нема.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            // Чип, довший за рядок («Національний академічний духовий оркестр України»), переноситься в межах
            // ширини, а не розпирає контейнер — інакше весь екран деталей ширшав за дисплей.
            if size.width > width {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                size.width = min(size.width, width)
            }
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
        }
        return frames
    }
}

struct CitySearchView: View {
    /// Без підписки на весь `AppModel`: підказки міст — з `ExploreScreenState`.
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    @Environment(\.dismiss) var dismiss
    @State private var query = ""

    /// Поки нічого не набрано, пропонуємо міста, де події справді є.
    private var covered: [HomeLocation] { HomeLocation.companion.covered }

    private func open(_ city: CityResult) {
        model.app.selectCity(city: city)
        model.app.dismissEvent()
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section(Copy.cities_with_events) {
                        ForEach(covered, id: \.city) { place in
                            Button {
                                open(CityResult(name: place.city, latitude: place.latitude, longitude: place.longitude))
                            } label: {
                                HStack(spacing: Space.md) {
                                    PoruchIcon(glyph: PoruchIcons.pin, size: 18).foregroundStyle(Palette.brand)
                                    Text(place.city).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(model.exploreScreen.state.cities, id: \.name) { city in
                        Button { open(city) } label: {
                            HStack(spacing: Space.md) {
                                PoruchIcon(glyph: PoruchIcons.pin, size: 18).foregroundStyle(Palette.brand)
                                Text(city.name).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: Text(Copy.city_search_prompt))
            // Без автофокуса: `searchFocused` з iOS 18, мінімум проєкту — 17.
            .onSettled(query, after: .milliseconds(220)) { model.app.searchCity(query: $0) }
            .navigationTitle(Copy.find_city)
            .toolbar { Button(Copy.apply) { dismiss() } }
        }
    }
}
