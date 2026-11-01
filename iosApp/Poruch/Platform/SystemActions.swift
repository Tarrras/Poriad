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

    /// «Покликати» (docs/invites.md): те саме, але голосом людини й з посиланням, яке дав спільний шар.
    static func inviteText(for event: Event, link: String) -> String {
        Copy.invite_share_text(event.displayTitle, eventDate(event), "\(event.city), \(event.address)", link)
    }

    /// Файли події для системного меню («Пост для Threads») у теку [folder]: адреса в меню стала б посиланням, а не фото.
    /// Що не завантажилось — без нього. Теку прибирає той, хто показав меню.
    static func download(_ urls: [String], into folder: URL) async -> [URL] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        for raw in urls {
            guard !Task.isCancelled else { break }
            guard let url = URL(string: raw), let (temp, _) = try? await downloads.download(from: url) else { continue }
            let file = folder.appendingPathComponent(url.lastPathComponent)
            if (try? FileManager.default.moveItem(at: temp, to: file)) != nil { files.append(file) } else { try? FileManager.default.removeItem(at: temp) }
        }
        return files
    }

    /// Меню не чекає довше, ніж людина згодна дивитись на неактивну кнопку: файл, що завис, просто пропускаємо.
    private static let downloads: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 45
        return URLSession(configuration: config)
    }()

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
