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
/// Стос у одному закладі буває на кілька десятків подій; більше за це в каруселі не потрібно.
private let clusterLeafLimit: UInt = 60
/**
 Радіус кластера в точках екрана. Той самий, що на Android, — інакше платформи показують різні мапи.

 Був 56, і на міському зумі половина Києва стояла в одній чорній бульбашці. Відколи мапа малює всі
 події області, а не перші 300, це стало помітнішим: кластер відповідає на питання «скільки», хоча
 мапу відкривають питати «що і де».
 */
private let clusterRadius = 40
private let pinLayerID = "poruch-pin"
private let pointLayerID = "poruch-point-pin"
private let chosenIconName = "poruch-chosen"
/**
 Ручка, якою екран може наблизити мапу.

 Щипок пальцями лишається, але він не єдиний спосіб: на екрані вибору точки одна рука тримає
 телефон, а друга — та сама, що потім тисне «Готово». Тому масштаб має бути й кнопкою.
 */
@MainActor final class MapController: ObservableObject {
    fileprivate weak var map: MLNMapView?

    func zoomIn() { zoom(by: 1) }
    func zoomOut() { zoom(by: -1) }

    private func zoom(by delta: Double) {
        guard let map else { return }
        // Межі ті самі, що в мапи: далі неї однаково не поїдеш, а кнопка має лишатись живою.
        let target = min(map.maximumZoomLevel, max(map.minimumZoomLevel, map.zoomLevel + delta))
        map.setZoomLevel(target, animated: true)
    }
}

/// Масштаби, якими користується не лише мапа: редактор теж має сказати, наскільки близько стати.
enum MapZoom {
    /// Оглядовий: видно ціле місто.
    static let city: Double = 12
    /// Вуличний: видно будинок, у якому і є та сама крапка.
    static let street: Double = 15
}

private let cityZoom = MapZoom.city
private let focusZoom = MapZoom.street

private func iconName(_ category: String, selected: Bool) -> String {
    "poruch-pin-\(category)" + (selected ? "-on" : "")
}

/**
 Pin plate drawn once per category and cached by the style: a category ring on a surface disc while
 resting, and the inverse — a filled disc with a surface ring — once the pin is focused.
 */
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
        // The glyph is drawn from the same geometry the rest of the app uses, at the same weight:
        // an SF Symbol here would put a different icon set on the map than on the cards.
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
        // Solid glyphs carry their counters as inner subpaths; without the even-odd rule a
        // palette's wells fill in and it becomes a disc.
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

/**
 Vector-tile clustering keeps dense neighbourhoods usable: MapLibre groups points inside the style,
 so panning stays smooth where per-annotation views forced a rebuild on every camera idle.
 */
struct EventMap: UIViewRepresentable {
    /// Індекс, а не картки: мапі потрібні координати й категорія, і вона не має чекати обкладинок.
    let events: [EventIndexEntry]
    let latitude: Double
    let longitude: Double
    var selectedID: String? = nil
    /// Змінюється лише тоді, коли змінився склад подій. Дешевша заміна порівнянню списків — див.
    /// `Coordinator.updateFeatures`.
    var eventsRevision: Int = 0
    /**
     Фільтр, яким екран звузив [events] у себе.

     Ревізія рахується в [AppModel] на емісію стану й про локальний фільтр екрана не знає: коли
     мапа перемикала категорію, лічильник змінювався, а піни лишались старими — джерело не
     перебудовувалось, бо ключ був той самий.
     */
    var filterKey: String = ""
    var retryToken: Int = 0
    var centerToken: Int = 0
    /// Наскільки близько ставати, коли центр змінився ззовні. Місто за замовчуванням.
    var centerZoom: Double = MapZoom.city
    /**
     Крапка, яку вже поставили. Мапа її лише малює, а не пам'ятає.

     Раніше крапкою тут був центр мапи, і роздивитись околиці означало переставити місце
     зустрічі: найменший зсув переписував щойно обрану адресу на сусідню вулицю. Тепер крапку
     ставлять довгим натиском — як на Android, — і мапу можна крутити скільки завгодно.
     */
    var chosenPoint: (latitude: Double, longitude: Double)?
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var interactive: Bool = true
    var loadFailed: (Bool) -> Void = { _ in }
    var selected: (Event) -> Void
    /// Тап у місце, де подій кілька: віддаємо всі, бо пін представляє заклад, а не подію.
    var selectedStack: ([String]) -> Void = { _ in }
    var moved: (MapRegion) -> Void
    /**
     Куди зараз дивиться мапа. Потрібно там, де крапка — це центр екрана, а не пін під пальцем.

     Читаємо центр камери, а не середину видимих меж: у проєкції Меркатора це різні числа, і
     друге тим більше бреше, чим далі від екватора.
     */
    var centerChanged: (Double, Double) -> Void = { _, _ in }
    /// Ручка масштабу для екрана, який хоче кнопки замість щипка.
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
        // The renderer's wordmark is not this app's brand, so it goes; the credit the data licence
        // does ask for stays, as a mark in the palette's quietest ink rather than a blue ⓘ.
        map.logoView.isHidden = true
        map.attributionButtonPosition = .bottomLeft
        map.attributionButton.tintColor = UIColor(Palette.inkTertiary)
        map.attributionButton.alpha = 0.7
        map.compassViewPosition = .topRight
        if interactive {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            map.addGestureRecognizer(tap)
        }
        // Стиль тут — локальний рядок, а не URL: MapLibre встигає його розібрати ще до того, як
        // `map.delegate` призначено, і тоді `didFinishLoading` не лунає взагалі. Саме через це на
        // iOS мапа малювалася без жодного піна, хоч подій знаходилося 167. Тому джерела й шари
        // ставимо самі, щойно стиль є, а делегат лишається для випадку, коли він ще вантажиться.
        context.coordinator.installStyleIfReady(map)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        // A flight across the city is exactly the movement «reduce motion» asks us to skip.
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
            // The style itself never failed to parse — it is local. Re-setting it makes the map
            // ask the tile server for the geometry again, which is what the retry is for.
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
        if context.coordinator.focusedID != selectedID {
            context.coordinator.focusedID = selectedID
            if let id = selectedID, let event = events.first(where: { $0.id == id }) {
                map.setCenter(
                    CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude),
                    zoomLevel: max(map.zoomLevel, focusZoom), animated: animated
                )
            }
        }
    }

    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) {
        coordinator.parent.controller?.map = nil
        map.delegate = nil
    }

    private func styleJSON(_ scheme: ColorScheme) -> String {
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

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: EventMap
        var centerKey = ""
        var featureKey = ""
        var chosenKey = ""
        var focusedID: String?
        var retryToken = 0
        var scheme: ColorScheme = .light
        private var styleReady = false

        init(_ parent: EventMap) { self.parent = parent }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            install(style, on: mapView)
        }

        /// Стиль уже розібрано, а делегат про це не почув. Ставимо шари самі — рівно один раз.
        func installStyleIfReady(_ map: MLNMapView) {
            guard !styleReady, let style = map.style else { return }
            install(style, on: map)
        }

        /// Новий стиль стирає джерела й шари разом зі старим, тож їх треба буде поставити знову.
        func styleReplaced() { styleReady = false }

        private func install(_ style: MLNStyle, on mapView: MLNMapView) {
            // Повторний addSource з тим самим ідентифікатором — виняток, а не заміна. Джерело
            // вже стоїть — лишається перечитати в нього події, бо вони могли змінитися.
            guard style.source(withIdentifier: eventSourceID) == nil else {
                styleReady = true
                featureKey = ""
                updateFeatures(mapView)
                return
            }
            registerImages(style)
            // Пін тепер представляє місце, тож стандартний point_count рахував би місця.
            // Читачеві потрібна кількість подій — її збирає власна властивість кластера.
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

            // Скільки подій у цьому місці. Значок лишається тим самим — змінюється підпис біля
            // нього, тож пін впізнаваний, а стос перестає прикидатися однією подією.
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

        /// Крапка зустрічі — окреме джерело, бо вона не подія і не рахується в кластерах.
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
            // Ключ мусить бути дешевим: `updateUIView` викликається на кожне перемальовування
            // екрана, а раніше тут на кожен такий виклик будувався рядок з усіх подій — сотні
            // переходів через міст у Kotlin і кілька кілобайт тексту заради одного порівняння.
            let key = "\(parent.eventsRevision)#\(parent.filterKey)#" + (parent.selectedID ?? "")
            guard key != featureKey else { return }
            featureKey = key
            // Групування спільне з Android: інакше платформи показували б різні мапи на тих
            // самих даних. І, як на Android, воно залежить лише від складу подій — тримаємо його
            // за `eventsRevision`, щоб крок каруселі не перекладав наново всі триста подій заради
            // іншого кольору одного піна.
            let pins = groupedPins(key: key, events: parent.events)
            let features: [MLNPointFeature] = pins.map { pin in
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
                let isSelected = pin.contains(eventId: parent.selectedID)
                feature.attributes = [
                    // `id` лишається подією — решта екрана оперує подіями, не місцями.
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

        /// Піни поточного складу подій. Перераховуються, лише коли склад справді змінився.
        private var pinCache: (key: String, pins: [VenuePin])?

        private func groupedPins(key: String, events: [EventIndexEntry]) -> [VenuePin] {
            if let cached = pinCache, cached.key == key { return cached.pins }
            let pins = MapPins.shared.group(events: events)
            pinCache = (key, pins)
            return pins
        }

        /// A tap hits a pin first, then a cluster; clusters expand to the zoom that splits them apart.
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

            // Розкриття допоможе лише тоді, коли воно справді змінює зум. Стос однакових точок не
            // розділиться ніколи, тож там показуємо вміст замість безкінечного наближення.
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

@MainActor final class LocationFinder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var message: String?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer }
    func request() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { message = "Геолокація недоступна. Ви можете знайти місто вручну." }
        else { manager.requestLocation() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { coordinate = locations.last?.coordinate }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { message = "Не вдалося визначити місце. Скористайтеся пошуком міста." }
}
