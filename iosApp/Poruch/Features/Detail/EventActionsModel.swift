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
        switch await pickedJPEG(item, maxPixel: uploadMaxPixel) {
        case .success(let bytes):
            photoError = nil
            app.uploadEventImage(eventId: event.id, bytes: bytes, contentType: "image/jpeg")
        case .failure(let problem):
            photoError = problem.message
        }
    }
}

/// Чому фото з пікера не стало байтами. Текст — для підпису під кнопкою.
struct PhotoProblem: Error {
    let message: String
}

/// Будь-що з пікера → JPEG без метаданих з довшою стороною до `maxPixel`, готовий для `shared`.
/// Декодування й копіювання в Kotlin — поза головним потоком: це сотні мілісекунд.
func pickedJPEG(_ item: PhotosPickerItem, maxPixel: CGFloat) async -> Result<KotlinByteArray, PhotoProblem> {
    do {
        guard let data = try await item.loadTransferable(type: Data.self) else { return .failure(PhotoProblem(message: "Не вдалося прочитати фото")) }
        let jpeg = await Task.detached(priority: .userInitiated) {
            ThumbnailCache.downsample(data, to: maxPixel)?.jpegData(compressionQuality: jpegQuality)
        }.value
        guard let jpeg else { return .failure(PhotoProblem(message: "Не вдалося прочитати фото")) }
        guard jpeg.count <= Int(ImageRules.shared.MAX_BYTES) else { return .failure(PhotoProblem(message: "Оберіть фото до 5 МБ")) }
        // Мосту Data → ByteArray у shared нема: копіюємо побайтово, але у фоні.
        let bytes = await Task.detached(priority: .userInitiated) {
            let bytes = KotlinByteArray(size: Int32(jpeg.count))
            for (index, byte) in jpeg.enumerated() { bytes.set(index: Int32(index), value: Int8(bitPattern: byte)) }
            return bytes
        }.value
        return .success(bytes)
    } catch {
        return .failure(PhotoProblem(message: "Не вдалося завантажити фото"))
    }
}

/// Досить для обкладинки і не виходить за ліміт сховища.
private let jpegQuality: CGFloat = 0.8
/// Найбільша сторона обкладинки в пікселях: з запасом для екрана деталей.
private let uploadMaxPixel: CGFloat = 2048
