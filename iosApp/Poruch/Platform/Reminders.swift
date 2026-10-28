import Foundation
import UserNotifications
import Shared

/// Дозвіл на сповіщення. Питає система, відповідь іде в спільний стор через перемикач у профілі.
enum NotificationPermission {
    /// З `provisional` система не питає: дозвіл тихий, сповіщення лягають у Центр сповіщень без банера й звуку,
    /// з кнопками «Залишити» / «Вимкнути». Запит без нього з тихого дозволу показує звичайне системне вікно.
    static func request(provisional: Bool = false, _ completion: @escaping (Bool) -> Void) {
        let options: UNAuthorizationOptions = provisional ? [.alert, .sound, .provisional] : [.alert, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, _ in
            DispatchQueue.main.async {
                // План міг прийти, поки висіло системне вікно, а без дозволу iOS запити відкидає.
                if granted { LocalReminderScheduler.shared.reschedule() }
                completion(granted)
            }
        }
    }

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Чи є ще що спитати: система не питала або дала лише тихий дозвіл першого запуску.
    static func askable() async -> Bool {
        let status = await status()
        return status == .notDetermined || status == .provisional
    }

    /// Перший запуск: тихий дозвіл без вікна, щоб дайджест вихідних дійшов і до того, хто відкрив раз і забув.
    /// Справжнє питання лишається на другому запуску (`DigestPrompt`) чи першій підписці.
    static func provisional() {
        Task {
            guard await status() == .notDetermined else { return }
            request(provisional: true) { granted in
                if granted { PushDelegate.registerIfAllowed() }
            }
        }
    }
}

/// Питання про сповіщення після першої підписки: «Стежити» без них марне, пуші про нове не дійдуть. Система питає
/// один раз і лише поки не питала, тож далі це нічого не робить. Дозвіл дає й реєстрацію в APNs.
enum FollowPrompt {
    static func ask() {
        Task {
            guard await NotificationPermission.askable() else { return }
            NotificationPermission.request { granted in
                if granted { PushDelegate.registerIfAllowed() }
            }
        }
    }
}

/// Приєднання чи своя нова подія — природний момент спитати про сповіщення: без них нагадування за годину
/// не прийде. Хто вимкнув нагадування в профілі, того не питаємо; система й так питає лише раз.
enum ReminderPrompt {
    static func offer(_ app: PoruchApp) {
        guard (app.state.value as? AppState)?.remindersEnabled == true else { return }
        Task {
            guard await NotificationPermission.askable() else { return }
            NotificationPermission.request { granted in
                if granted { PushDelegate.registerIfAllowed() }
            }
        }
    }
}

/// Системне вікно відгуку після оцінки події 4–5 чи закладки й приєднання в другий день (`AppState.reviewMoment`),
/// раз на версію.
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

/// Мʼяке питання про дайджест: на другому запуску, раз, лише поки система ще не питала вікном
/// (тихий дозвіл першого запуску — не відповідь). Перший запуск належить онбордингу й геолокації.
enum DigestPrompt {
    private static var counted = false

    static func due(digestEnabled: Bool) async -> Bool {
        guard !counted else { return false }
        counted = true
        let defaults = UserDefaults.standard
        let launches = defaults.integer(forKey: "poruch.launches") + 1
        defaults.set(launches, forKey: "poruch.launches")
        guard launches >= 2, digestEnabled, !defaults.bool(forKey: "poruch.digestAsked"),
              await NotificationPermission.askable() else { return false }
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
    /// Префікс драбини дайджестів: `poruch.digest.1`…`4`; голий `poruch.digest` — єдиний дайджест старих версій.
    private let digestID = "poruch.digest"
    /// Останній план: `shared` шле лише зміни, а без дозволу iOS запити відкидає.
    private var lastReminders: [EventReminder] = []
    private var lastDigests: [WeekendDigest] = []
    private var planned = false

    /// Сповіщення дозволили, вікном чи в Налаштуваннях: ставимо останній план знову, інакше він чекав би зміни.
    func reschedule() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { [self] in
                guard planned else { return }
                replace(reminders: lastReminders)
                replaceDigests(digests: lastDigests)
            }
        }
    }

    func replace(reminders: [EventReminder]) {
        lastReminders = reminders
        planned = true
        center.getPendingNotificationRequests { [center, prefix] requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
            for reminder in reminders {
                let interval = Double(reminder.fireAtEpochMillis) / 1000 - Date().timeIntervalSince1970
                guard interval > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                if let at = reminder.tomorrowAt {
                    content.body = Copy.reminder_saved_body(at, reminder.address)
                    content.userInfo = ["eventId": reminder.eventId, "saved": true]
                } else {
                    content.body = Copy.reminder_body("\(reminder.address)")
                    content.userInfo = ["eventId": reminder.eventId]
                }
                content.sound = .default
                center.add(UNNotificationRequest(
                    identifier: prefix + reminder.eventId, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                ))
            }
        }
    }

    /// Драбина дайджестів: запит на тиждень під `poruch.digest.<id>` (вихідні 1–4, будні 11–14), новий план знімає весь старий.
    func replaceDigests(digests: [WeekendDigest]) {
        lastDigests = digests
        center.getPendingNotificationRequests { [center, digestID] requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(digestID) })
            for digest in digests {
                let interval = Double(digest.fireAtEpochMillis) / 1000 - Date().timeIntervalSince1970
                guard interval > 0 else { continue }
                let content = UNMutableNotificationContent()
                let city = digest.city ?? Copy.brand_name, count = Copy.digest_count(Int(digest.count))
                content.title = if digest.kind == .weekdays { Copy.digest_weekdays_title(city, count) } else {
                    switch digest.week {
                    case 2: Copy.digest_title_2(city, count)
                    case 3: Copy.digest_title_3(city, count)
                    case 4: Copy.digest_title_4(city, count)
                    default: Copy.digest_title(city, count)
                    }
                }
                content.body = digestBody(digest)
                content.sound = .default
                // Під ключем `week` — id дайджесту: старі запити (1–4) так і читаються як вихідні.
                content.userInfo = ["week": Int(digest.id)]
                center.add(UNNotificationRequest(
                    identifier: "\(digestID).\(digest.id)", content: content,
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
            center.add(UNNotificationRequest(identifier: requestPrefix + alert.eventId, content: content, trigger: nil))
        }
    }

    /// Нові повідомлення в чаті: одне сповіщення на подію, з іменем і початком останнього.
    func notifyMessages(alerts: [ChatAlert]) {
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.eventTitle
            let author = alert.authorName.isEmpty ? Copy.chat_member : alert.authorName
            content.body = "\(author): \(alert.preview)"
            content.subtitle = chatCount(Int(alert.count))
            content.sound = .default
            content.userInfo = ["eventId": alert.eventId]
            center.add(UNNotificationRequest(identifier: chatPrefix + alert.eventId, content: content, trigger: nil))
        }
    }

    private func chatCount(_ count: Int) -> String { Copy.chat_new_messages(count) }

    private func requestBody(_ count: Int) -> String { Copy.request_notification_body(count) }

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
    /// «Хтось шукає компанію» (`companion`) несе найближчий збір як `eventId`: звичайний шлях на подію.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let info = request.content.userInfo
        if request.identifier.hasPrefix(digestID) {
            let week = info["week"] as? Int ?? 1
            DispatchQueue.main.async {
                PushDelegate.digestOpened(week: Int32(week))
                PushDelegate.open(eventId: nil, chat: false)
            }
        } else if info["kind"] as? String == "winback" {
            // Пуш повернення з сервера — як дайджест: без події, на головну (docs/guest-channel.md).
            let step = info["step"] as? Int ?? 1
            DispatchQueue.main.async {
                PushDelegate.winbackOpened(step: Int32(step))
                PushDelegate.open(eventId: nil, chat: false)
            }
        } else {
            // Пуш з сервера каже, що він, у `kind`; локальне сповіщення — префікс ідентифікатора. Дайджест — свій `digest_open`.
            let id = request.identifier
            let reason = info["kind"] as? String
                ?? (id.hasPrefix(chatPrefix) ? "chat" : id.hasPrefix(requestPrefix) ? "request"
                    : id.hasPrefix(prefix) ? (info["saved"] != nil ? "saved" : "reminder") : nil)
            let eventId = info["eventId"] as? String, placeId = info["placeId"] as? String, artistId = info["artistId"] as? String
            let chat = info["kind"] as? String == "chat" || id.hasPrefix(chatPrefix)
            DispatchQueue.main.async {
                // Метрика лише разом із переходом: пуш без цілі не «повернув людину».
                guard eventId != nil || placeId != nil || artistId != nil else { return }
                if let reason { PushDelegate.opened(reason: reason) }
                PushDelegate.open(eventId: eventId, chat: chat, placeId: placeId, artistId: artistId)
            }
        }
        completionHandler()
    }
}

/// Тіло дайджесту: вирізнена подія з причинами («Стендап — один вечір у місті · і ще 6»), інакше назви й «та ще N».
private func digestBody(_ digest: WeekendDigest) -> String {
    let more = Int(digest.count) - (digest.lead == nil ? digest.titles.count : 1)
    guard let lead = digest.lead else {
        let titles = digest.titles.joined(separator: ", ")
        return more > 0 ? Copy.digest_more(titles, "\(more)") : titles
    }
    let reasons = digest.reasons.compactMap { reason -> String? in
        if reason == .followed { return digest.followName.map { Copy.digest_reason_followed($0) } }
        if reason == .company { return Copy.digest_reason_company }
        if reason == .oneNight { return Copy.digest_reason_one_night }
        if reason == .forYou { return Copy.digest_reason_for_you }
        return nil
    }.joined(separator: " · ")
    if reasons.isEmpty { return more > 0 ? Copy.digest_more(lead, "\(more)") : lead }
    return more > 0 ? Copy.digest_lead_more(lead, reasons, "\(more)") : Copy.digest_lead(lead, reasons)
}
