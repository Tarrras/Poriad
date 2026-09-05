import SwiftUI
import MapLibre
import Shared
import CoreLocation

struct MapRegion { var south: Double; var west: Double; var north: Double; var east: Double }
final class EventPin: MLNPointAnnotation {
    var events: [Event] = []
}
struct EventMap: UIViewRepresentable {
    let events: [Event]
    let latitude: Double
    let longitude: Double
    var selected: (Event) -> Void
    var moved: (MapRegion) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MLNMapView {
        let style = Bundle.main.object(forInfoDictionaryKey: "MAP_STYLE_URL") as? String ?? "https://tiles.openfreemap.org/styles/positron"
        let map = MLNMapView(frame: .zero, styleURL: URL(string: style))
        map.delegate = context.coordinator
        map.setCenter(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), zoomLevel: 11, animated: false)
        return map
    }
    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        let centerKey = "\(latitude),\(longitude)"
        if context.coordinator.centerKey != centerKey {
            context.coordinator.centerKey = centerKey
            map.setCenter(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), zoomLevel: 11, animated: false)
        }
        context.coordinator.updatePins(map)
    }
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: EventMap
        var centerKey = ""
        var pinKey = ""
        init(_ parent: EventMap) { self.parent = parent }
        func updatePins(_ map: MLNMapView) {
            let key = parent.events.map { "\($0.id):\($0.latitude):\($0.longitude):\($0.category):\($0.title)" }.joined() + String(Int(map.zoomLevel * 2))
            guard key != pinKey else { return }; pinKey = key
            if let annotations = map.annotations { map.removeAnnotations(annotations) }
            let grid = max(0.0001, 360 / pow(2, map.zoomLevel) / 7)
            let groups = Dictionary(grouping: parent.events) { "\(Int(floor($0.latitude / grid))),\(Int(floor($0.longitude / grid)))" }
            for group in groups.values {
                let pin = EventPin(); pin.events = group
                pin.coordinate = CLLocationCoordinate2D(latitude: group.map(\.latitude).reduce(0,+) / Double(group.count), longitude: group.map(\.longitude).reduce(0,+) / Double(group.count))
                pin.title = group.count > 1 ? "\(group.count) подій" : group[0].title
                map.addAnnotation(pin)
            }
        }
        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            guard let pin = annotation as? EventPin else { return nil }
            let label = pin.events.count > 1 ? String(pin.events.count) : "•"
            let symbol = categories.first { $0.0 == pin.events.first?.category }?.2 ?? "mappin"
            let identifier = "pin-\(label)-\(symbol)"
            if let image = mapView.dequeueReusableAnnotationImage(withIdentifier: identifier) { return image }
            let image = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 48)).image { ctx in
                UIColor(red: 0.12, green: 0.39, blue: 0.28, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 40, height: 40)).fill()
                if pin.events.count == 1, let symbolImage = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold))?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    symbolImage.draw(in: CGRect(x: 11, y: 10, width: 22, height: 22))
                } else {
                let text = label as NSString
                text.draw(in: CGRect(x: 5, y: 8, width: 34, height: 30), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.white, .paragraphStyle: { let s = NSMutableParagraphStyle(); s.alignment = .center; return s }()])
                }
            }
            return MLNAnnotationImage(image: image, reuseIdentifier: identifier)
        }
        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let pin = annotation as? EventPin else { return }
            if pin.events.count > 1 { mapView.setCenter(pin.coordinate, zoomLevel: mapView.zoomLevel + 2, animated: true) }
            else if let event = pin.events.first { parent.selected(event) }
            mapView.deselectAnnotation(annotation, animated: false)
        }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            updatePins(mapView)
            let b = mapView.visibleCoordinateBounds
            parent.moved(MapRegion(south: b.sw.latitude, west: b.sw.longitude, north: b.ne.latitude, east: b.ne.longitude))
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
