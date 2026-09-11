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
    /**
     Чи крапка вже обрана, чи це ще центр міста.

     На відміну від Android, координати тут є завжди: мапа керована центром, і в новій формі це
     центр міста. Тому з самих чисел не видно, чи місце вирішили, — і цей факт треба зберігати
     разом із ними, інакше повернення до чернетки показувало б обрану адресу з підписом
     «поставте крапку».

     Необов'язкове поле навмисно: чернетки, збережені до його появи, мають читатись далі.
     */
    var placed: Bool?

    /// Крапка зустрічі, якщо її вже обрали. Мапа малює саме її, а не свій центр.
    var point: (latitude: Double, longitude: Double)? {
        placed == true ? (latitude, longitude) : nil
    }
    var starts = Date().addingTimeInterval(defaultLead)
    var ends = Date().addingTimeInterval(defaultLead + defaultDuration)
    var timeZone = TimeZone.current.identifier
    var capacity = defaultCapacity
    /// Who the organizer is willing to host. `maxAge` of nil is the ordinary «no upper bound».
    var minAge = Int(SafetyRules.shared.MIN_SIGNUP_AGE)
    var maxAge: Int?
    /// When set, joining is a request the organizer answers rather than an open door.
    var approvalRequired = false

    /// Null until every field is present; the publish button follows this, so it cannot lie.
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

/// Owns the editor's form, its step, and the draft it saves. The view renders and forwards edits;
/// nothing here needs SwiftUI to be tested.
@MainActor final class EventEditorModel: ObservableObject {
    @Published var form = EditorForm()
    @Published var step = EditorStep.about
    @Published private(set) var submitted = false
    /// Пояс визначено за місцем події, а не взято з пристрою. Різні ступені впевненості.
    @Published private(set) var timeZoneFromPlace = false
    /**
     Адреси, що збігаються з набраним.

     Координати — не те, що людина знає про місце зустрічі. Вона знає вулицю й будинок, тож
     набирає їх, а крапку ставить застосунок. Мапа лишається для випадків, яких немає в жодному
     довіднику: «біля третього дерева» чи новобудова без адреси.
     */
    @Published private(set) var addressSuggestions: [PlaceResult] = []
    /// Крапку поставлено з підказки — тоді координати вже не здогад.
    @Published private(set) var pointChosen = false
    /**
     Скільки разів крапку поставили ззовні мапи.

     Мапа тут керована власним центром, і пересування пальцем — це вже її стан. Тому обраній
     підказці потрібен окремий сигнал: не «координати змінились» (вони міняються й від панорами,
     і тоді мапу совати не можна), а «крапку поставили не мапою — стань на неї».
     */
    @Published private(set) var placedAt = 0

    /**
     Адреса під ціллю на екрані вибору. Порожня, доки відповідь у дорозі.

     Крапка на мапі — це координати, а людина обирає місце. Без назви вулиці під ціллю вибір
     лишався б здогадом: схоже на той двір чи вже сусідній.
     */
    @Published private(set) var aimAddress = ""

    private let app: PoruchApp
    private let event: Event?
    private var storageKey: String { "poruch.draft.\(event?.id ?? "new")" }
    /// Один кодувальник на редактор: створення нового коштує більше, ніж саме кодування.
    private let encoder = JSONEncoder()
    private var pendingSave: Task<Void, Never>?
    /// Запит адреси для щойно пересунутої крапки. Наступний рух скасовує попередній.
    private var pendingAddress: Task<Void, Never>?
    /// Те саме для цілі на екрані вибору. Окремо, бо це інше питання: там крапку ще приміряють.
    private var pendingAim: Task<Void, Never>?
    /// Останнє, що знайшлось під ціллю, разом із координатами: збігтись має саме пара.
    private var aimed: (point: (latitude: Double, longitude: Double), place: PlaceResult)?

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

    /**
     Пояс події визначає її місце, а не пристрій організатора.

     Досі його набирали руками рядком `Europe/Kyiv` — посеред екрана, де все інше обирається
     дотиком. Тепер відповідає платформа; коли вона не змогла, лишається пояс пристрою, тобто те
     саме типове значення, що було доти. Тому невдача тут мовчазна: гірше не стало.
     */
    /// Адреса, яку вже обрали. Без цього вибір підказки міняє поле, а зміна поля відкриває
    /// список знову — з тією самою підказкою, яку щойно обрали.
    private var accepted: String?

    /// Підказки адрес. Зсув беремо від того, що вже на мапі: та сама вулиця є в десятку міст.
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

    /// Обрана підказка приносить і адресу, і крапку, і пояс — усе, заради чого її й обирали.
    func pick(_ place: PlaceResult) {
        accepted = place.label
        form.address = place.label
        // Місто їде за адресою: крапка могла виявитись і в іншому місті.
        if !place.city.isEmpty { form.city = place.city }
        form.latitude = place.latitude
        form.longitude = place.longitude
        form.placed = true
        addressSuggestions = []
        pointChosen = true
        placedAt += 1
        resolveTimeZone(latitude: place.latitude, longitude: place.longitude)
    }

    /**
     Крапку поставили на мапі — лишається сказати, що це за адреса.

     Поле й мапа показують одне й те саме, тож рухати його можна з обох боків: обрана підказка
     веде крапку, поставлена крапка веде поле. Без цього номер будинку мовчки лишався від
     попередньої адреси — тобто поле брехало про те, куди прийдуть люди.
     */
    func moveTo(latitude: Double, longitude: Double) {
        form.latitude = latitude
        form.longitude = longitude
        form.placed = true
        pointChosen = true
        pendingAddress?.cancel()
        pendingAddress = Task { @MainActor in
            // Мапу рідко зупиняють з першого разу; питаємо про адресу, коли рука вже відпустила.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            app.resolveAddress(latitude: latitude, longitude: longitude) { [weak self] place in
                guard let self, let place, !Task.isCancelled else { return }
                // Поле — те саме, тож підказки, що стосувались набраного до крапки, більше не про це.
                accepted = place.label
                form.address = place.label
                if !place.city.isEmpty { form.city = place.city }
                addressSuggestions = []
            }
            resolveTimeZone(latitude: latitude, longitude: longitude)
        }
    }

    /// Ціль зупинилась — питаємо, що під нею. Мапа повідомляє про зупинку, а не про кожен кадр.
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

    /// Ціль підтвердили. Якщо адресу під нею вже знайшли — беремо її, а не питаємо вдруге.
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

    /// Called when the store confirms the write; the saved draft has served its purpose.
    func finish() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        submitted = false
        app.clearCompletedEvent()
    }

    /**
     Чернетка має пережити закриття застосунку — не кожну натиснуту літеру.

     Досі кожне натискання кодувало всю форму в JSON і писало її в `UserDefaults`. На симуляторі
     цього не видно, на пристрої це те, що відчувається як залипання поля вводу. Тепер запис
     чекає паузи в наборі, а [persist] лишається для моментів, коли чекати не можна: вихід із
     редактора, згортання застосунку, публікація.
     */
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
        // Редагувати можна лише те, що ми проводимо самі: сервер відмовляє в цьому тим самим
        // `assert_event_editable`, і без кімнати редактору нічим наповнити половину полів.
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

/// A new event defaults to «tomorrow-ish», which is what most drafts turn out to be.
/// Коротше за це запит нічого не звужує, а запит уже коштує мережі.
private let minAddressQuery = 3

private let defaultLead: TimeInterval = 3600
private let defaultDuration: TimeInterval = 3600
private let defaultCategory = "social"
private let defaultCapacity = 20
