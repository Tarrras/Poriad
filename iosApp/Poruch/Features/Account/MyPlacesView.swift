import SwiftUI
import Shared

/// Маршрут «Моїх місць» у стосі профілю.
struct PlacesRoute: Hashable {}

/// «Мої місця» (docs/my-places.md): райони й кола, де людині цікаві зустрічі від людей. Список живе на телефоні, і в
/// гостя теж; сервер дізнається про нього разом із токеном пуша.
struct MyPlacesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var addingDistrict = false
    @State private var addingCircle = false

    private var zones: [Zone] { model.state?.zones ?? [] }
    private var districts: [District] { model.state?.city.districts ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: Copy.places_title, back: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text(Copy.places_intro).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if zones.isEmpty {
                        EmptyState(glyph: PoruchIcons.district, title: Copy.places_empty_title, message: Copy.places_empty_hint)
                    } else {
                        GroupedRows {
                            ForEach(Array(zones.enumerated()), id: \.element.key) { position, zone in
                                if position > 0 {
                                    Divider().overlay(Palette.hairline).padding(.leading, typeSize.isAccessibilitySize ? Space.lg : Space.lg + 40 + Space.md)
                                }
                                row(zone)
                            }
                        }
                    }
                    VStack(spacing: Space.sm) {
                        // Місто без районів (ще не приїхали чи їх нема) — лише коло.
                        if !districts.isEmpty {
                            SecondaryButton(title: Copy.places_add_district, glyph: PoruchIcons.district) { addingDistrict = true }
                        }
                        SecondaryButton(title: Copy.places_add_circle, glyph: PoruchIcons.pin) { addingCircle = true }
                    }
                    if zones.count >= Int(ZoneRules.shared.MAX) {
                        Text(Copy.places_full("\(ZoneRules.shared.MAX)")).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Space.page).padding(.bottom, Space.section)
            }
        }
        .background(Palette.canvas)
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $addingDistrict) { DistrictsView(from: "places").presentationDetents([.medium, .large]) }
        .fullScreenCover(isPresented: $addingCircle) {
            CirclePicker(start: (model.state?.city.latitude ?? HomeLocation.companion.Kyiv.latitude,
                                 model.state?.city.longitude ?? HomeLocation.companion.Kyiv.longitude))
        }
    }

    private func row(_ zone: Zone) -> some View {
        let shown = describe(zone)
        return HStack(spacing: Space.md) {
            // На найбільших кеглях плитка забирала ширину, і «Подільський» рвався посеред слова.
            if !typeSize.isAccessibilitySize {
                PoruchIcon(glyph: shown.glyph, size: 20).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(shown.title).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                Text(shown.subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.leading)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button { model.app.removeZone(key: zone.key) } label: {
                PoruchIcon(glyph: PoruchIcons.close, size: 18).foregroundStyle(Palette.inkTertiary).tapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.places_remove(shown.title))
        }
        .padding(.leading, Space.lg).padding(.trailing, Space.sm).padding(.vertical, Space.md)
    }

    /// Район — назва й «Район» / «Місцевість» (з іншого міста — і місто); коло — радіус і район центру.
    private func describe(_ zone: Zone) -> (glyph: PoruchGlyph, title: String, subtitle: String) {
        if let area = zone as? ZoneArea {
            let locality = districts.first { $0.id == area.districtId }?.isLocality == true
            let city = area.city == model.state?.city.name ? nil : area.city
            let subtitle = [locality ? Copy.places_locality : Copy.places_district, city].compactMap { $0 }.joined(separator: " · ")
            return (PoruchIcons.district, area.name, subtitle)
        }
        let circle = zone as? ZoneCircle
        let km = Int(circle?.radiusM ?? ZoneRules.shared.RADIUS) / 1000
        return (PoruchIcons.pin, Copy.places_circle(Copy.places_radius("\(km)")), circle?.label ?? Copy.places_point)
    }
}

/// Діаметр кола на екрані після вибору радіуса, pt: дві третини ширини телефона, і над нижньою панеллю лишається мапа.
private let circleSide = 250.0

/// Коло на мапі: ціль у центрі, мапа їде під нею, як у виборі точки редактора. Коло — радіус у метрах, переведений у pt
/// масштабом мапи на кожен кадр, тож росте й меншає разом із нею.
private struct CirclePicker: View {
    let start: (latitude: Double, longitude: Double)
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = MapController()
    @State private var center: (latitude: Double, longitude: Double)
    @State private var radius = Int(ZoneRules.shared.RADIUS)
    /// Метрів на pt у центрі. Nil, поки мапа його не сказала.
    @State private var metersPerPoint: Double?
    private let radii = ZoneRules.shared.RADII.map { Int(truncating: $0) }

    init(start: (latitude: Double, longitude: Double)) {
        self.start = start
        _center = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            EventMap(
                events: [], latitude: start.latitude, longitude: start.longitude,
                // Коло в 2 км тут має якраз `circleSide`.
                centerZoom: 11.6,
                selected: { _ in },
                moved: { _ in },
                centerChanged: { center = ($0, $1) },
                scaleChanged: { metersPerPoint = $0 },
                controller: controller
            )
            .ignoresSafeArea()
            // Центр мапи — центр усього екрана, а не безпечної зони: коло й ціль теж. Накладкою на порожнє: коло, ширше
            // за екран, інакше розпирало б розкладку й зсувало все вбік.
            Color.clear
                .overlay {
                    if let metersPerPoint, metersPerPoint > 0 {
                        // Межа — перфорацією, як межа району на мапі. Дуже близько коло ширше за будь-який екран: стеля.
                        let side = min(CGFloat(Double(radius) * 2 / metersPerPoint), 6000)
                        Circle().fill(Palette.ink.opacity(0.1))
                            .overlay(Circle().strokeBorder(Palette.ink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [0, 8])))
                            .frame(width: side, height: side)
                    }
                }
                .overlay { PoruchIcon(glyph: PoruchIcons.pin, size: 36).foregroundStyle(Palette.brand).offset(y: -18) }
                .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                PageHeader(title: Copy.places_circle_title) {
                    Button(Copy.cancel) { dismiss() }
                        .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).tapTarget()
                }
                .background(Palette.canvas)
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: Space.sm) {
                        ZoomButton(glyph: PoruchIcons.plus, label: Copy.zoom_in) { controller.zoomIn() }
                        ZoomButton(glyph: PoruchIcons.minus, label: Copy.zoom_out) { controller.zoomOut() }
                    }
                }
                .padding(Space.lg)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: Space.md) {
                    Text(Copy.places_circle_hint).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SegmentedPill(
                        items: radii.map { Copy.places_radius("\($0 / 1000)") },
                        selection: radii.firstIndex(of: radius) ?? 0
                    ) { pick(radii[$0]) }
                    PrimaryButton(title: Copy.places_circle_save, glyph: PoruchIcons.bell) { save() }
                }
                .padding(Space.page)
                .background(Palette.surface.ignoresSafeArea(edges: .bottom))
            }
            // Шапка й панель не ростуть безмежно: на найбільших кеглях вони з'їдали мапу й різали головну кнопку.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    /// Обране коло — цілим на екрані: 3 км з близького масштабу виходили за всі краї, і коло зникало. Мапа віддаляється
    /// чи наближається так, щоб коло мало ті самі ~250 pt.
    private func pick(_ meters: Int) {
        radius = meters
        if let metersPerPoint { controller.zoom(by: log2(metersPerPoint * circleSide / Double(2 * meters))) }
    }

    /// `followCircle` — перемикач: те саме коло вдруге зняло б його, тож наявне лишаємо як є.
    private func save() {
        let key = ZoneRules.shared.circle(latitude: center.latitude, longitude: center.longitude, radiusM: Int32(radius), districts: []).key
        if model.state?.zones.contains(where: { $0.key == key }) != true {
            model.app.followCircle(latitude: center.latitude, longitude: center.longitude, radiusM: Int32(radius), from: "places")
        }
        dismiss()
    }
}
