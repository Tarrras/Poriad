import SwiftUI
import MapLibre
import Shared
import CoreLocation

struct MapRegion { var south: Double; var west: Double; var north: Double; var east: Double }

private let eventSourceID = "poruch-events"
private let pointSourceID = "poruch-point"
private let clusterHaloID = "poruch-cluster-halo"
private let clusterLayerID = "poruch-cluster"
private let clusterCountID = "poruch-cluster-count"
private let pinCountID = "poruch-pin-count"
/// Максимум подій зі стосу для каруселі.
private let clusterLeafLimit: UInt = 60
/// Радіус кластера в pt, той самий, що на Android. Більший перетворював місто на кілька чорних бульбашок.
private let clusterRadius = 40
private let pinLayerID = "poruch-pin"
private let pointLayerID = "poruch-point-pin"
private let chosenIconName = "poruch-chosen"
/// Керування зумом з екрана: на виборі точки масштаб має бути й кнопкою, не лише щипком.
@MainActor final class MapController: ObservableObject {
    fileprivate weak var map: MLNMapView?

    func zoomIn() { zoom(by: 1) }
    func zoomOut() { zoom(by: -1) }

    private func zoom(by delta: Double) {
        guard let map else { return }
        // Обмежуємо межами мапи, щоб кнопка лишалась живою.
        let target = min(map.maximumZoomLevel, max(map.minimumZoomLevel, map.zoomLevel + delta))
        map.setZoomLevel(target, animated: true)
    }
}

/// Масштаби, спільні для мапи й редактора.
enum MapZoom {
    /// Видно ціле місто.
    static let city: Double = 12
    /// Видно будинок.
    static let street: Double = 15
}

private let cityZoom = MapZoom.city
private let focusZoom = MapZoom.street

private func iconName(_ category: String, selected: Bool) -> String {
    "poruch-pin-\(category)" + (selected ? "-on" : "")
}

/// Значок піна, один на категорію, кешується стилем: кільце на диску в спокої, інверсія у фокусі.
private func pinImage(glyph: PoruchGlyph, hue: UIColor, surface: UIColor, selected: Bool) -> UIImage {
    let disc: CGFloat = selected ? 46 : 38
    let pointer: CGFloat = 9
    let pad: CGFloat = 6
    let size = CGSize(width: disc + pad * 2, height: disc + pointer + pad * 2)
    return UIGraphicsImageRenderer(size: size).image { context in
        let canvas = context.cgContext
        let cx = size.width / 2
        let cy = pad + disc / 2
        let radius = disc / 2
        canvas.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: UIColor.black.withAlphaComponent(0.25).cgColor)
        canvas.setFillColor((selected ? hue : surface).cgColor)
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: cx - pointer * 0.6, y: cy + radius - 1))
        tail.addLine(to: CGPoint(x: cx, y: cy + radius + pointer))
        tail.addLine(to: CGPoint(x: cx + pointer * 0.6, y: cy + radius - 1))
        tail.close()
        canvas.addPath(tail.cgPath)
        canvas.fillPath()
        canvas.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: disc, height: disc))
        canvas.setShadow(offset: .zero, blur: 0, color: nil)
        canvas.setStrokeColor((selected ? surface : hue).cgColor)
        canvas.setLineWidth(2.5)
        canvas.strokeEllipse(in: CGRect(x: cx - radius + 1.25, y: cy - radius + 1.25, width: disc - 2.5, height: disc - 2.5))
        // Гліф з тієї ж геометрії, що й решта застосунку: SF Symbol дав би інший набір іконок на мапі.
        let box: CGFloat = selected ? 22 : 18
        let scale = box / PoruchIconMetrics.grid
        canvas.saveGState()
        canvas.translateBy(x: cx - box / 2, y: cy - box / 2)
        let ink = (selected ? surface : hue).cgColor
        if let stroke = glyph.stroke {
            var path = Path()
            stroke(&path, scale)
            canvas.addPath(path.cgPath)
            canvas.setStrokeColor(ink)
            canvas.setLineWidth(PoruchIconMetrics.stroke * scale)
            canvas.setLineCap(.round)
            canvas.setLineJoin(.round)
            canvas.strokePath()
        }
        canvas.setFillColor(ink)
        // Без even-odd внутрішні контури заливаються і гліф стає диском.
        if let punch = glyph.punch {
            var path = Path()
            punch(&path, scale)
            canvas.addPath(path.cgPath)
            canvas.fillPath(using: .evenOdd)
        }
        if let fill = glyph.fill {
            var path = Path()
            fill(&path, scale)
            canvas.addPath(path.cgPath)
            canvas.fillPath()
        }
        canvas.restoreGState()
    }
}

/// Стиль мапи з токенів палітри під тему.
private func mapStyleJSON(_ scheme: ColorScheme) -> String {
    func endpoint(_ key: String, _ fallback: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return value.isEmpty ? fallback : value
    }
    return MapStyleKt.poruchMapStyle(
        tokens: mapTokens(scheme),
        tilesUrl: endpoint("MAP_TILES_URL", MapEndpoints.shared.TILES),
        glyphsUrl: endpoint("MAP_GLYPHS_URL", MapEndpoints.shared.GLYPHS)
    )
}

/// Нерухома мініатюра місця (деталі події): одна картинка від `MLNMapSnapshotter` замість живого
/// `MLNMapView` з GL-контекстом і тайлами в памʼяті, поки людина читає опис. Пін малюємо поверх.
struct EventMapSnapshot: View {
    let latitude: Double
    let longitude: Double
    let category: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    /// Знімальник живе до кінця знімка: звільнений, він його скасовує.
    @State private var snapshotter: MLNMapSnapshotter?

    var body: some View {
        let pin = pinImage(
            glyph: categoryGlyph(category), hue: categoryUIColor(category), surface: UIColor(Palette.surface), selected: true
        )
        GeometryReader { geometry in
            ZStack {
                Palette.canvasTint
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                // Вістря піна — у центрі, там, де точка події. 6 — відступ під тінь у `pinImage`.
                Image(uiImage: pin).offset(y: -(pin.size.height / 2 - 6))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: "\(latitude),\(longitude),\(scheme),\(Int(geometry.size.width))x\(Int(geometry.size.height))") {
                await render(geometry.size)
            }
        }
    }

    private func render(_ size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }
        // Знімку потрібен URL стилю, а стиль у нас рядок: кладемо його у тимчасовий файл теми.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("poruch-style-\(scheme == .dark ? "dark" : "light").json")
        guard (try? mapStyleJSON(scheme).write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        let camera = MLNMapCamera()
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let options = MLNMapSnapshotOptions(styleURL: file, camera: camera, size: size)
        options.zoomLevel = MapZoom.street
        options.scale = displayScale
        // Як на живій мапі: без логотипу рендерера, атрибуція даних лишається.
        options.showsLogo = false
        let snapshotter = MLNMapSnapshotter(options: options)
        self.snapshotter = snapshotter
        let rendered: UIImage? = await withCheckedContinuation { continuation in
            snapshotter.start { snapshot, _ in continuation.resume(returning: snapshot?.image) }
        }
        if let rendered, !Task.isCancelled { image = rendered }
    }
}

/// Мапа подій. Кластеризацію робить MapLibre всередині стилю, тож панорамування не перебудовує анотації.
struct EventMap: UIViewRepresentable {
    /// Індекс, а не картки: мапі досить координат і категорії.
    let events: [EventIndexEntry]
    let latitude: Double
    let longitude: Double
    var selectedID: String? = nil
    /// Змінюється лише зі складом подій: дешевша заміна порівнянню списків, див. `Coordinator.updateFeatures`.
    var eventsRevision: Int = 0
    /// Локальний фільтр екрана: ревізія з `AppModel` про нього не знає, і піни лишались старими.
    var filterKey: String = ""
    var retryToken: Int = 0
    var centerToken: Int = 0
    /// Зум, коли центр змінився ззовні.
    var centerZoom: Double = MapZoom.city
    /// Поставлена крапка. Мапа лише малює її; ставлять довгим натиском, як на Android.
    var chosenPoint: (latitude: Double, longitude: Double)?
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var interactive: Bool = true
    var loadFailed: (Bool) -> Void = { _ in }
    var selected: (Event) -> Void
    /// Тап у місце з кількома подіями: усі id, бо пін — це заклад.
    var selectedStack: ([String]) -> Void = { _ in }
    var moved: (MapRegion) -> Void
    /// Центр камери, а не середина видимих меж: у Меркаторі це різні числа.
    var centerChanged: (Double, Double) -> Void = { _, _ in }
    /// Керування зумом кнопками.
    var controller: MapController?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleJSON: styleJSON(context.environment.colorScheme))
        context.coordinator.centerKey = "\(latitude),\(longitude),\(centerToken)"
        context.coordinator.scheme = context.environment.colorScheme
        map.delegate = context.coordinator
        map.setCenter(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), zoomLevel: centerZoom, animated: false)
        map.allowsRotating = false
        map.allowsTilting = false
        map.allowsScrolling = interactive
        map.allowsZooming = interactive
        // Логотип рендерера прибираємо, атрибуцію даних лишаємо у тихому кольорі палітри.
        map.logoView.isHidden = true
        map.attributionButtonPosition = .bottomLeft
        map.attributionButton.tintColor = UIColor(Palette.inkTertiary)
        map.attributionButton.alpha = 0.7
        map.compassViewPosition = .topRight
        if interactive {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            map.addGestureRecognizer(tap)
        }
        // Локальний стиль MapLibre розбирає ще до призначення делегата, і didFinishLoading не
        // лунає. Тому шари ставимо самі, щойно стиль є; делегат — для випадку, коли ще вантажиться.
        context.coordinator.installStyleIfReady(map)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        // Політ через місто — саме той рух, який «reduce motion» просить пропустити.
        let animated = !context.environment.accessibilityReduceMotion
        map.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        map.attributionButtonMargins = CGPoint(x: 12, y: 12)
        map.compassViewMargins = CGPoint(x: 12, y: 12)

        if context.coordinator.scheme != context.environment.colorScheme {
            context.coordinator.scheme = context.environment.colorScheme
            context.coordinator.styleReplaced()
            map.styleJSON = styleJSON(context.environment.colorScheme)
        }
        if context.coordinator.retryToken != retryToken {
            context.coordinator.retryToken = retryToken
            // Стиль локальний і не міг не розібратись; перевстановлення змушує перепитати тайли.
            context.coordinator.styleReplaced()
            map.styleJSON = styleJSON(context.environment.colorScheme)
        }
        controller?.map = map
        context.coordinator.installStyleIfReady(map)
        let centerKey = "\(latitude),\(longitude),\(centerToken)"
        if context.coordinator.centerKey != centerKey {
            context.coordinator.centerKey = centerKey
            map.setCenter(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), zoomLevel: centerZoom, animated: animated)
        }
        context.coordinator.updateFeatures(map)
        context.coordinator.updateChosen(map)
        // Вибір, якого ще нема серед подій (індекс у дорозі), не вважаємо наведеним: шукаємо знову,
        // щойно зміниться склад. Інакше мапа, відкрита з деталей до приходу індексу, лишалась на місті.
        let focusKey = "\(selectedID ?? "")#\(eventsRevision)#\(filterKey)"
        if context.coordinator.focusedID != selectedID, context.coordinator.focusKey != focusKey {
            context.coordinator.focusKey = focusKey
            if let id = selectedID, let event = events.first(where: { $0.id == id }) {
                context.coordinator.focusedID = id
                map.setCenter(
                    CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude),
                    zoomLevel: max(map.zoomLevel, focusZoom), animated: animated
                )
            } else {
                context.coordinator.focusedID = nil
            }
        }
    }

    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) {
        coordinator.parent.controller?.map = nil
        map.delegate = nil
    }

    private func styleJSON(_ scheme: ColorScheme) -> String { mapStyleJSON(scheme) }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: EventMap
        var centerKey = ""
        var featureKey = ""
        var chosenKey = ""
        var focusedID: String?
        /// Вибір і склад, для яких уже шукали подію, щоб не ходити по індексу на кожен кадр.
        var focusKey = ""
        var retryToken = 0
        var scheme: ColorScheme = .light
        private var styleReady = false

        init(_ parent: EventMap) { self.parent = parent }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            install(style, on: mapView)
        }

        /// Стиль уже розібрано без делегата: ставимо шари самі, один раз.
        func installStyleIfReady(_ map: MLNMapView) {
            guard !styleReady, let style = map.style else { return }
            install(style, on: map)
        }

        /// Новий стиль стирає джерела й шари: ставимо знову.
        func styleReplaced() { styleReady = false }

        private func install(_ style: MLNStyle, on mapView: MLNMapView) {
            // Повторний addSource з тим самим id — виняток; лише оновлюємо події.
            guard style.source(withIdentifier: eventSourceID) == nil else {
                styleReady = true
                featureKey = ""
                updateFeatures(mapView)
                return
            }
            registerImages(style)
            // Пін — це місце, тож point_count рахував би місця; кількість подій збирає власна властивість.
            let sumEvents = [
                NSExpression(format: "sum:({$featureAccumulated, events})"),
                NSExpression(forKeyPath: "count")
            ]
            let events = MLNShapeSource(identifier: eventSourceID, shape: nil, options: [
                .clustered: true, .clusterRadius: clusterRadius, .maximumZoomLevelForClustering: 15,
                .clusterProperties: ["events": sumEvents]
            ])
            let point = MLNShapeSource(identifier: pointSourceID, shape: nil, options: nil)
            style.addSource(events)
            style.addSource(point)

            let halo = MLNCircleStyleLayer(identifier: clusterHaloID, source: events)
            halo.circleColor = NSExpression(forConstantValue: UIColor(Palette.brand))
            halo.circleOpacity = NSExpression(forConstantValue: scheme == .dark ? 0.28 : 0.16)
            halo.circleRadius = NSExpression(
                format: "mgl_interpolate:withCurveType:parameters:stops:(CAST(events, 'NSNumber'), 'linear', nil, %@)",
                [2: 26, 60: 42]
            )
            halo.predicate = NSPredicate(format: "cluster == YES")
            style.addLayer(halo)

            let core = MLNCircleStyleLayer(identifier: clusterLayerID, source: events)
            core.circleColor = NSExpression(forConstantValue: UIColor(Palette.brand))
            core.circleStrokeWidth = NSExpression(forConstantValue: 3)
            core.circleStrokeColor = NSExpression(forConstantValue: UIColor(Palette.surface))
            core.circleRadius = NSExpression(
                format: "mgl_interpolate:withCurveType:parameters:stops:(CAST(events, 'NSNumber'), 'linear', nil, %@)",
                [2: 18, 60: 30]
            )
            core.predicate = NSPredicate(format: "cluster == YES")
            style.addLayer(core)

            let count = MLNSymbolStyleLayer(identifier: clusterCountID, source: events)
            count.text = NSExpression(format: "CAST(events, 'NSString')")
            count.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            count.textFontSize = NSExpression(forConstantValue: 13)
            count.textColor = NSExpression(forConstantValue: UIColor(Palette.onBrand))
            count.textAllowsOverlap = NSExpression(forConstantValue: true)
            count.textIgnoresPlacement = NSExpression(forConstantValue: true)
            count.predicate = NSPredicate(format: "cluster == YES")
            style.addLayer(count)

            let pins = MLNSymbolStyleLayer(identifier: pinLayerID, source: events)
            pins.iconImageName = NSExpression(forKeyPath: "icon")
            pins.iconAnchor = NSExpression(forConstantValue: "bottom")
            pins.iconAllowsOverlap = NSExpression(forConstantValue: true)
            pins.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            pins.symbolSortKey = NSExpression(forKeyPath: "sort")
            pins.predicate = NSPredicate(format: "cluster != YES")
            style.addLayer(pins)

            // Підпис з кількістю подій біля піна: значок лишається впізнаваним.
            let perPin = MLNSymbolStyleLayer(identifier: pinCountID, source: events)
            perPin.text = NSExpression(format: "CAST(count, 'NSString')")
            perPin.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            perPin.textFontSize = NSExpression(forConstantValue: 11)
            perPin.textColor = NSExpression(forConstantValue: UIColor(Palette.onBrand))
            perPin.textHaloColor = NSExpression(forConstantValue: UIColor(Palette.brand))
            perPin.textHaloWidth = NSExpression(forConstantValue: 9)
            perPin.textTranslation = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 12, dy: -22)))
            perPin.textAllowsOverlap = NSExpression(forConstantValue: true)
            perPin.textIgnoresPlacement = NSExpression(forConstantValue: true)
            perPin.predicate = NSPredicate(format: "cluster != YES AND count > 1")
            style.addLayer(perPin)

            let chosen = MLNSymbolStyleLayer(identifier: pointLayerID, source: point)
            chosen.iconImageName = NSExpression(forConstantValue: chosenIconName)
            chosen.iconAnchor = NSExpression(forConstantValue: "bottom")
            chosen.iconAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(chosen)

            styleReady = true
            featureKey = ""
            chosenKey = ""
            updateFeatures(mapView)
            updateChosen(mapView)
            DispatchQueue.main.async { self.parent.loadFailed(false) }
        }

        private func registerImages(_ style: MLNStyle) {
            let surface = UIColor(Palette.surface)
            for category in categories {
                let hue = categoryUIColor(category.0)
                style.setImage(
                    pinImage(glyph: categoryGlyph(category.0), hue: hue, surface: surface, selected: false),
                    forName: iconName(category.0, selected: false)
                )
                style.setImage(
                    pinImage(glyph: categoryGlyph(category.0), hue: hue, surface: surface, selected: true),
                    forName: iconName(category.0, selected: true)
                )
            }
            style.setImage(
                pinImage(glyph: PoruchIcons.pin, hue: UIColor(Palette.brand), surface: surface, selected: true),
                forName: chosenIconName
            )
        }

        /// Крапка зустрічі — окреме джерело: не подія, в кластери не рахується.
        func updateChosen(_ map: MLNMapView) {
            guard styleReady, let source = map.style?.source(withIdentifier: pointSourceID) as? MLNShapeSource else { return }
            let key = parent.chosenPoint.map { "\($0.latitude),\($0.longitude)" } ?? ""
            guard key != chosenKey else { return }
            chosenKey = key
            guard let point = parent.chosenPoint else { return source.shape = nil }
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            source.shape = feature
        }

        func updateFeatures(_ map: MLNMapView) {
            guard styleReady, let source = map.style?.source(withIdentifier: eventSourceID) as? MLNShapeSource else { return }
            // Ключ має бути дешевим: updateUIView кличуть на кожне перемальовування.
            let key = "\(parent.eventsRevision)#\(parent.filterKey)#" + (parent.selectedID ?? "")
            guard key != featureKey else { return }
            featureKey = key
            // Групування спільне з Android і залежить лише від складу подій (eventsRevision).
            let pins = groupedPins(key: key, events: parent.events)
            let features: [MLNPointFeature] = pins.map { pin in
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
                let isSelected = pin.contains(eventId: parent.selectedID)
                feature.attributes = [
                    // `id` — подія: решта екрана оперує подіями, не місцями.
                    "id": isSelected ? (parent.selectedID ?? pin.representative.id) : pin.representative.id,
                    "ids": pin.eventIds.joined(separator: ","),
                    "icon": iconName(pin.representative.category, selected: isSelected),
                    "count": pin.count,
                    "sort": isSelected ? 1 : 0
                ]
                return feature
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }

        /// Піни поточного складу подій, перераховуються лише при його зміні.
        private var pinCache: (key: String, pins: [VenuePin])?

        private func groupedPins(key: String, events: [EventIndexEntry]) -> [VenuePin] {
            if let cached = pinCache, cached.key == key { return cached.pins }
            let pins = MapPins.shared.group(events: events)
            pinCache = (key, pins)
            return pins
        }

        /// Тап шукає спершу пін, потім кластер; кластер розкривається до зуму, що його розділяє.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MLNMapView, map.style != nil else { return }
            let location = gesture.location(in: map)
            let target = CGRect(x: location.x - 26, y: location.y - 26, width: 52, height: 52)
            let pins = map.visibleFeatures(in: target, styleLayerIdentifiers: [pinLayerID])
            if !pins.isEmpty {
                let ids = pins.flatMap { eventIDs(of: $0) }
                if !ids.isEmpty { parent.selectedStack(ids); return }
            }
            let clusters = map.visibleFeatures(in: target, styleLayerIdentifiers: [clusterLayerID])
            guard let cluster = clusters.first as? MLNPointFeatureCluster,
                  let source = map.style?.source(withIdentifier: eventSourceID) as? MLNShapeSource else { return }
            let zoom = source.zoomLevel(forExpanding: cluster)

            // Наближаємо лише якщо це справді змінює зум, інакше показуємо вміст.
            if zoom <= map.zoomLevel + 0.1 || zoom > 19 {
                let ids = source.leaves(of: cluster, offset: 0, limit: clusterLeafLimit)
                    .flatMap { eventIDs(of: $0) }
                if !ids.isEmpty { parent.selectedStack(ids); return }
            }
            map.setCenter(cluster.coordinate, zoomLevel: min(19, zoom > 0 ? zoom : map.zoomLevel + 2), animated: true)
        }

        /// Події місця, як їх записав `updateFeatures`.
        private func eventIDs(of feature: MLNFeature) -> [String] {
            if let joined = feature.attribute(forKey: "ids") as? String, !joined.isEmpty {
                return joined.components(separatedBy: ",").filter { !$0.isEmpty }
            }
            return (feature.attribute(forKey: "id") as? String).map { [$0] } ?? []
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            styleReady = false
            DispatchQueue.main.async { self.parent.loadFailed(true) }
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let center = mapView.centerCoordinate
            parent.centerChanged(center.latitude, center.longitude)
            let gestures: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom]
            guard !reason.intersection(gestures).isEmpty else { return }
            let bounds = mapView.visibleCoordinateBounds
            parent.moved(MapRegion(south: bounds.sw.latitude, west: bounds.sw.longitude, north: bounds.ne.latitude, east: bounds.ne.longitude))
        }
    }
}

/// Місто, де людина зараз. Як на Android: спершу останнє відоме положення (миттєво), свіже лише
/// уточнює; назва — від системного геокодера, а не «Поруч зі мною». Свіжий вимір того самого міста
/// не перемикає місто вдруге: інакше видача перечитувалась би без причини.
@MainActor final class LocationFinder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    @Published var city: CityResult?
    @Published var message: String?
    /// Назва, вже віддана в межах поточного запиту.
    private var announced: String?
    /// Положення просили. Система кличе `locationManagerDidChangeAuthorization` і при створенні
    /// менеджера: без прапорця кожен екземпляр сам визначав місто, і воно перемикалось двічі.
    private var wanted = false
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer }
    func request() {
        announced = nil
        wanted = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: message = "Геолокація недоступна. Ви можете знайти місто вручну."
        default: locate()
        }
    }
    private func locate() {
        // Свіжий вимір буває за десять секунд; останній відомий майже завжди вже є.
        if let known = manager.location { resolve(known) }
        manager.requestLocation()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wanted, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        locate()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last { resolve(last) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Останній відомий уже спрацював: мовчимо.
        if announced == nil { message = "Не вдалося визначити місце. Скористайтеся пошуком міста." }
    }

    private func resolve(_ location: CLLocation) {
        geocoder.cancelGeocode()
        // У місті з подіями назва — його, а не громади від геокодера.
        let point = location.coordinate
        if let place = HomeLocation.companion.around(latitude: point.latitude, longitude: point.longitude) {
            guard place.city != announced else { return }
            announced = place.city
            city = CityResult(name: place.city, latitude: place.latitude, longitude: place.longitude)
            return
        }
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "uk_UA")) { [weak self] places, error in
            Task { @MainActor in
                guard let self else { return }
                // Скасоване наступним виміром — не відповідь.
                if (error as? CLError)?.code == .geocodeCanceled { return }
                let locality = places?.first?.locality.flatMap { $0.isEmpty ? nil : $0 }
                // Геокодер змовчав, а місто вже є: заглушка його не перебиває.
                if locality == nil && self.announced != nil { return }
                let name = locality ?? "Поруч зі мною"
                guard name != self.announced else { return }
                self.announced = name
                self.city = CityResult(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
        }
    }
}
