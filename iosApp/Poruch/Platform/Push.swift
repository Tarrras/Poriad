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
            if let token = pendingToken { app?.pushTokenChanged(token: token, platform: PushPlatform.shared.IOS) }
            else { registerIfAllowed() }
        }
    }
    private static var pendingToken: String?
    /// Тап по сповіщенню: подія, яку відкрити. Ставить корінь.
    static var openEvent: ((String) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
        PushDelegate.app?.pushTokenChanged(token: token, platform: PushPlatform.shared.IOS)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("Poruch/push: apns registration failed: %@", error.localizedDescription)
    }
}
