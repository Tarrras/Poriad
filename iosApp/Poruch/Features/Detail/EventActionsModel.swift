import EventKit
import PhotosUI
import SwiftUI
import UserNotifications
import Shared

/// Побічні дії екрана деталей (фото, календар) та їхній прогрес. Переживають рендер, тому не в тілі view.
@MainActor final class EventActionsModel: ObservableObject {
    @Published var photoError: String?
    @Published var calendarStore: EKEventStore?

    private let app: PoruchApp

    init(app: PoruchApp) { self.app = app }

    func perform(_ action: DetailAction, on event: Event, signedIn: Bool) -> Bool {
        // Квитки на афішу купують у джерела: акаунт не потрібен, тому до перевірки входу.
        if action == .tickets {
            if let url = sourceURL(event) { UIApplication.shared.open(url) }
            return true
        }
        guard signedIn else { return false }
        switch action {
        case .join, .request: app.joinEvent(id: event.id); offerReminders()
        case .leave: app.leaveEvent(id: event.id)
        case .joinWaitlist: app.joinWaitlist(id: event.id); offerReminders()
        case .leaveWaitlist: app.leaveWaitlist(id: event.id)
        default: break
        }
        return true
    }

    /// Перше приєднання — природний момент увімкнути нагадування. Той, хто вимкнув їх у профілі,
    /// дозвіл системи вже дав, і система вдруге не питає: його вибір лишається.
    private func offerReminders() {
        guard (app.state.value as? AppState)?.remindersEnabled == false else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [app] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            NotificationPermission.request { granted in
                guard granted else { return }
                app.setRemindersEnabled(enabled: true)
                PushDelegate.registerIfAllowed()
            }
        }
    }

    func toggleSaved(_ event: Event, signedIn: Bool) -> Bool {
        guard signedIn else { return false }
        app.toggleSaved(id: event.id)
        return true
    }

    func cancel(_ event: Event) { app.cancelEvent(id: event.id) }

    /// З iOS 17 редактор EventKit працює поза процесом застосунку і доступу до календаря не потребує:
    /// людина сама обирає календар і зберігає. Тож дозволу не питаємо.
    func openCalendar() { calendarStore = EKEventStore() }

    /// Перекодовує будь-що з пікера в JPEG: один тип простіше гарантувати, ніж визначати. Фото з
    /// камери 24–48 Мп у JPEG завжди більше за ліміт, тому спершу зменшуємо до обкладинки.
    /// Декодування й копіювання в Kotlin — поза головним потоком: це сотні мілісекунд.
    func upload(_ item: PhotosPickerItem?, to event: Event) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { photoError = "Не вдалося прочитати фото"; return }
            let jpeg = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.downsample(data, to: uploadMaxPixel)?.jpegData(compressionQuality: jpegQuality)
            }.value
            guard let jpeg else { photoError = "Не вдалося прочитати фото"; return }
            guard jpeg.count <= Int(ImageRules.shared.MAX_BYTES) else { photoError = "Оберіть фото до 5 МБ"; return }
            // Мосту Data → ByteArray у shared нема: копіюємо побайтово, але у фоні.
            let bytes = await Task.detached(priority: .userInitiated) {
                let bytes = KotlinByteArray(size: Int32(jpeg.count))
                for (index, byte) in jpeg.enumerated() { bytes.set(index: Int32(index), value: Int8(bitPattern: byte)) }
                return bytes
            }.value
            photoError = nil
            app.uploadEventImage(eventId: event.id, bytes: bytes, contentType: "image/jpeg")
        } catch {
            photoError = "Не вдалося завантажити фото"
        }
    }
}

/// Досить для обкладинки і не виходить за ліміт сховища.
private let jpegQuality: CGFloat = 0.8
/// Найбільша сторона обкладинки в пікселях: з запасом для екрана деталей.
private let uploadMaxPixel: CGFloat = 2048
