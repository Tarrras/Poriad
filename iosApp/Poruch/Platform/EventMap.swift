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
private let pinLayerID = "poruch-pin"
private let pointLayerID = "poruch-point-pin"
private let chosenIconName = "poruch-chosen"
private let cityZoom: Double = 12
private let focusZoom: Double = 15

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
    let events: [Event]
    let latitude: Double
    let longitude: Double
    var selectedID: String? = nil
    var retryToken: Int = 0
    var centerToken: Int = 0
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var interactive: Bool = true
    var loadFailed: (Bool) -> Void = { _ in }
    var selected: (Event) -> Void
    var moved: (MapRegion) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL(context.environment.colorScheme))
        context.coordinator.centerKey = "\(latitude),\(longitude),\(centerToken)"
        context.coordinator.scheme = context.environment.colorScheme
        map.delegate = context.coordinator
        map.setCenter(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), zoomLevel: cityZoom, animated: false)
        map.allowsRotating = false
        map.allowsTilting = false
        map.allowsScrolling = interactive
        map.allowsZooming = interactive
        // Keep provider attribution reachable above the carousel.
        map.attributionButtonPosition = .bottomLeft
        map.logoViewPosition = .bottomLeft
        map.compassViewPosition = .topRight
        if interactive {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            map.addGestureRecognizer(tap)
        }
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        // A flight across the city is exactly the movement «reduce motion» asks us to skip.
        let animated = !context.environment.accessibilityReduceMotion
        map.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        map.attributionButtonMargins = CGPoint(x: 12, y: 12)
        map.logoViewMargins = CGPoint(x: 44, y: 12)
        map.compassViewMargins = CGPoint(x: 12, y: 12)

        if context.coordinator.scheme != context.environment.colorScheme {
            context.coordinator.scheme = context.environment.colorScheme
            map.styleURL = styleURL(context.environment.colorScheme)
        }
        if context.coordinator.retryToken != retryToken {
            context.coordinator.retryToken = retryToken
            map.reloadStyle(nil)
        }
        let centerKey = "\(latitude),\(longitude),\(centerToken)"
        if context.coordinator.centerKey != centerKey {
            context.coordinator.centerKey = centerKey
            map.setCenter(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), zoomLevel: cityZoom, animated: animated)
        }
        context.coordinator.updateFeatures(map)
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

    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) { map.delegate = nil }

    private func styleURL(_ scheme: ColorScheme) -> URL? {
        let key = scheme == .dark ? "MAP_STYLE_DARK_URL" : "MAP_STYLE_URL"
        let fallback = scheme == .dark
            ? "https://tiles.openfreemap.org/styles/dark"
            : "https://tiles.openfreemap.org/styles/positron"
        return URL(string: Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: EventMap
        var centerKey = ""
        var featureKey = ""
        var focusedID: String?
        var retryToken = 0
        var scheme: ColorScheme = .light
        private var styleReady = false

        init(_ parent: EventMap) { self.parent = parent }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            registerImages(style)
            let events = MLNShapeSource(identifier: eventSourceID, shape: nil, options: [
                .clustered: true, .clusterRadius: 56, .maximumZoomLevelForClustering: 15
            ])
            let point = MLNShapeSource(identifier: pointSourceID, shape: nil, options: nil)
            style.addSource(events)
            style.addSource(point)

            let halo = MLNCircleStyleLayer(identifier: clusterHaloID, source: events)
            halo.circleColor = NSExpression(forConstantValue: UIColor(Palette.brand))
            halo.circleOpacity = NSExpression(forConstantValue: scheme == .dark ? 0.28 : 0.16)
            halo.circleRadius = NSExpression(
                format: "mgl_interpolate:withCurveType:parameters:stops:(CAST(point_count, 'NSNumber'), 'linear', nil, %@)",
                [2: 26, 60: 42]
            )
            halo.predicate = NSPredicate(format: "cluster == YES")
            style.addLayer(halo)

            let core = MLNCircleStyleLayer(identifier: clusterLayerID, source: events)
            core.circleColor = NSExpression(forConstantValue: UIColor(Palette.brand))
            core.circleStrokeWidth = NSExpression(forConstantValue: 3)
            core.circleStrokeColor = NSExpression(forConstantValue: UIColor(Palette.surface))
            core.circleRadius = NSExpression(
                format: "mgl_interpolate:withCurveType:parameters:stops:(CAST(point_count, 'NSNumber'), 'linear', nil, %@)",
                [2: 18, 60: 30]
            )
            core.predicate = NSPredicate(format: "cluster == YES")
            style.addLayer(core)

            let count = MLNSymbolStyleLayer(identifier: clusterCountID, source: events)
            count.text = NSExpression(format: "CAST(point_count, 'NSString')")
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

            let chosen = MLNSymbolStyleLayer(identifier: pointLayerID, source: point)
            chosen.iconImageName = NSExpression(forConstantValue: chosenIconName)
            chosen.iconAnchor = NSExpression(forConstantValue: "bottom")
            chosen.iconAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(chosen)

            styleReady = true
            featureKey = ""
            updateFeatures(mapView)
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

        func updateFeatures(_ map: MLNMapView) {
            guard styleReady, let source = map.style?.source(withIdentifier: eventSourceID) as? MLNShapeSource else { return }
            let key = parent.events.map { "\($0.id):\($0.category)" }.joined(separator: "|") + "#" + (parent.selectedID ?? "")
            guard key != featureKey else { return }
            featureKey = key
            let features: [MLNPointFeature] = parent.events.map { event in
                let feature = MLNPointFeature()
                feature.coordinate = CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude)
                feature.attributes = [
                    "id": event.id,
                    "icon": iconName(event.category, selected: event.id == parent.selectedID),
                    "sort": event.id == parent.selectedID ? 1 : 0
                ]
                return feature
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }

        /// A tap hits a pin first, then a cluster; clusters expand to the zoom that splits them apart.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MLNMapView, map.style != nil else { return }
            let location = gesture.location(in: map)
            let target = CGRect(x: location.x - 26, y: location.y - 26, width: 52, height: 52)
            let pins = map.visibleFeatures(in: target, styleLayerIdentifiers: [pinLayerID])
            if let id = pins.first?.attribute(forKey: "id") as? String,
               let event = parent.events.first(where: { $0.id == id }) {
                parent.selected(event)
                return
            }
            let clusters = map.visibleFeatures(in: target, styleLayerIdentifiers: [clusterLayerID])
            guard let cluster = clusters.first as? MLNPointFeatureCluster,
                  let source = map.style?.source(withIdentifier: eventSourceID) as? MLNShapeSource else { return }
            let zoom = source.zoomLevel(forExpanding: cluster)
            map.setCenter(cluster.coordinate, zoomLevel: min(19, zoom > 0 ? zoom : map.zoomLevel + 2), animated: true)
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            styleReady = false
            DispatchQueue.main.async { self.parent.loadFailed(true) }
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
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
