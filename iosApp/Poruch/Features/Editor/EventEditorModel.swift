import Foundation
import Shared

/// Форма, як її набрали, плюс локальне збереження чернетки між запусками.
struct EditorForm: Codable, Equatable {
    var title = ""
    var description = ""
    var category = defaultCategory
    var city = ""
    var address = ""
    var latitude = 0.0
    var longitude = 0.0
    /// Чи крапка вже обрана. На iOS координати є завжди (центр міста), тому окремий прапорець.
    /// Optional, щоб старі чернетки читались далі.
    var placed: Bool?

    /// Крапка зустрічі, якщо обрана. Мапа малює її, а не свій центр.
    var point: (latitude: Double, longitude: Double)? {
        placed == true ? (latitude, longitude) : nil
    }
    var starts = Date().addingTimeInterval(defaultLead)
    var ends = Date().addingTimeInterval(defaultLead + defaultDuration)
    var timeZone = TimeZone.current.identifier
    var capacity = defaultCapacity
    /// Вікові межі. `maxAge` nil — без верхньої межі.
    var minAge = Int(SafetyRules.shared.MIN_SIGNUP_AGE)
    var maxAge: Int?
    /// Приєднання — запит організатору, а не відкриті двері.
    var approvalRequired = false

    /// Nil, поки не заповнене кожне поле. Кнопка публікації дивиться сюди.
    func draft(imageUrl: String?) -> EventDraft? {
        guard !title.trimmed.isEmpty, !city.trimmed.isEmpty, !address.trimmed.isEmpty, ends > starts else { return nil }
        guard SafetyRules.shared.isAgeLimit(minAge: Int32(minAge), maxAge: maxAge.map { KotlinInt(int: Int32($0)) }) else { return nil }
        let formatter = ISO8601DateFormatter()
        return EventDraft(
            title: title.trimmed, description: description.trimmed, category: category,
            city: city.trimmed, address: address.trimmed, latitude: latitude, longitude: longitude,
            startsAt: formatter.string(from: starts), endsAt: formatter.string(from: ends),
            timeZone: timeZone, capacity: Int32(capacity), imageUrl: imageUrl,
            minAge: Int32(minAge), maxAge: maxAge.map { KotlinInt(int: Int32($0)) },
            approvalRequired: approvalRequired
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

/// Форма редактора, крок і чернетка. View лише малює й передає правки; тестується без SwiftUI.
@MainActor final class EventEditorModel: ObservableObject {
    @Published var form = EditorForm()
    @Published var step = EditorStep.about
    @Published private(set) var submitted = false
    /// Пояс визначено за місцем події, а не взято з пристрою.
    @Published private(set) var timeZoneFromPlace = false
    /// Підказки адрес: людина набирає вулицю й будинок, крапку ставить застосунок.
    @Published private(set) var addressSuggestions: [PlaceResult] = []
    /// Крапку поставлено з підказки: координати вже не здогад.
    @Published private(set) var pointChosen = false
    /// Лічильник «крапку поставили не мапою»: сигнал мапі стати на неї. Координати міняються й від панорами.
    @Published private(set) var placedAt = 0

    /// Адреса під ціллю на екрані вибору. Порожня, поки відповідь у дорозі.
    @Published private(set) var aimAddress = ""

    private let app: PoruchApp
    private let event: Event?
    private var storageKey: String { "poruch.draft.\(event?.id ?? "new")" }
    /// Один кодувальник на редактор: створення дорожче за кодування.
    private let encoder = JSONEncoder()
    private var pendingSave: Task<Void, Never>?
    /// Запит адреси для пересунутої крапки. Наступний рух скасовує попередній.
    private var pendingAddress: Task<Void, Never>?
    /// Те саме для цілі на екрані вибору. Окремо, бо там крапку ще приміряють.
    private var pendingAim: Task<Void, Never>?
    /// Останнє знайдене під ціллю, разом із координатами.
    private var aimed: (point: (latitude: Double, longitude: Double), place: PlaceResult)?

    init(app: PoruchApp, event: Event?, home: AppState?) {
        self.app = app
        self.event = event
        restore(home: home)
    }

    var editing: Bool { event != nil }

    /// Кожен крок перевіряє лише свої поля, тож «Далі» не блокується наступним.
    var canAdvance: Bool {
        switch step {
        case .about: !form.title.trimmed.isEmpty
        case .place: !form.city.trimmed.isEmpty && !form.address.trimmed.isEmpty
        case .schedule: form.draft(imageUrl: event?.imageUrl) != nil
        }
    }

    /// Обрана адреса: інакше вибір підказки міняв поле, а зміна поля відкривала список знову.
    private var accepted: String?

    /// Підказки адрес з пріоритетом біля того, що вже на мапі.
    func suggestAddresses(_ query: String) {
        guard query != accepted else { return }
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= minAddressQuery else {
            addressSuggestions = []
            return
        }
        app.searchAddress(
            query: query, latitude: form.latitude, longitude: form.longitude
        ) { [weak self] found in
            self?.addressSuggestions = found
        }
    }

    /// Обрана підказка приносить адресу, крапку й пояс.
    func pick(_ place: PlaceResult) {
        accepted = place.label
        form.address = place.label
        // Місто їде за адресою.
        if !place.city.isEmpty { form.city = place.city }
        form.latitude = place.latitude
        form.longitude = place.longitude
        form.placed = true
        addressSuggestions = []
        pointChosen = true
        placedAt += 1
        resolveTimeZone(latitude: place.latitude, longitude: place.longitude)
    }

    /// Адреса поставленої крапки: крапка веде поле, як підказка веде крапку.
    func moveTo(latitude: Double, longitude: Double) {
        form.latitude = latitude
        form.longitude = longitude
        form.placed = true
        pointChosen = true
        pendingAddress?.cancel()
        pendingAddress = Task { @MainActor in
            // Питаємо адресу після паузи: мапу рідко зупиняють з першого разу.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            app.resolveAddress(latitude: latitude, longitude: longitude) { [weak self] place in
                guard let self, let place, !Task.isCancelled else { return }
                // Старі підказки стосувались набору до крапки.
                accepted = place.label
                form.address = place.label
                if !place.city.isEmpty { form.city = place.city }
                addressSuggestions = []
            }
            resolveTimeZone(latitude: latitude, longitude: longitude)
        }
    }

    /// Ціль зупинилась: питаємо, що під нею.
    func aim(at latitude: Double, longitude: Double) {
        pendingAim?.cancel()
        aimAddress = ""
        pendingAim = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            app.resolveAddress(latitude: latitude, longitude: longitude) { [weak self] place in
                guard let self, let place, !Task.isCancelled else { return }
                aimed = ((latitude, longitude), place)
                aimAddress = place.label
            }
        }
    }

    /// Ціль підтвердили. Знайдену адресу беремо, а не питаємо вдруге.
    func confirmAim(latitude: Double, longitude: Double) {
        pendingAim?.cancel()
        let known = aimed.flatMap { $0.point == (latitude, longitude) ? $0.place : nil }
        guard let known else { return moveTo(latitude: latitude, longitude: longitude) }
        accepted = known.label
        form.address = known.label
        if !known.city.isEmpty { form.city = known.city }
        form.latitude = latitude
        form.longitude = longitude
        form.placed = true
        addressSuggestions = []
        pointChosen = true
        placedAt += 1
        resolveTimeZone(latitude: latitude, longitude: longitude)
    }

    func resolveTimeZone(latitude: Double, longitude: Double) {
        app.resolveTimeZone(latitude: latitude, longitude: longitude) { [weak self] zone in
            guard let self, let zone, zone != form.timeZone else { return }
            form.timeZone = zone
            timeZoneFromPlace = true
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

    /// Стор підтвердив запис: чернетка більше не потрібна.
    func finish() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        submitted = false
        app.clearCompletedEvent()
    }

    /// Запис чернетки після паузи в наборі: кодування на кожну літеру відчувалось як залипання.
    /// `persist` — для моментів, коли чекати не можна: вихід, згортання, публікація.
    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    func persist() {
        pendingSave?.cancel(); pendingSave = nil
        guard !submitted, let data = try? encoder.encode(form) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func restore(home: AppState?) {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(EditorForm.self, from: data) {
            form = saved
            pointChosen = saved.placed ?? false
            accepted = saved.address.isEmpty ? nil : saved.address
            return
        }
        // Редагувати можна лише кімнату: сервер перевіряє те саме в `assert_event_editable`.
        if let event, let room = event.gathering {
            form = EditorForm(
                title: event.title, description: event.description_, category: event.category,
                city: event.city, address: event.address, latitude: event.latitude, longitude: event.longitude,
                starts: parseEventDate(event.startsAt) ?? Date(), ends: parseEventDate(event.endsAt) ?? Date(),
                timeZone: event.timeZone, capacity: Int(room.capacity),
                minAge: Int(room.minAge), maxAge: room.maxAge.map { Int(truncating: $0) },
                approvalRequired: room.approvalRequired
            )
            form.placed = true
            pointChosen = true
            accepted = event.address
        } else if event == nil {
            form.city = home?.cityName ?? HomeLocation.companion.Kyiv.city
            form.latitude = home?.cityLatitude ?? HomeLocation.companion.Kyiv.latitude
            form.longitude = home?.cityLongitude ?? HomeLocation.companion.Kyiv.longitude
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Коротший запит нічого не звужує, а мережі коштує.
private let minAddressQuery = 3

private let defaultLead: TimeInterval = 3600
private let defaultDuration: TimeInterval = 3600
private let defaultCategory = "social"
private let defaultCapacity = 20
