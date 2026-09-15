import EventKit
import EventKitUI
import SwiftUI
import Shared

/// Передача в системні застосунки, поза view, що їх викликають.
enum SystemActions {
    /// Поділитись через будь-який застосунок; своїх запрошень не тримаємо.
    static func shareText(for event: Event) -> String {
        "\(event.title) · \(eventDate(event)) · \(event.city), \(event.address)"
    }

    /// Маршрут будує системна мапа.
    @MainActor static func openInMaps(_ event: Event) {
        let query = event.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?ll=\(event.latitude),\(event.longitude)&q=\(query)") else { return }
        UIApplication.shared.open(url)
    }

    /// Копія в системному календарі переживає наші локальні сповіщення.
    static func requestCalendarAccess(_ completion: @escaping (EKEventStore?) -> Void) {
        let store = EKEventStore()
        store.requestWriteOnlyAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted ? store : nil) }
        }
    }
}

/// Редактор EventKit: вибір календаря, нагадування й підтвердження лишаються в Apple.
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
        entry.calendar = store.defaultCalendarForNewEvents
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
