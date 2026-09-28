import EventKit
import EventKitUI
import SwiftUI
import Shared

/// Передача в системні застосунки, поза view, що їх викликають.
enum SystemActions {
    /// Поділитись через будь-який застосунок; своїх запрошень не тримаємо.
    /// Посилання в кінці: Telegram і месенджери розгортають з нього прев'ю сторінки події.
    static func shareText(for event: Event) -> String {
        "\(event.title) · \(eventDate(event)) · \(event.city), \(event.address)\n\(EventLinks.shared.url(eventId: event.id))"
    }

    /// Маршрут будує системна мапа.
    @MainActor static func openInMaps(_ event: Event) {
        openInMaps(latitude: event.latitude, longitude: event.longitude, label: event.title)
    }

    @MainActor static func openInMaps(latitude: Double, longitude: Double, label: String) {
        let query = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(query)") else { return }
        UIApplication.shared.open(url)
    }
}

/// Редактор EventKit: вибір календаря, нагадування й підтвердження лишаються в Apple. Копія в
/// системному календарі переживає наші локальні сповіщення.
struct CalendarEditor: UIViewControllerRepresentable {
    let event: Event
    let store: EKEventStore
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        let entry = EKEvent(eventStore: store)
        entry.title = event.title
        entry.notes = event.description_
        entry.location = "\(event.city), \(event.address)"
        entry.timeZone = TimeZone(identifier: event.timeZone)
        let start = parseEventDate(event.startsAt) ?? Date()
        entry.startDate = start
        entry.endDate = parseEventDate(event.endsAt) ?? start.addingTimeInterval(defaultDuration)
        controller.event = entry
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let dismiss: () -> Void
        init(_ dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}

/// Тривалість для календаря, якщо кінець не розібрався.
private let defaultDuration: TimeInterval = 3600
