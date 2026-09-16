import Foundation
import UserNotifications
import Shared

/// Дозвіл на сповіщення. Питає система, відповідь іде в спільний стор через перемикач у профілі.
enum NotificationPermission {
    static func request(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}

/// Локальні сповіщення за планом зі спільного шару: що і коли вирішено там, тут лише центр
/// сповіщень. Делегат потрібен, щоб банер показувався й у відкритому застосунку: без нього
/// iOS у фореграунді мовчить.
final class LocalReminderScheduler: NSObject, ReminderScheduler, RequestNotifier, ChatNotifier, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "poruch.event."

    override init() {
        super.init()
        center.delegate = self
    }

    func replace(reminders: [EventReminder]) {
        center.getPendingNotificationRequests { [center, prefix] requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
            for reminder in reminders {
                let interval = Double(reminder.fireAtEpochMillis) / 1000 - Date().timeIntervalSince1970
                guard interval > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = "Початок за годину · \(reminder.address)"
                content.sound = .default
                content.userInfo = ["eventId": reminder.eventId]
                center.add(UNNotificationRequest(
                    identifier: prefix + reminder.eventId, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                ))
            }
        }
    }

    /// Нові запити на участь: негайно, без тригера. «Нове» вже вирішив спільний шар; тут лише показ.
    func notify(alerts: [RequestAlert]) {
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.eventTitle
            content.body = requestBody(Int(alert.count))
            content.sound = .default
            content.userInfo = ["eventId": alert.eventId]
            // Інший префікс, ніж у нагадувань: запит і нагадування про ту саму подію — два сповіщення.
            center.add(UNNotificationRequest(identifier: "poruch.request." + alert.eventId, content: content, trigger: nil))
        }
    }

    /// Нові повідомлення в чаті: одне сповіщення на подію, з іменем і початком останнього.
    func notifyMessages(alerts: [ChatAlert]) {
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.eventTitle
            let author = alert.authorName.isEmpty ? "Учасник" : alert.authorName
            content.body = "\(author): \(alert.preview)"
            content.subtitle = chatCount(Int(alert.count))
            content.sound = .default
            content.userInfo = ["eventId": alert.eventId]
            center.add(UNNotificationRequest(identifier: "poruch.chat." + alert.eventId, content: content, trigger: nil))
        }
    }

    private func chatCount(_ count: Int) -> String {
        let last = count % 10, tens = count % 100
        return last == 1 && tens != 11 ? "\(count) нове повідомлення" : "\(count) нових повідомлень"
    }

    private func requestBody(_ count: Int) -> String {
        let last = count % 10, tens = count % 100
        let noun = last == 1 && tens != 11 ? "новий запит"
            : (2...4).contains(last) && !(12...14).contains(tens) ? "нові запити" : "нових запитів"
        return "\(count) \(noun) на участь. Відкрийте подію, щоб відповісти."
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Пуш у відкритому застосунку: стан перечитуємо, а банер показуємо, як і локальні.
        let info = notification.request.content.userInfo
        if let kind = info["kind"] as? String {
            PushDelegate.app?.pushReceived(kind: kind, key: info["key"] as? String ?? "")
        }
        completionHandler([.banner, .list, .sound])
    }

    /// Тап по сповіщенню, локальному чи пушу: відкрити подію, про яку воно.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let eventId = response.notification.request.content.userInfo["eventId"] as? String {
            DispatchQueue.main.async { PushDelegate.openEvent?(eventId) }
        }
        completionHandler()
    }
}
