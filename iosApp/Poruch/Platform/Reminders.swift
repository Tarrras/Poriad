import Foundation
import UserNotifications
import Shared

/// Локальні нагадування за згодою, звіряються з актуальним членством із сервера.
final class EventReminders {
    private let center = UNUserNotificationCenter.current()
    private var signature = ""
    func request(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in completion(granted) }
    }
    func reconcile(_ state: AppState) {
        let enabled = UserDefaults.standard.bool(forKey: "poruch.reminders")
        let events = state.myEvents.filter { $0.gathering?.joined == true && $0.isPublished }
        let next = "\(enabled)-\(state.userId ?? "guest")-" + events.map { "\($0.id)-\($0.startsAt)" }.sorted().joined()
        guard next != signature else { return }; signature = next
        center.getPendingNotificationRequests { [center] requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("poruch.event.") })
            guard enabled, state.userId != nil else { return }
            for event in events.prefix(60) {
                guard let start = parseEventDate(event.startsAt) else { continue }
                let interval = start.timeIntervalSinceNow - 3600
                guard interval > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = event.title; content.body = "Початок за годину · \(event.address)"; content.sound = .default
                center.add(UNNotificationRequest(identifier: "poruch.event.\(event.id)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
            }
        }
    }
}
