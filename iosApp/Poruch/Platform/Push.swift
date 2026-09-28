import UIKit
import UserNotifications
import Shared

/// Пуші через APNs. Токен просимо, щойно система дозволила сповіщення; hex-рядок іде в стор і
/// реєструється під поточним акаунтом. Симулятор на Apple silicon отримує справжні токени.
final class PushDelegate: NSObject, UIApplicationDelegate {
    /// Стор підключається після старту: делегат створюється раніше за `AppModel`, а токен від
    /// APNs може прийти ще раніше. Тому токен тримаємо і віддаємо, щойно стор зʼявився.
    static var app: PoruchApp? {
        didSet {
            if let token = pendingToken { app?.pushTokenChanged(token: token, platform: PushPlatform.ios) }
            else { registerIfAllowed() }
            if let app, let reason = pendingReason { pendingReason = nil; app.pushOpened(reason: reason) }
        }
    }
    private static var pendingToken: String?
    /// Тап по сповіщенню: подія, яку відкрити, і чи в її чат; без події — заклад, чий стос показати на мапі
    /// (пуш про кілька нових подій), а без нього — дайджест, лише головна.
    /// Ставить корінь, коли застосунок уже на екрані.
    static var openEvent: ((String?, Bool, String?) -> Void)? {
        didSet {
            if let openEvent, let pending = pendingOpen { pendingOpen = nil; openEvent(pending.id, pending.chat, pending.placeId) }
        }
    }
    /// Тап при холодному старті приходить раніше, ніж корінь готовий: чекає тут.
    private static var pendingOpen: (id: String?, chat: Bool, placeId: String?)?

    static func open(eventId: String?, chat: Bool, placeId: String? = nil) {
        if let openEvent { openEvent(eventId, chat, placeId) } else { pendingOpen = (eventId, chat, placeId) }
    }

    /// Що це було, для аналітики (`push_open`). Так само чекає на `app`: при холодному старті його ще нема.
    private static var pendingReason: String?

    static func opened(reason: String) {
        if let app { app.pushOpened(reason: reason) } else { pendingReason = reason }
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Делегат центру — до кінця запуску, інакше тап, що запустив застосунок, губиться.
        UNUserNotificationCenter.current().delegate = LocalReminderScheduler.shared
        PushDelegate.registerIfAllowed()
        return true
    }

    /// Реєструємо лише з дозволом: без нього токен є, а сповіщень нема, і сервер даремно шле.
    static func registerIfAllowed() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            NSLog("Poruch/push: notification authorization status %d", settings.authorizationStatus.rawValue)
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async {
                NSLog("Poruch/push: registering for remote notifications")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        // NSLog, а не PoruchLog: цю подію треба бачити в системному журналі й без консолі Xcode.
        NSLog("Poruch/push: apns token received (%d bytes)", deviceToken.count)
        PushDelegate.pendingToken = token
        PushDelegate.app?.pushTokenChanged(token: token, platform: PushPlatform.ios)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("Poruch/push: apns registration failed: %@", error.localizedDescription)
        // Без токена пуші мовчать: у звіт, з доменом і кодом системної помилки, без її тексту.
        let failure = error as NSError
        PoruchLog.shared.report(tag: "push", issue: "apns registration failed \(failure.domain) \(failure.code)", error: nil)
    }
}
