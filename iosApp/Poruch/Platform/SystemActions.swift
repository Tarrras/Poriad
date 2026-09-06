import EventKit
import EventKitUI
import SwiftUI
import Shared

/// Hand-offs to apps the reader already trusts, kept out of the views that trigger them.
enum SystemActions {
    /// Sharing hands the event to any app the reader already uses; no in-app invitations to maintain.
    static func shareText(for event: Event) -> String {
        "\(event.title) · \(eventDate(event)) · \(event.city), \(event.address)"
    }

    /// Routing belongs to the maps app the reader already trusts, not to a half-built one of ours.
    @MainActor static func openInMaps(_ event: Event) {
        let query = event.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?ll=\(event.latitude),\(event.longitude)&q=\(query)") else { return }
        UIApplication.shared.open(url)
    }

    /// The system calendar owns reminders we cannot: a copy there outlives our local notifications.
    static func requestCalendarAccess(_ completion: @escaping (EKEventStore?) -> Void) {
        let store = EKEventStore()
        store.requestWriteOnlyAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted ? store : nil) }
        }
    }
}

/// EventKit's own editor keeps the calendar choice, alerts and confirmation in Apple's hands.
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

/// An event with an unparseable end still needs one in the calendar; an hour is the safe guess.
private let defaultDuration: TimeInterval = 3600
