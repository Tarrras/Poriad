import Foundation
import Shared

/// The form as the reader typed it, plus the local persistence that keeps a draft across launches.
struct EditorForm: Codable, Equatable {
    var title = ""
    var description = ""
    var category = defaultCategory
    var city = ""
    var address = ""
    var latitude = 0.0
    var longitude = 0.0
    var starts = Date().addingTimeInterval(defaultLead)
    var ends = Date().addingTimeInterval(defaultLead + defaultDuration)
    var timeZone = TimeZone.current.identifier
    var capacity = defaultCapacity

    /// Null until every field is present; the publish button follows this, so it cannot lie.
    func draft(imageUrl: String?) -> EventDraft? {
        guard !title.trimmed.isEmpty, !city.trimmed.isEmpty, !address.trimmed.isEmpty, ends > starts else { return nil }
        let formatter = ISO8601DateFormatter()
        return EventDraft(
            title: title.trimmed, description: description.trimmed, category: category,
            city: city.trimmed, address: address.trimmed, latitude: latitude, longitude: longitude,
            startsAt: formatter.string(from: starts), endsAt: formatter.string(from: ends),
            timeZone: timeZone, capacity: Int32(capacity), imageUrl: imageUrl
        )
    }
}

enum EditorStep: Int, CaseIterable, Identifiable {
    case about, place, schedule
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .about: "Про подію"
        case .place: "Місце"
        case .schedule: "Час і місця"
        }
    }
    var isLast: Bool { self == .schedule }
}

/// Owns the editor's form, its step, and the draft it saves. The view renders and forwards edits;
/// nothing here needs SwiftUI to be tested.
@MainActor final class EventEditorModel: ObservableObject {
    @Published var form = EditorForm()
    @Published var step = EditorStep.about
    @Published private(set) var submitted = false

    private let app: PoruchApp
    private let event: Event?
    private var storageKey: String { "poruch.draft.\(event?.id ?? "new")" }

    init(app: PoruchApp, event: Event?, home: AppState?) {
        self.app = app
        self.event = event
        restore(home: home)
    }

    var editing: Bool { event != nil }

    /// Each step guards only its own fields, so «Далі» never blocks on a later one.
    var canAdvance: Bool {
        switch step {
        case .about: !form.title.trimmed.isEmpty
        case .place: !form.city.trimmed.isEmpty && !form.address.trimmed.isEmpty
        case .schedule: form.draft(imageUrl: event?.imageUrl) != nil
        }
    }

    func advance() { if let next = EditorStep(rawValue: step.rawValue + 1) { step = next } }
    func retreat() { if let previous = EditorStep(rawValue: step.rawValue - 1) { step = previous } }

    func submit() {
        guard let draft = form.draft(imageUrl: event?.imageUrl) else { return }
        persist()
        app.clearCompletedEvent()
        submitted = true
        if let event { app.updateEvent(id: event.id, draft: draft) } else { app.createEvent(draft: draft) }
    }

    /// Called when the store confirms the write; the saved draft has served its purpose.
    func finish() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        submitted = false
        app.clearCompletedEvent()
    }

    func persist() {
        guard !submitted, let data = try? JSONEncoder().encode(form) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func restore(home: AppState?) {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(EditorForm.self, from: data) {
            form = saved
            return
        }
        if let event {
            form = EditorForm(
                title: event.title, description: event.description_, category: event.category,
                city: event.city, address: event.address, latitude: event.latitude, longitude: event.longitude,
                starts: parseEventDate(event.startsAt) ?? Date(), ends: parseEventDate(event.endsAt) ?? Date(),
                timeZone: event.timeZone, capacity: Int(event.capacity)
            )
        } else {
            form.city = home?.cityName ?? HomeLocation.companion.Kyiv.city
            form.latitude = home?.cityLatitude ?? HomeLocation.companion.Kyiv.latitude
            form.longitude = home?.cityLongitude ?? HomeLocation.companion.Kyiv.longitude
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A new event defaults to «tomorrow-ish», which is what most drafts turn out to be.
private let defaultLead: TimeInterval = 3600
private let defaultDuration: TimeInterval = 3600
private let defaultCategory = "social"
private let defaultCapacity = 20
