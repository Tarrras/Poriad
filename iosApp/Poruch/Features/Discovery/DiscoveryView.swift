import SwiftUI
import Shared

/// The date filters the map offers, in the order they are shown. Both the chip row and the filter
/// sheet read this list, so the two can never drift apart.
var dateFilterKeys: [String] { [DateFilter.shared.ANY, DateFilter.shared.TODAY, DateFilter.shared.WEEKEND] }

func dateLabel(_ key: String) -> String {
    switch key {
    case DateFilter.shared.TODAY: "Сьогодні"
    case DateFilter.shared.WEEKEND: "Вихідні"
    default: "Будь-коли"
    }
}

private let topControlsInset: CGFloat = 196
private let carouselInset: CGFloat = 268
private let tabBarInset: CGFloat = 92
/**
 Скільки лишаємо над шторкою, коли її підняли повністю.

 Смужка мапи, а не панель контролів: у верхньому положенні шторка має закривати екран, як шторка
 деталей події. Фільтри лишаються на відстані одного потягування вниз — у половинному положенні
 вони знову над нею.
 */
private let sheetTopInset: CGFloat = Space.sm

/**
 Три положення шторки зі списком.

 Списку немає окремого режиму: він живе в тій самій шторці, згорнутий стан якої — це карусель.
 Доки режим був окремий, вкладка «Мапа» показувала список без мапи й без п'яти фільтрів із шести,
 а повернутись можна було лише кнопкою, яка сама переїжджала з нижнього кута у верхній.
 */
private enum SheetDetent {
    case peek, half, full
}

struct DiscoveryView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var location = LocationFinder()
    @State private var citySearch = false
    @State private var details = false
    @State private var filters = false
    @State private var mapFailed = false
    @State private var retryToken = 0
    @State private var centerToken = 0
    @State private var region: MapRegion?
    /// Події, що стоять на одній точці. Кеш майданчиків дає всім подіям закладу ті самі
    /// координати, тож без фокуса решта стосу недосяжна з мапи.
    @State private var stackIDs: [String] = []
    /// Наскільки піднята шторка зі списком.
    @State private var detent: SheetDetent = .peek
    /**
     Скільки пальця вже пройдено по ручці шторки. Вниз — додатне.

     Звичайний стан, а не `@GestureState`: той скидається сам, окремим оновленням від того, у
     якому шторка дізнається нове положення. Через це на відпусканні вона встигала стрибнути назад
     до висоти старого положення й аж тоді їхала до нового. Тут скидання й нове положення
     приїжджають разом.
     */
    @State private var sheetDrag: CGFloat = 0
    /// Розмір екрана під контролами: з нього рахуються висоти шторки.
    @State private var screen: CGSize = .zero
    /// Категорія, обрана плитками в шторці. Звужує список, а не мапу.
    @State private var listCategory = AppStateKt.ALL_CATEGORIES
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Pins are a set and have no order; the carousel and the list do, and it is the same order
    /// home shows — what the answers put first is what the thumb reaches first.
    /// Зібрано в [AppModel] один раз на емісію стану, а не на кожне перемальовування екрана.
    /// Категорія мапи. Головна має свою — вибір на одному екрані не чіпає другий.
    private var category: String { model.state?.category ?? AppStateKt.ALL_CATEGORIES }

    /**
     Що малює мапа: індекс області, звужений до обраної категорії.

     Фільтр тут, а не в запиті до сервера. Доки категорія їхала в `EventQuery`, вона звужувала сам
     індекс — і мапа, відфільтрована на «музику», звужувала й те, що бачить головна.
     */
    var mapEntries: [EventIndexEntry] {
        let all = category == AppStateKt.ALL_CATEGORIES
        return all ? model.mapEntries : model.mapEntries.filter { $0.category == category }
    }
    private var selectedID: String? { model.state?.selectedEvent?.id }
    private var savedIDs: Set<String> { model.savedIDs }

    /// Події обраного піна, у порядку індексу. Порожньо, якщо від стосу після нової видачі
    /// нічого не лишилось — тоді фокусувати нема на чому.
    private var stackEntries: [EventIndexEntry] {
        stackIDs.isEmpty ? [] : mapEntries.filter { stackIDs.contains($0.id) }
    }
    private var stackFocused: Bool { !stackEntries.isEmpty }

    /**
     Що показує шторка: те, що стоїть на обраному піні, або вся видача — і те й те звужене
     категорією, обраною плитками **в самій шторці**.

     Плитки звужують список, а не мапу. Мапа має власну категорію — ту, що у фільтрах, — і піни
     під шторкою не мають перестроюватись від того, що людина гортає список за темою.
     */
    private var listEntries: [EventIndexEntry] {
        let base = stackFocused ? stackEntries : mapEntries
        guard listCategory != AppStateKt.ALL_CATEGORIES else { return base }
        return base.filter { $0.category == listCategory }
    }
    /// Картки списку, які вже завантажились. Їх може бути менше, ніж [listEntries]: решту
    /// список просить сам, доки його гортають.
    private var shownEvents: [Event] { listEntries.compactMap { model.cardsByID[$0.id] } }
    private var activeFilters: Int {
        [model.state?.dateFilter != DateFilter.shared.ANY, model.state?.category != AppStateKt.ALL_CATEGORIES, model.state?.onlyAvailable == true]
            .filter { $0 }.count
    }
    var body: some View {
        ZStack(alignment: .top) {
            EventMap(
                events: mapEntries, latitude: model.state?.cityLatitude ?? 50.45, longitude: model.state?.cityLongitude ?? 30.52,
                selectedID: selectedID, eventsRevision: model.eventsRevision, filterKey: category,
                retryToken: retryToken, centerToken: centerToken,
                topInset: topControlsInset, bottomInset: carouselInset,
                loadFailed: { mapFailed = $0 },
                // Пін тапнули — значить, дивляться на мапу: шторка сходить із дороги й показує
                // картку саме тієї події.
                selected: { model.app.selectEvent(id: $0.id); open(.peek) },
                selectedStack: { ids in
                    // Пін представляє місце, а не подію: у фокус іде все, що на ньому стоїть, —
                    // і одна подія так само, як десять.
                    stackIDs = ids
                    // Стос — це не початок стрічки, тож вікно карток його не покриває: у київського
                    // майданчика на 32 події в нього потрапляли дві, і пін казав «32», а карусель
                    // під ним — «Тут подій: 2».
                    model.app.loadCards(ids: ids)
                    if let first = ids.first { model.app.selectEvent(id: first); open(.peek) }
                },
                moved: { region = $0 }
            )
            .ignoresSafeArea()
            LinearGradient(colors: [Palette.canvas.opacity(0.94), Palette.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 230).ignoresSafeArea(edges: .top).allowsHitTesting(false)
            VStack(spacing: Space.md) {
                topControls
                if mapFailed {
                    Button { mapFailed = false; retryToken += 1 } label: {
                        Label("Мапа недоступна · Повторити", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                            .padding(.horizontal, Space.lg).frame(height: 44).cardSurface(radius: 22, elevation: 6)
                    }.buttonStyle(.plain)
                }
                if region != nil {
                    PrimaryButton(title: "Шукати тут", symbol: "arrow.clockwise") {
                        if let region { model.app.searchArea(south: region.south, west: region.west, north: region.north, east: region.east) }
                        region = nil
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            sheet.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background {
            // Вимір, а не обгортка: висоти шторки рахуються від екрана, але сам екран у
            // `GeometryReader` не загортається — див. [statusBarInset] про ціну такої обгортки.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { screen = proxy.size }
                    .onChange(of: proxy.size) { _, value in screen = value }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: region == nil)
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: model.eventsRevision) { _, _ in region = nil }
        // Індекс повний з першої відповіді, картки — ні. Коли карусель підходить до краю
        // завантаженого, просимо наступне вікно за вже відомими ідентифікаторами.
        .onChange(of: selectedID) { _, id in
            guard let id, !stackFocused, shownEvents.count < listEntries.count else { return }
            guard let position = shownEvents.firstIndex(where: { $0.id == id }) else { return }
            if position >= shownEvents.count - cardPrefetchAhead { loadHead(shownEvents.count + cardPage) }
        }
        // Картки просять під ту категорію, яку показують. Без цього під фільтром список лишався
        // порожнім при лічильнику «1»: вікно карток стояло на початку **повного** індексу, а
        // єдина подія категорії лежала далеко за його краєм.
        .onChange(of: listCategory) { _, _ in loadHead(cardPage) }
        .onChange(of: category) { _, _ in loadHead(cardPage) }
        .onChange(of: model.eventsRevision) { _, _ in loadHead(cardPage) }
        .sheet(isPresented: $citySearch) { CitySearchView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $filters) { FiltersView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $details) {
            NavigationStack { EventDetailView(app: model.app) }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .onReceive(location.$coordinate) { coordinate in
            if let coordinate {
                model.app.selectCity(city: CityResult(name: "Поруч зі мною", latitude: coordinate.latitude, longitude: coordinate.longitude))
                region = nil
            }
        }
        .alert("Геолокація", isPresented: Binding(get: { location.message != nil }, set: { if !$0 { location.message = nil } })) {
            Button("Добре") { location.message = nil }
        } message: { Text(location.message ?? "") }
    }

    private var topControls: some View {
        VStack(spacing: Space.md) {
            SearchBar(
                placeholder: "Подія, місце або тема",
                initial: model.state?.searchText ?? "",
                activeFilters: activeFilters,
                onFilters: { filters = true }
            ) { model.app.setSearchText(query: $0) }
            HStack(spacing: Space.sm) {
                Button { citySearch = true } label: {
                    HStack(spacing: Space.sm) {
                        PoruchIcon(glyph: PoruchIcons.pin, size: 16).foregroundStyle(Palette.brand)
                        Text(model.state?.cityName ?? "Київ").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.inkSecondary)
                    }.padding(.horizontal, Space.lg).frame(height: 44).cardSurface(radius: 22, elevation: 6)
                }.buttonStyle(.plain).accessibilityLabel("Змінити місто")
                Spacer(minLength: 0)
                IconPill(symbol: "viewfinder", label: "Повернутися до міста") {
                    model.app.dismissEvent(); centerToken += 1
                }
                IconPill(symbol: "location", label: "Поруч зі мною") { location.request() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(dateFilterKeys, id: \.self) { key in
                        // Тап по вибраному чипу знімає вибір. Інакше звузити дату можна, а
                        // повернутись — лише знайшовши «Будь-коли», який до того ж міг виїхати
                        // за край рядка.
                        Chip(label: dateLabel(key), selected: model.state?.dateFilter == key) {
                            model.app.setDateFilter(filter: model.state?.dateFilter == key ? DateFilter.shared.ANY : key)
                        }
                    }
                    Chip(label: "Можна приєднатись", symbol: "checkmark.circle", selected: model.state?.onlyAvailable == true) {
                        model.app.setOnlyAvailable(available: !(model.state?.onlyAvailable ?? false))
                    }
                }
            }
            // Поля живуть усередині смуги, тож смуга йде від краю до краю: поля сторінки, які дає
            // стос над нею, тут знімаються.
            .railContentPadding()
            .padding(.horizontal, -Space.page)
        }
    }

    // ---------------------------------------------------------------- шторка зі списком

    /**
     Шторка над мапою: згорнута — це карусель, піднята — список тієї самої видачі.

     Карусель і мапа ділять один вибір: картка стала на місце — пін підсвітився; тапнули пін —
     карусель прокрутилась назад.
     */
    private var sheet: some View {
        VStack(spacing: 0) {
            sheetHandle
            if !expanded {
                if shownEvents.isEmpty {
                    if model.state?.loading != true { quietCard.padding(.horizontal, Space.page) }
                } else {
                    EventDeck(
                        events: shownEvents, selectedID: selectedID, savedIDs: savedIDs,
                        resetToken: centerToken,
                        select: { model.app.selectEvent(id: $0) },
                        open: { model.app.selectEvent(id: $0); details = true },
                        toggleSaved: { model.app.toggleSaved(id: $0) }
                    )
                }
            } else {
                sheetList
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, tabBarInset)
        // Висота йде за пальцем, а не за положенням: інакше під час протягування вміст лишається
        // завбільшки з попереднє положення, і над ним відкривається порожнє полотно.
        .frame(height: sheetHeight, alignment: .top)
        .background {
            // Згорнутою шторці підкладка не потрібна: карусель і лічильник висять просто над
            // мапою, як і висіли. Прозорий фон тут був би гірший за жодний — у SwiftUI він ловить
            // дотики й мапу під собою не віддає.
            if expanded {
                RoundedRectangle(cornerRadius: Corner.xl, style: .continuous)
                    .fill(Palette.canvas)
                    .lifted(Elevation.overlay)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: detent)
    }

    /// Скільки зараз займає шторка: висота положення плюс те, що вже пройшов палець.
    private var sheetHeight: CGFloat {
        min(max(height(of: detent) - sheetDrag, height(of: .peek)), height(of: .full))
    }

    /**
     Чи шторка вже більша за згорнуту.

     Рахується від живої висоти, а не від положення: вміст має мінятись на списком тоді, коли
     палець відкрив для нього місце, а не аж коли шторку відпустили.
     */
    private var expanded: Bool { sheetHeight > height(of: .peek) + Space.section }

    private func height(of detent: SheetDetent) -> CGFloat {
        switch detent {
        case .peek: return peekHeight
        case .half: return max(screen.height * 0.55, peekHeight)
        case .full: return max(screen.height - sheetTopInset, peekHeight)
        }
    }

    /// Згорнута шторка — це рядок лічильника й карусель під ним, разом із місцем під панель вкладок.
    private var peekHeight: CGFloat { 44 + Space.sm + mapCardHeight + tabBarInset }

    /**
     Ручка шторки.

     Тягнеться пальцем і натискається: жест сам себе не пояснює, а тап по лічильнику — пояснює.
     Обидва шляхи ведуть в одне місце, тож список лишається доступним і для VoiceOver, де жести
     протягування не працюють.
     */
    private var sheetHandle: some View {
        // Один стос на всі положення, і жест висить саме на ньому.
        //
        // Доки згорнута й піднята шапки були двома гілками `if`, перехід між ними знищував те
        // подання, на якому тримався жест, — і протягування вмирало на півдорозі. Швидкий кидок
        // устигав спрацювати до перебудови, повільний — ні. Тепер міняється вміст стоса, а сам
        // стос лишається тим самим тілом від початку руху до кінця.
        VStack(spacing: Space.sm) {
            Capsule().fill(Palette.inkTertiary)
                .frame(width: 36, height: expanded ? 4 : 0)
                .opacity(expanded ? 1 : 0)
                .padding(.top, expanded ? Space.sm : 0)
            if expanded { listHeader } else { peekHeader }
        }
        .padding(.horizontal, Space.page)
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
    }

    /**
     Протягування шторки.

     Живе тільки на шапці. Доки той самий жест стояв ще й на всьому вмісті, він відбирав у списку
     прокрутку: список і шторка тягнулись одночасно, а іноді шторка забирала рух собі цілком.
     */
    private var sheetDragGesture: some Gesture {
        // Координати — екранні, а не власні.
        //
        // `DragGesture` за замовчуванням міряє протягування в системі координат того подання, на
        // якому висить. Тут це подання — шапка шторки, і воно їде вгору рівно від того, що жест
        // повідомив. Палець зсувся на піксель — шторка виросла на піксель — шапка під пальцем
        // поїхала — наступний відлік прийшов меншим на той самий піксель. Звідси й дрібне
        // тремтіння на повільному русі, і великі стрибки на різкому. Екранна система координат
        // від руху шторки не залежить, тож коло розмикається.
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in sheetDrag = value.translation.height }
            .onEnded { value in
                settle(translation: value.translation.height, predicted: value.predictedEndTranslation.height)
            }
    }

    private var peekHeader: some View {
        HStack(spacing: Space.sm) {
            Spacer(minLength: 0)
            // Не `Button`: кнопка забирає дотик собі, і протягнути шторку за неї вже не виходить.
            // Тап і протягування тут стоять поруч на звичайному поданні.
            HStack(spacing: Space.sm) {
                if model.state?.loading == true { ProgressView().controlSize(.mini) }
                else if model.state?.offline == true {
                    Image(systemName: "wifi.slash").font(.system(size: 12)).foregroundStyle(Palette.accent)
                }
                Text(countLabel).font(PoruchFont.label).foregroundStyle(Palette.ink)
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, Space.lg).frame(height: 40)
            .cardSurface(radius: 20, elevation: 6)
            .contentShape(Capsule())
            .onTapGesture { open(.half) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(countLabel). Показати списком")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(.half) }
            if stackFocused { clearStackButton }
        }
        .frame(height: 44)
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(countLabel).font(PoruchFont.title2).foregroundStyle(Palette.ink)
                Text(areaLabel).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            if stackFocused { clearStackButton }
            IconPill(symbol: "chevron.down", label: "Показати на мапі") { open(.peek) }
        }
        .padding(.bottom, Space.md)
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
    }

    /// Вихід із фокуса на піні. Знімає й підсвітку піна: доки вибір лишався, мапа показувала
    /// обрану подію, а список під нею — уже всі, і це читалось як збій.
    private var clearStackButton: some View {
        IconPill(symbol: "xmark", label: "Показати всі події") {
            stackIDs = []
            model.app.dismissEvent()
        }
    }

    private var sheetList: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(categories, id: \.0) { entry in
                        CategoryTile(category: entry.0, selected: listCategory == entry.0) {
                            listCategory = listCategory == entry.0 ? AppStateKt.ALL_CATEGORIES : entry.0
                        }
                    }
                }
            }.railContentPadding()
            if shownEvents.isEmpty {
                if model.state?.loading == true {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.section)
                } else {
                    quietCard.padding(Space.page)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.lg) {
                        ForEach(Array(shownEvents.enumerated()), id: \.element.id) { position, event in
                            EventCard(
                                event: event, saved: savedIDs.contains(event.id),
                                waitlisted: model.waitlistedIDs.contains(event.id),
                                onSave: { model.app.toggleSaved(id: event.id) }
                            ) { model.app.selectEvent(id: event.id); details = true }
                            // Список просить наступні картки сам. Доки цим займалась лише
                            // карусель, список закінчувався на завантаженому: лічильник казав
                            // «442», а рядків було двадцять чотири, і більше не ставало.
                            .onAppear { loadMore(reaching: position) }
                        }
                        if shownEvents.count < listEntries.count {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.lg)
                        }
                    }
                    .padding(.horizontal, Space.page).padding(.top, Space.md).padding(.bottom, Space.section)
                }
            }
        }
    }

    private var quietCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Тут поки тихо").font(PoruchFont.title3).foregroundStyle(Palette.ink)
            Text("Змініть область мапи, дату або категорію — і події знайдуться.")
                .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /**
     Лічильник рахує те, що в списку, а не те, що прийшло з сервера.

     Число з індексу, а не з завантажених карток: решту список дотягує сам. Доки тут стояло
     `totalFound`, під фільтром у шторці з'являлась пара «Знайдено подій: 1» і порожній список,
     а з обраним піном — кількість усього міста над подіями одного майданчика.
     */
    private var countLabel: String {
        if model.state?.loading == true { return "Шукаємо події…" }
        if stackFocused { return "Тут подій: \(listEntries.count)" }
        let whole = category == AppStateKt.ALL_CATEGORIES && listCategory == AppStateKt.ALL_CATEGORIES
        return "Знайдено подій: \(whole ? Int(model.state?.totalFound ?? 0) : listEntries.count)"
    }

    /// Що саме показує екран: пін, рамку, поставлену рукою, чи ціле місто.
    private var areaLabel: String {
        if stackFocused { return "Усе, що стоїть на обраному піні" }
        return model.state?.customArea == true
            ? "В області, яку ви обрали на мапі"
            : "Знайдіть, куди піти у місті \(model.state?.cityName ?? "Київ")"
    }

    /// Перевести шторку в положення: кнопкою, тапом чи слідом за вибором піна.
    private func open(_ target: SheetDetent) {
        if reduceMotion {
            sheetDrag = 0
            detent = target
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                sheetDrag = 0
                detent = target
            }
        }
    }

    /**
     Куди відпустити шторку: до положення, найближчого до того місця, де її відпустили.

     Інерція лише схиляє вибір, а не вирішує його — звідси четвертина передбаченого вибігу. Доки
     різкий рух означав крок на ціле положення, шторка з половини завжди йшла в крайнє: система
     передбачає кидок щедро, а на звичайному відпусканні пальця швидкість ніколи не нульова.
     */
    private func settle(translation: CGFloat, predicted: CGFloat) {
        let released = height(of: detent) - translation
        let target = released - (predicted - translation) * coastShare
        let nearest = [SheetDetent.peek, .half, .full]
            .min { abs(height(of: $0) - target) < abs(height(of: $1) - target) } ?? .peek
        // Нове положення і скидання пройденого — в одному русі: нарізно вони дають стрибок, бо
        // спершу шторка миттю повертається до висоти старого положення й уже звідти їде до нового.
        open(nearest)
    }

    /// Наступне вікно карток, коли список підходить до краю завантаженого.
    private func loadMore(reaching position: Int) {
        guard shownEvents.count < listEntries.count else { return }
        guard position >= shownEvents.count - cardPrefetchAhead else { return }
        loadHead(shownEvents.count + cardPage)
    }

    /// Картки початку того списку, який зараз показують.
    private func loadHead(_ count: Int) {
        let ids = listEntries.prefix(count).map(\.id)
        guard !ids.isEmpty else { return }
        model.app.loadCards(ids: ids)
    }
}

struct FiltersView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    /**
     Вибір накопичується у шторці й летить на сервер один раз, по «Готово».

     Досі кожен тап по чипу був повним пошуком. Обрати категорію й дату — це два запити по
     чотириста рядків, і жодного проміжного результату ніхто не бачить: їх закриває сама шторка.
     А поки вона відкрита, мапа під нею перемальовується двічі.
     */
    @State private var date: String?
    @State private var category: String?
    @State private var available: Bool?

    private var pickedDate: String { date ?? model.state?.dateFilter ?? DateFilter.shared.ANY }
    private var pickedCategory: String { category ?? model.state?.category ?? AppStateKt.ALL_CATEGORIES }
    private var pickedAvailable: Bool { available ?? model.state?.onlyAvailable ?? false }

    private func apply() {
        if pickedDate != model.state?.dateFilter { model.app.setDateFilter(filter: pickedDate) }
        if pickedCategory != model.state?.category { model.app.setCategory(category: pickedCategory) }
        if pickedAvailable != model.state?.onlyAvailable { model.app.setOnlyAvailable(available: pickedAvailable) }
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    section("Коли") {
                        HStack(spacing: Space.sm) {
                            ForEach(dateFilterKeys, id: \.self) { key in
                                Chip(label: dateLabel(key), selected: pickedDate == key) {
                                    date = pickedDate == key ? DateFilter.shared.ANY : key
                                }
                            }
                        }
                    }
                    section("Категорії") {
                        FlexibleChips(
                            items: [(AppStateKt.ALL_CATEGORIES, "Усі", nil)] + categories.map { ($0.0, $0.1, $0.0) },
                            isSelected: { pickedCategory == $0 }
                        ) { category = pickedCategory == $0 ? AppStateKt.ALL_CATEGORIES : $0 }
                    }
                    Toggle(isOn: Binding(get: { pickedAvailable }, set: { available = $0 })) {
                        Text("Лише події, до яких можна приєднатись").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                    }.tint(Palette.brand)
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.lg)
            }
            actions
        }
        .background(Palette.canvas)
    }

    /// The sheet's own title is a title, not an overline: at 11 pt it was smaller than the section
    /// labels underneath it, which inverted the hierarchy of the whole sheet.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Фільтри").font(PoruchFont.title2).foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            Button("Скинути") {
                date = DateFilter.shared.ANY
                category = AppStateKt.ALL_CATEGORIES
                available = false
            }
            .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.lg)
    }

    /// Pinned, not scrolled: at the medium detent the button sat below the fold and the sheet
    /// looked as though it had no way out.
    private var actions: some View {
        PrimaryButton(title: "Готово") { apply() }
            .frame(maxWidth: .infinity)
            .padding(Space.page)
            .background(Palette.surface.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
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

/// Wrapping chip group; SwiftUI has no flow layout on the deployment target, so rows are measured manually.
struct FlexibleChips: View {
    /// Each item is (key, label, category key for the leading dot — nil for a plain chip).
    let items: [(String, String, String?)]
    let isSelected: (String) -> Bool
    let action: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { index in
                HStack(spacing: Space.sm) {
                    ForEach(items[index..<min(index + 2, items.count)], id: \.0) { item in
                        Chip(label: item.1, dot: item.2, selected: isSelected(item.0)) { action(item.0) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct CitySearchView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var query = ""

    /**
     Доки нічого не набрано, пропонуємо те, де події справді є.

     Геокодер на порожній запит мовчить, а на перші літери віддає область, район, вокзал і
     аеропорт — тобто місця, де людина побачить порожню мапу й вирішить, що подій немає взагалі.
     */
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
                    Section("Міста з подіями") {
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
                    ForEach(model.state?.cities ?? [], id: \.name) { city in
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
            .searchable(text: $query, prompt: "Місто у світі")
            // Автофокуса тут немає свідомо: `searchFocused` зʼявився в iOS 18, а мінімум проєкту —
            // 17. Для пʼяти міст, де є події, він і не потрібен — вони в списку одразу, без
            // жодного символу.
            .onSettled(query, after: .milliseconds(220)) { model.app.searchCity(query: $0) }
            .navigationTitle("Знайти місто")
            .toolbar { Button("Готово") { dismiss() } }
        }
    }
}

/// Яку частку передбаченого вибігу враховувати, обираючи положення шторки.
private let coastShare: CGFloat = 0.25
/// За скільки карток до кінця завантаженого просити наступні.
private let cardPrefetchAhead = 8
/// Скільки карток додає одне довантаження.
private let cardPage = 24
