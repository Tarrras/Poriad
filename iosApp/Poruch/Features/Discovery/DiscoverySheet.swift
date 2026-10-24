import SwiftUI
import Shared

private let tabBarInset: CGFloat = 92
/// Повітря між рядком лічильника і каруселлю.
private let deckGap: CGFloat = Space.md
/// Скільки мапи лишаємо над повністю піднятою шторкою. Фільтри повертаються в половинному положенні.
private let sheetTopInset: CGFloat = Space.sm
/// Скільки списку має бути видно в половинному положенні понад поріг: шапка з плитками й рядок.
private let halfListMin: CGFloat = 160
/// Частка інерції пальця, що схиляє вибір положення шторки.
private let coastShare: CGFloat = 0.25

/// Положення шторки: згорнута (карусель), половина, повний екран. Окремого режиму списку нема.
enum SheetDetent {
    case peek, half, full
}

/// Прокрутка списку в шторці від його початку.
private struct ListOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private extension View {
    /// Зсув ScrollView від початку, вниз додатний, у `offset`. На iOS 18+ від самої прокрутки: GeometryReader
    /// у фоні вмісту на новіших системах не оновлюється, і зсув застрягав на нулі. На iOS 17 читає
    /// preference `ListOffsetKey`, який вміст має виставити сам у просторі "sheetList".
    @ViewBuilder
    func listOffset(_ offset: Binding<CGFloat>) -> some View {
        if #available(iOS 18, *) {
            onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, new in
                offset.wrappedValue = new
            }
        } else {
            coordinateSpace(name: "sheetList")
                .onPreferenceChange(ListOffsetKey.self) { offset.wrappedValue = $0 }
        }
    }
}

/// Живий зсув шторки: міняється щокадру, тож живе поза `@State` кореня. Його читає лише `SheetFrame`,
/// а мапа, карусель і фільтри над нею не перемальовуються на кожен кадр жесту.
final class SheetDrag: ObservableObject {
    @Published var value: CGFloat = 0
    /// Прокрутка списку від початку; потрібна лише жесту, тож без публікації.
    var listOffset: CGFloat = 0
}

/// Висота шторки йде за пальцем: перемальовується цей view, а не корінь мапи.
private struct SheetFrame<Content: View>: View {
    @ObservedObject var drag: SheetDrag
    let detent: SheetDetent
    let heights: (SheetDetent) -> CGFloat
    /// Шторка вже більша за згорнуту. Від живої висоти, а не від положення: вміст стає списком, щойно є місце.
    @Binding var expanded: Bool
    @ViewBuilder let content: Content

    private var height: CGFloat { min(max(heights(detent) - drag.value, heights(.peek)), heights(.full)) }

    var body: some View {
        content
            .frame(height: height, alignment: .top)
            .onChange(of: height, initial: true) { _, height in
                let now = height > heights(.peek) + Space.section
                if now != expanded { expanded = now }
            }
    }
}

/// Шторка над мапою: згорнута — карусель, піднята — список тієї ж видачі. Карусель і мапа ділять один вибір.
/// Положення, зсув і розмір екрана тримає `DiscoveryView`: шторку переводять і мапа, і пошук, і стос.
struct DiscoverySheet: View {
    /// Наскільки піднята шторка зі списком.
    let detent: SheetDetent
    /// Зсув пальця по ручці шторки, вниз додатний, і прокрутка списку. Корінь їх не спостерігає: кадр жесту
    /// перемальовує лише `SheetFrame`.
    let drag: SheetDrag
    /// Шторка вже більша за згорнуту; ставить `SheetFrame` на перетині порога.
    @Binding var expanded: Bool
    /// Розмір екрана під контролами: з нього рахуються висоти шторки.
    let screen: CGSize
    /// Росте з «До міста» і переходом з головної: карусель з чистого аркуша.
    let centerToken: Int
    /// Перевести шторку в положення (`DiscoveryView.open`).
    let open: (SheetDetent) -> Void
    /// Деталі події поверх мапи.
    let openDetail: (String) -> Void
    /// «До міста»: мапа на місто, без стосу піна.
    let recenter: () -> Void
    let locate: () -> Void
    /// Гість натиснув «Стежити»: вхід.
    let askAuth: () -> Void
    /// Скинути фільтри з порожньої картки так, щоб їх можна було повернути.
    let resetFilters: () -> Void
    let createEvent: (String) -> Void
    /// «Ближче до мене» чекає на положення.
    let locating: Bool
    let toggleNear: () -> Void
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    private var explore: ExploreScreenModel { model.exploreScreen }
    private var view: ExploreScreenState { explore.state }
    /// Зсув пальця по списку в момент, коли протягування перейшло від списку до шторки. `nil` — список сам по собі.
    @State private var listDrag: CGFloat?
    /// VoiceOver не тягне шторку жестом: з ним список гортається й у половинному положенні.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private var listEntries: [EventIndexEntry] { view.listEntries }
    /// Завантажені картки шторки: для каруселі й списку. Може бути менше за `listEntries`: решту список просить сам.
    private var shownEvents: [Event] { view.deckEvents }
    private var deckEvents: [Event] { view.deckEvents }

    var body: some View {
        SheetFrame(drag: drag, detent: detent, heights: height(of:), expanded: $expanded) {
            VStack(spacing: 0) {
                handle
                if !expanded {
                    // Подій нема — лише коли порожній сам список: картки району чи категорії часто ще їдуть.
                    if deckEvents.isEmpty {
                        if !view.loading && listEntries.isEmpty { quietCard.padding(.horizontal, Space.page) }
                    } else {
                        EventDeck(
                            events: deckEvents, selectedID: view.selectedId, savedIDs: explore.savedIDs,
                            select: { model.app.selectEvent(id: $0) },
                            open: openEvent,
                            toggleSaved: { model.app.toggleSaved(id: $0) }
                        )
                        // «До міста», перехід з головної і новий запит (фільтр, пошук, місто): карусель з чистого аркуша, з першої
                        // картки. Інакше нова видача показувалась з позиції старої, посеред списку й зсунута на пів картки.
                        // Нова карусель, а не `scrollTo(first)`: `scrollPosition` тримається за id картки, і видача, що приїжджає
                        // слідом, ставила карусель знову посередині. Перебудова дешева: `LazyHStack` має 2–3 видимі картки.
                        // «Ближче до мене» теж: перша картка — найближча.
                        .id("\(centerToken)/\(view.queries)/\(view.nearMe)")
                        .padding(.top, deckGap)
                    }
                } else {
                    list
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, tabBarInset)
        }
        .background {
            // Згорнутій шторці підкладка не потрібна. Прозорий фон ловив би дотики замість мапи.
            if expanded {
                RoundedRectangle(cornerRadius: Corner.xl, style: .continuous)
                    .fill(Palette.canvas)
                    .lifted(Elevation.overlay)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .motion(Motion.spring, value: detent)
    }

    private func height(of detent: SheetDetent) -> CGFloat {
        switch detent {
        case .peek: return peekHeight
        // Не нижче за поріг списку з кількома рядками: на SE з великим шрифтом 55 % екрана були нижчими за поріг, і
        // «Показати списком» лише підкидав карусель. Не вміщається — половина й є повна.
        case .half: return min(max(screen.height * 0.55, peekHeight + Space.section + halfListMin), height(of: .full))
        case .full: return max(screen.height - sheetTopInset, peekHeight)
        }
    }

    /// Згорнута шторка: рядок лічильника, карусель і місце під таббар.
    @ScaledMetric(relativeTo: .body) private var cardHeight = mapCardHeight
    private var peekHeight: CGFloat { 44 + deckGap + Space.sm + scaledMapCardHeight(cardHeight) + tabBarInset }

    /// Ручка шторки: тягнеться і натискається, тож список доступний і для VoiceOver.
    private var handle: some View {
        // Один контейнер на всі положення, жест на ньому. Дві гілки `if` перебудовували
        // подання під час жесту, і протягування вмирало на півдорозі.
        VStack(spacing: Space.sm) {
            Capsule().fill(Palette.inkTertiary)
                .frame(width: 36, height: expanded ? 4 : 0)
                .opacity(expanded ? 1 : 0)
                .padding(.top, expanded ? Space.sm : 0)
            if expanded {
                ListHeader(detent: detent, open: open, askAuth: askAuth, locating: locating, toggleNear: toggleNear)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
            } else {
                PeekHeader(recenter: recenter, locate: locate, openList: { open(.half) }, askAuth: askAuth)
            }
        }
        .padding(.horizontal, Space.page)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    /// Протягування шторки на шапці. Список має свій жест: `listDragGesture`.
    private var dragGesture: some Gesture {
        // Екранні координати: у власних шапка їде разом зі шторкою, і відліки тремтять.
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in drag.value = value.translation.height }
            .onEnded { value in
                settle(translation: value.translation.height, predicted: value.predictedEndTranslation.height)
            }
    }

    private var list: some View {
        VStack(spacing: 0) {
            // І в стосі: категорія звужує події закладу, як дата й «Від людей» над мапою, а не виводить у місто.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(categories, id: \.0) { entry in
                        // Та сама категорія, що у «Фільтрах»: звужує й мапу. Число — серед міста чи закладу, як лічильник після тапу.
                        CategoryTile(category: entry.0, selected: view.category == entry.0, counted: true,
                                     count: view.countOf(category: entry.0)?.intValue) {
                            explore.toggleCategory(entry.0)
                        }
                    }
                }
            }
            .railContentPadding()
            // Висота — за вмістом: над порожньою карткою шторка стискала ряд, і `minimumScaleFactor` дрібнив підписи плиток.
            .fixedSize(horizontal: false, vertical: true)
            if shownEvents.isEmpty && view.districts.isEmpty && view.places.isEmpty && view.artists.isEmpty {
                if view.loading || !listEntries.isEmpty {
                    PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
                } else {
                    quietCard.padding(Space.page)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    SheetRows(open: openEvent, focusPlace: focusPlace, selectDistrict: { explore.selectDistrict($0) }, loadMore: loadMore(reaching:))
                }
                .listOffset(Binding(get: { drag.listOffset }, set: { drag.listOffset = $0 }))
                // Список гортається лише в повній шторці; нижче протягування піднімає її. Вимкнення
                // під час жесту скасовує прокрутку UIKit, і шторка їде замість гумового краю.
                // VoiceOver жестом шторку не підніме: з ним список гортається й у половинному положенні.
                .scrollDisabled(!voiceOver && (detent != .full || listDrag != nil))
                // Нижче повної список не гортається, і жест має перебити натискання картки, інакше
                // протягування відкривало її. У повній він лише йде поруч із прокруткою UIKit.
                .highPriorityGesture(listDragGesture, including: detent == .full ? .subviews : .all)
                .simultaneousGesture(listDragGesture, including: detent == .full ? .all : .subviews)
            }
        }
    }

    private var quietCard: some View { QuietCard(resetFilters: resetFilters, createEvent: createEvent) }

    private func openEvent(_ id: String) {
        model.app.selectEvent(id: id)
        openDetail(id)
    }

    /// Заклад з пошуку: шторку опускаємо, щоб бачити мапу, а стос відкриє `showPlace`, коли приїде видача.
    private func focusPlace(_ place: Place) {
        open(.peek)
        explore.focusPlace(place)
    }

    /// Прокрутка списку тягне шторку: угору — доки не повна, униз від верху списку — опускає її.
    private var listDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dy = value.translation.height
                if listDrag == nil {
                    // Після сідання на згорнуту список зникає, а жест ще шле оновлення.
                    guard detent != .peek else { return }
                    // У повній шторці список гортається сам; беремо жест, лише коли він на початку і палець іде вниз.
                    guard detent != .full || (drag.listOffset <= 0.5 && dy > 0) else { return }
                    listDrag = dy
                }
                guard let origin = listDrag else { return }
                let shift = dy - origin
                // Нижче порога список зникає разом із жестом, тож сідаємо на згорнуту звідси.
                if height(of: detent) - shift <= height(of: .peek) + Space.section {
                    listDrag = nil
                    open(.peek)
                    return
                }
                drag.value = shift
            }
            .onEnded { value in
                guard let origin = listDrag else { return }
                listDrag = nil
                settle(translation: value.translation.height - origin, predicted: value.predictedEndTranslation.height - origin)
            }
    }

    /// Куди відпустити шторку: до найближчого положення. Інерція лише схиляє вибір (`coastShare`).
    private func settle(translation: CGFloat, predicted: CGFloat) {
        let released = height(of: detent) - translation
        let target = released - (predicted - translation) * coastShare
        let nearest = [SheetDetent.peek, .half, .full]
            .min { abs(height(of: $0) - target) < abs(height(of: $1) - target) } ?? .peek
        // Нове положення і скидання зсуву в одному оновленні, інакше стрибок.
        open(nearest)
    }

    /// Наступне вікно карток біля краю завантаженого.
    private func loadMore(reaching position: Int) {
        guard shownEvents.count < listEntries.count else { return }
        guard position >= shownEvents.count - cardPrefetchAhead else { return }
        explore.loadHead(shownEvents.count + cardPage)
    }
}

/// Шапка згорнутої шторки: керування мапою, лічильник, що відкриває список, і на стосі — «Стежити» й вихід.
private struct PeekHeader: View {
    let recenter: () -> Void
    let locate: () -> Void
    let openList: () -> Void
    let askAuth: () -> Void
    @Environment(\.appModel) private var appModel
    private var view: ExploreScreenState { appModel!.exploreScreen.state }

    var body: some View {
        HStack(spacing: Space.sm) {
            // Керування мапою в зоні великого пальця. Це кнопки, тож за них шторку не тягнуть — лише за решту ряду.
            // До міста — без стосу піна: інакше мапа стояла на місті, а шторка далі казала «Тут подій: 10».
            IconPill(glyph: PoruchIcons.recenter, label: Copy.recenter, size: 40, action: recenter)
            IconPill(glyph: PoruchIcons.myLocation, label: Copy.nearby, size: 40, action: locate)
            Spacer(minLength: 0)
            // Не `Button`: кнопка забирає дотик, і протягнути шторку за неї не виходить.
            HStack(spacing: Space.sm) {
                if view.loading { ProgressView().controlSize(.mini) }
                else if view.offline {
                    PoruchIcon(glyph: PoruchIcons.wifiOff, size: 15).foregroundStyle(Palette.accent)
                }
                // Карусель — від найближчої: видно й без піднятої шторки, де живе сам перемикач.
                if view.nearMe { PoruchIcon(glyph: PoruchIcons.myLocation, size: 15).foregroundStyle(Palette.inkSecondary) }
                // Зі «Стежити» чи на великому шрифті «Тут подій: 12» не влазить: лишається число, а не «Тут по…».
                // Повний текст VoiceOver чує з підпису кнопки.
                ViewThatFits(in: .horizontal) {
                    Text(countLabel(view)).lineLimit(1)
                    Text(view.loading ? countLabel(view) : view.offline ? Copy.offline_count("\(view.listCount)") : "\(view.listCount)")
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .font(PoruchFont.label).foregroundStyle(Palette.ink)
                PoruchIcon(glyph: PoruchIcons.chevronUp, size: 14).foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, Space.lg).frame(minHeight: 40)
            .cardSurface(radius: Corner.pill, elevation: Elevation.raised)
            // Пігулка 40 — головний вхід у список: ціль 44, як у решти кнопок.
            .tapTarget()
            .onTapGesture { openList() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Copy.a11y_show_list(view.nearMe ? "\(countLabel(view)), \(Copy.nearer_me)" : countLabel(view)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { openList() }
            .coachTarget(.sheet)
            if view.stackFocused {
                StackFollowButton(iconOnly: true, askAuth: askAuth)
                // 40, як дзвінок і кнопки ліворуч: 48 вилазила за рядок 44.
                ClearStackButton(size: 40)
            }
        }
        .frame(height: 44)
    }
}

/// Шапка піднятої шторки: що в списку і де. Тягнуть її за жест `DiscoverySheet`.
private struct ListHeader: View {
    let detent: SheetDetent
    let open: (SheetDetent) -> Void
    let askAuth: () -> Void
    let locating: Bool
    let toggleNear: () -> Void
    @Environment(\.appModel) private var appModel
    private var view: ExploreScreenState { appModel!.exploreScreen.state }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                // Стос закладу — це заклад: назва заголовком, а не «усе, що стоїть на обраному піні». Кондензом, як
                // заголовки решти шторок.
                Text(view.stackPlace?.name ?? countLabel(view)).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    // VoiceOver не тягне шторку: висоту він міняє діями на заголовку.
                    .accessibilityAction(named: detent == .full ? Copy.a11y_sheet_half : Copy.a11y_sheet_full) {
                        open(detent == .full ? .half : .full)
                    }
                Text(view.stackPlace != nil ? countLabel(view) : areaLabel(view)).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(2)
                // Під підписом, а не в ряду: лічильник і дві кнопки праворуч не лишають йому місця.
                if view.stackPlace != nil { StackFollowButton(iconOnly: false, askAuth: askAuth).padding(.top, Space.sm) }
                // Те саме гніздо в місті: порядок — властивість списку, який піднімають, щоб зіставити. У стосі чипа нема:
                // одне місце — одна відстань.
                if !view.stackFocused {
                    Chip(label: Copy.nearer_me, glyph: PoruchIcons.myLocation, selected: view.nearMe || locating, action: toggleNear)
                        .padding(.top, Space.sm)
                }
            }
            Spacer(minLength: Space.sm)
            if view.stackFocused { ClearStackButton(size: 48) }
            IconPill(glyph: PoruchIcons.chevronDown, label: Copy.show_map) { open(.peek) }
        }
        .padding(.bottom, Space.md)
    }
}

/// Вихід із фокуса на піні знімає і підсвітку, інакше мапа й список розходились.
private struct ClearStackButton: View {
    let size: CGFloat
    @Environment(\.appModel) private var appModel

    var body: some View {
        IconPill(glyph: PoruchIcons.close, label: Copy.show_all_events, size: size) {
            appModel!.exploreScreen.clearStack()
        }
    }
}

/// «Стежити» за закладом стосу. Гостя ведемо на вхід: пуш прив'язаний до акаунта.
private struct StackFollowButton: View {
    let iconOnly: Bool
    let askAuth: () -> Void
    @Environment(\.appModel) private var appModel
    private var explore: ExploreScreenModel { appModel!.exploreScreen }

    var body: some View {
        if let place = explore.state.stackPlace {
            FollowPill(following: explore.state.stackFollowing, iconOnly: iconOnly) {
                if !explore.toggleFollowStack() { askAuth() }
            }
            // Дзвінок без підпису в згорнутій шапці: VoiceOver має чути, за чим стежити.
            // Назва стала, стан — трейтом «вибрано»: «Не стежити» разом із «вибрано» суперечили одне одному.
            .accessibilityLabel(Copy.a11y_follow_name(place.name))
            .accessibilityAddTraits(explore.state.stackFollowing ? .isSelected : [])
        }
    }
}

/// Список піднятої шторки: заклади й артисти, під ними події.
private struct SheetRows: View {
    let open: (String) -> Void
    let focusPlace: (Place) -> Void
    /// Район з пошуку. Шторку опускає `DiscoveryView`, коли район змінився: так само й для району з головної.
    let selectDistrict: (DistrictHit) -> Void
    /// Довантажити картки, коли рядок `position` з'явився біля краю завантаженого.
    let loadMore: (Int) -> Void
    @Environment(\.appModel) private var appModel
    private var explore: ExploreScreenModel { appModel!.exploreScreen }
    private var view: ExploreScreenState { explore.state }

    var body: some View {
        LazyVStack(spacing: Space.sm) {
            // Райони — першими: їх у місті до десяти, і запит «Київський» найчастіше саме про район.
            if !view.districts.isEmpty {
                DistrictsGroup(districts: view.districts) { selectDistrict($0) }.padding(.bottom, Space.md)
            }
            // Заклади — над подіями: список подій довгий, під ним їх ніхто б не побачив.
            if !view.places.isEmpty {
                PlacesGroup(places: view.places) { focusPlace($0) }.padding(.bottom, Space.md)
            }
            if !view.artists.isEmpty { ArtistsGroup(artists: view.artists).padding(.bottom, Space.md) }
            // Рядки з малим корінцем, як у пошуку головної: список відкривають, щоб зіставити варіанти, і
            // картка з фото 180 давала півтори події на екран. Фото й «Зберегти» — на картці каруселі й у деталях.
            ForEach(Array(view.deckEvents.enumerated()), id: \.element.id) { position, event in
                EventResultRow(event: event, waitlisted: explore.waitlistedIDs.contains(event.id), distance: distanceLabel(view.kmFromMe(event: event), within: Int(view.nearWithinKm))) {
                    open(event.id)
                }
                .cardSurface()
                // Список довантажує картки сам, а не лише карусель.
                .onAppear { loadMore(position) }
            }
            if view.deckEvents.count < view.listEntries.count {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.lg)
            }
        }
        .padding(.horizontal, Space.page).padding(.top, Space.md).padding(.bottom, Space.section)
        .background {
            // Запасний вимір для iOS 17; на 18+ його не читають.
            GeometryReader { proxy in
                Color.clear.preference(key: ListOffsetKey.self, value: -proxy.frame(in: .named("sheetList")).minY)
            }
        }
    }
}

/// Порожньо: називаємо те, що справді звужує видачу, і даємо одну дію — прибрати це або зібрати своїх.
private struct QuietCard: View {
    let resetFilters: () -> Void
    let createEvent: (String) -> Void
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }
    private var view: ExploreScreenState { model.exploreScreen.state }

    var body: some View {
        let query = view.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Дія — у рядку заголовка: у згорнутій шторці картка має висоту каруселі, і під текстом дія зрізала підказку.
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(Copy.nothing_here).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                if !query.isEmpty, let hit = view.districts.first {
                    // Слово — назва району: подій із ним нема, а район є. Дія — туди, а не «очистити».
                    quietAction(Copy.show_district) { model.exploreScreen.selectDistrict(hit) }
                } else if !query.isEmpty {
                    quietAction(Copy.clear_search) { model.app.setSearchText(query: "") }
                } else if view.activeFilters > 0 {
                    quietAction(Copy.reset_filters_action, action: resetFilters)
                } else if view.district != nil {
                    // Порожній район — звичайна справа: афіша в центрі, а спальні райони часто тихі. Вихід — усе місто.
                    quietAction(Copy.whole_city) { model.exploreScreen.showWholeCity() }
                } else {
                    quietAction(Copy.create) { createEvent("map") }
                }
            }
            // У стосі область мапи не допоможе: тут звужують лише фільтри.
            Text(hint(query))
                .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    private func hint(_ query: String) -> String {
        if !query.isEmpty, let hit = view.districts.first { return Copy.nothing_for_query_district(query, hit.district.name) }
        if !query.isEmpty { return Copy.nothing_for_query(query) }
        if view.stackFocused { return Copy.nothing_here_stack }
        if let district = view.district, view.activeFilters == 0 { return Copy.nothing_in_district(district.locative) }
        return Copy.nothing_here_hint
    }

    /// Текстова дія порожньої картки: картка лежить над мапою в згорнутій шторці, повна кнопка 52 її б не вмістила.
    private func quietAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(PoruchFont.button).foregroundStyle(Palette.ink)
        }
        .tapTarget()
    }
}

/// Лічильник шторки: з індексу, а не з `totalFound` чи завантажених карток.
private func countLabel(_ view: ExploreScreenState) -> String {
    if view.loading { return Copy.searching }
    let count = view.stackFocused ? Copy.events_here("\(view.listCount)") : Copy.events_found("\(view.listCount)")
    // Офлайн словами, а не лише гліфом: видача — збережена, і це треба знати.
    return view.offline ? Copy.offline_count(count) : count
}

/// Відстань у рядку з «Ближче до мене»: цілими км, а в межах похибки положення — «до 3 км». Nil — перемикач вимкнено.
private func distanceLabel(_ km: KotlinInt?, within: Int) -> String? {
    guard let km = km?.intValue else { return nil }
    return km == 0 ? Copy.distance_within("\(within)") : Copy.distance_km("\(km)")
}

/// Що показує екран: пін, область рукою чи ціле місто.
private func areaLabel(_ view: ExploreScreenState) -> String {
    if view.stackFocused { return Copy.area_stack }
    if let district = view.district, !view.customArea { return Copy.area_district(district.locative) }
    return view.customArea ? Copy.area_custom : Copy.area_city("\(view.cityName)")
}
