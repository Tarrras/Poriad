import EventKit
import PhotosUI
import SwiftUI
import Shared

/// The side effects of the detail screen — a photo upload, a calendar hand-off — and the progress
/// they show. They outlive a single render, so they live here rather than in the view's body.
@MainActor final class EventActionsModel: ObservableObject {
    @Published var photoError: String?
    @Published var calendarStore: EKEventStore?
    @Published var calendarDenied = false

    private let app: PoruchApp

    init(app: PoruchApp) { self.app = app }

    func perform(_ action: DetailAction, on event: Event, signedIn: Bool) -> Bool {
        guard signedIn else { return false }
        switch action {
        case .join: app.joinEvent(id: event.id)
        case .leave: app.leaveEvent(id: event.id)
        case .joinWaitlist: app.joinWaitlist(id: event.id)
        case .leaveWaitlist: app.leaveWaitlist(id: event.id)
        default: break
        }
        return true
    }

    func toggleSaved(_ event: Event, signedIn: Bool) -> Bool {
        guard signedIn else { return false }
        app.toggleSaved(id: event.id)
        return true
    }

    func cancel(_ event: Event) { app.cancelEvent(id: event.id) }

    func requestCalendar() {
        SystemActions.requestCalendarAccess { [weak self] store in
            guard let self else { return }
            if let store { calendarStore = store } else { calendarDenied = true }
        }
    }

    /// Re-encodes whatever the picker returned as JPEG: the store accepts three types, and one is
    /// simpler to guarantee than to detect.
    func upload(_ item: PhotosPickerItem?, to event: Event) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: jpegQuality)
            else { photoError = "Не вдалося прочитати фото"; return }
            guard jpeg.count <= Int(ImageRules.shared.MAX_BYTES) else { photoError = "Оберіть фото до 5 МБ"; return }
            let bytes = KotlinByteArray(size: Int32(jpeg.count))
            for (index, byte) in jpeg.enumerated() { bytes.set(index: Int32(index), value: Int8(bitPattern: byte)) }
            photoError = nil
            app.uploadEventImage(eventId: event.id, bytes: bytes, contentType: "image/jpeg")
        } catch {
            photoError = "Не вдалося завантажити фото"
        }
    }
}

/// Enough for a cover photo without pushing the upload past the store's ceiling.
private let jpegQuality: CGFloat = 0.8
