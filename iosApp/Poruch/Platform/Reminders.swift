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

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

/// Питання про сповіщення після першої підписки: «Стежити» без них марне, пуші про нове не дійдуть. Система питає
/// один раз і лише поки не питала, тож далі це нічого не робить. Дозвіл дає й реєстрацію в APNs.
enum FollowPrompt {
    static func ask() {
        Task {
            guard await NotificationPermission.status() == .notDetermined else { return }
            NotificationPermission.request { granted in
                if granted { PushDelegate.registerIfAllowed() }
            }
        }
    }
}

/// Системне вікно відгуку після оцінки події 4–5 (`AppState.reviewMoment`), раз на версію.
/// Чи показати його, вирішує iOS (до трьох разів на рік), і чи людина відповіла, не каже.
enum ReviewPrompt {
    static func due() -> Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "poruch.reviewAskedVersion") != version else { return false }
        defaults.set(version, forKey: "poruch.reviewAskedVersion")
        return true
    }
}

/// Мʼяке питання про дайджест: на другому запуску, раз, лише поки система ще не питала.
/// Перший запуск належить онбордингу й геолокації; системне питання iOS ставить лише раз.
enum DigestPrompt {
    private static var counted = false

    static func due(digestEnabled: Bool) async -> Bool {
        guard !counted else { return false }
        counted = true
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: "poruch.launches") + 1
        defaults.set(launches, forKey: "poruch.launches")
        guard launches >= 2, digestEnabled, !defaults.bool(forKey: "poruch.digestAsked"),
              await NotificationPermission.status() == .notDetermined else { return false }
        defaults.set(true, forKey: "poruch.digestAsked")
        return true
    }
}

/// Локальні сповіщення за планом зі спільного шару: що і коли вирішено там, тут лише центр
/// сповіщень. Делегат потрібен, щоб банер показувався й у відкритому застосунку: без нього
/// iOS у фореграунді мовчить. Один на застосунок: делегатом його ставить `PushDelegate` при запуску.
final class LocalReminderScheduler: NSObject, ReminderScheduler, RequestNotifier, ChatNotifier, UNUserNotificationCenterDelegate {
    static let shared = LocalReminderScheduler()
    private let center = UNUserNotificationCenter.current()
    private let prefix = "poruch.event."
    private let chatPrefix = "poruch.chat."
    private let requestPrefix = "poruch.request."
    private let digestID = "poruch.digest"

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

    /// Дайджест вихідних: один запит під сталим id, новий план його замінює.
    func replaceDigest(digest: WeekendDigest?) {
        center.removePendingNotificationRequests(withIdentifiers: [digestID])
        guard let digest else { return }
        let interval = Double(digest.fireAtEpochMillis) / 1000 - Date().timeIntervalSince1970
        guard interval > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(digest.city ?? "Поруч"): \(eventCount(Int(digest.count))) на вихідних"
        let titles = digest.titles.joined(separator: ", ")
        let more = Int(digest.count) - digest.titles.count
        content.body = more > 0 ? "\(titles) та ще \(more)" : titles
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: digestID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        ))
    }

    private func eventCount(_ count: Int) -> String {
        let last = count % 10, tens = count % 100
        let noun = last == 1 && tens != 11 ? "подія"
            : (2...4).contains(last) && !(12...14).contains(tens) ? "події" : "подій"
        return "\(count) \(noun)"
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
            center.add(UNNotificationRequest(identifier: requestPrefix + alert.eventId, content: content, trigger: nil))
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
            center.add(UNNotificationRequest(identifier: chatPrefix + alert.eventId, content: content, trigger: nil))
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

    /// Тап по сповіщенню, локальному чи пушу: відкрити подію, про яку воно, а про повідомлення — її чат.
    /// Пуш про кілька нових подій закладу веде на мапу, до його стосу, а про артиста — на його екран.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let info = request.content.userInfo
        if request.identifier == digestID {
            DispatchQueue.main.async { PushDelegate.open(eventId: nil, chat: false) }
        } else {
            // Пуш з сервера каже, що він, у `kind`; локальне сповіщення — префікс ідентифікатора. Дайджест — свій `digest_open`.
            let id = request.identifier
            let reason = info["kind"] as? String
                ?? (id.hasPrefix(chatPrefix) ? "chat" : id.hasPrefix(requestPrefix) ? "request" : id.hasPrefix(prefix) ? "reminder" : nil)
            let eventId = info["eventId"] as? String, placeId = info["placeId"] as? String, artistId = info["artistId"] as? String
            let chat = info["kind"] as? String == "chat" || id.hasPrefix(chatPrefix)
            DispatchQueue.main.async {
                if let reason { PushDelegate.opened(reason: reason) }
                if eventId != nil || placeId != nil || artistId != nil { PushDelegate.open(eventId: eventId, chat: chat, placeId: placeId, artistId: artistId) }
            }
        }
        completionHandler()
    }
}
