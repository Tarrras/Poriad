import Foundation
import Shared

/// Форма, як її набрали, плюс локальне збереження чернетки між запусками.
struct EditorForm: Codable, Equatable {
    var title = ""
    var description = ""
    /// Категорія зберігається ключем: enum з Kotlin не буває `Codable`, а старі чернетки лежать із рядком.
    var categoryKey = defaultCategory.key
    var category: EventCategory {
        get { EventCategory.companion.fromKey(key: categoryKey) }
        set { categoryKey = newValue.key }
    }
    var city = ""
    var address = ""
    var latitude = 0.0
    var longitude = 0.0
    /// Чи крапка вже обрана. Координати тримають центр міста для мапи й підказок, тож без прапорця
    /// подія публікувалась би в центрі міста. Optional, щоб старі чернетки читались далі.
    var placed: Bool?

    /// Крапка зустрічі, якщо обрана. Мапа малює її, а не свій центр.
    var point: (latitude: Double, longitude: Double)? {
        placed == true ? (latitude, longitude) : nil
    }
    var starts = defaultStart()
    var ends = defaultStart().addingTimeInterval(defaultDuration)
    var timeZone = TimeZone.current.identifier
    var capacity = defaultCapacity
    /// Вікові межі. `maxAge` nil — без верхньої межі.
    var minAge = Int(SafetyRules.shared.MIN_SIGNUP_AGE)
    var maxAge: Int?
    /// Приєднання — запит організатору, а не відкриті двері.
    var approvalRequired = false
    /// Чат учасників. Optional, щоб старі чернетки читались далі; порожньо — без чату.
    var contactUrl: String?

    private enum CodingKeys: String, CodingKey {
        case title, description, categoryKey = "category", city, address, latitude, longitude, placed
        case starts, ends, timeZone, capacity, minAge, maxAge, approvalRequired, contactUrl
    }

    /// Посилання, як його бачить чернетка: обрізане, порожнє стає nil.
    var contactLink: String? { ContactRules.shared.normalize(value: contactUrl) }

    /// Довжина опису так, як її рахує `EventDraft.validate`: без крайових пробілів, у UTF-16.
    var descriptionLength: Int { description.trimmed.utf16.count }

    /// Порушені правила. Та сама `EventDraft.validate`, що на Android і в спільному шарі, тож межі
    /// з `EventRules` не дублюються тут числами.
    func issues(imageUrl: String?) -> [DraftField] {
        build(imageUrl: imageUrl).validate(now: iso.string(from: Date()))
    }

    /// Nil, поки хоч одне поле порушує правило. Публікація дивиться сюди.
    func draft(imageUrl: String?) -> EventDraft? {
        let draft = build(imageUrl: imageUrl)
        return draft.validate(now: iso.string(from: Date())).isEmpty ? draft : nil
    }

    private func build(imageUrl: String?) -> EventDraft {
        EventDraft(
            title: title.trimmed, description: description.trimmed, category: category,
            // Без обраної крапки — NaN: правило LOCATION не пропустить центр міста як місце зустрічі.
            city: city.trimmed, address: address.trimmed,
            latitude: placed == true ? latitude : .nan, longitude: placed == true ? longitude : .nan,
            startsAt: iso.string(from: starts), endsAt: iso.string(from: ends),
            timeZone: timeZone, capacity: Int32(capacity), imageUrl: imageUrl,
            minAge: Int32(minAge), maxAge: maxAge.map { KotlinInt(int: Int32($0)) },
            approvalRequired: approvalRequired, contactUrl: contactLink
        )
    }
}

enum EditorStep: Int, CaseIterable, Identifiable {
    case about, place, schedule, people
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .about: Copy.step_one
        case .place: Copy.step_two
        case .schedule: Copy.step_three
        case .people: Copy.step_four
        }
    }
    /// Питання кроку великим заголовком.
    var headline: String {
        switch self {
        case .about: Copy.editor_about_title
        case .place: Copy.editor_place_title
        case .schedule: Copy.editor_schedule_title
        case .people: Copy.editor_people_title
        }
    }
    var hint: String {
        switch self {
        case .about: Copy.editor_about_hint
        case .place: Copy.editor_place_hint
        case .schedule: Copy.editor_schedule_hint
        case .people: Copy.editor_people_hint
        }
    }
    var isLast: Bool { self == .people }

    /// Крок, де поле вводять: там «Далі» не пускає далі, туди веде й відмова публікації.
    static func of(_ field: DraftField) -> EditorStep {
        switch field.name {
        case "TITLE", "DESCRIPTION", "CATEGORY": .about
        case "ADDRESS", "LOCATION": .place
        case "STARTS_AT", "ENDS_AT", "TIME_ZONE": .schedule
        default: .people
        }
    }
}

/// Форма редактора, крок і чернетка. View лише малює й передає правки; тестується без SwiftUI.
@MainActor final class EventEditorModel: ObservableObject {
    @Published var form = EditorForm() { didSet { issues = form.issues(imageUrl: event?.imageUrl) } }
    @Published var step = EditorStep.about
    /// Порушені правила всієї форми. Рахуються раз на правку, а не на кожне поле в тілі.
    @Published private(set) var issues: [DraftField] = []
    /// Людина вже натиснула «Далі» чи «Опублікувати» на цьому кроці: тепер червоніють і порожні поля.
    @Published private(set) var revealed = false
    /// Поле, до якого прокрутити, і лічильник-сигнал: той самий збій двічі має прокрутити двічі.
    @Published private(set) var focus: DraftField?
    @Published private(set) var jump = 0
    @Published private(set) var submitted = false
    /// Подію збережено, чернетку стерто: більше нічого не пишемо.
    private var finished = false
    /// Підказки адрес: людина набирає вулицю й будинок, крапку ставить застосунок.
    @Published private(set) var addressSuggestions: [PlaceResult] = []
    /// Крапку поставлено з підказки: координати вже не здогад.
    @Published private(set) var pointChosen = false
    /// Лічильник «крапку поставили не мапою»: сигнал мапі стати на неї. Координати міняються й від панорами.
    @Published private(set) var placedAt = 0

    /// Адреса під ціллю на екрані вибору. Порожня, поки відповідь у дорозі.
    @Published private(set) var aimAddress = ""
    /// Скільки людей із «Моїми місцями» навколо крапки отримають анонс. Nil — менше трьох, крапки нема чи це правка.
    @Published private(set) var audience: Int?

    private let app: PoruchApp
    private let event: Event?
    private let home: AppState?
    /// Форма, як вона прийшла з сервера: з нею звіряємо, чи є що втратити.
    private var original: EditorForm?
    /// Нову подію почали з незакінченої чернетки: параметр `draft` воронки створення.
    private var resumed = false
    private static let draftPrefix = "poruch.draft."
    private var storageKey: String { Self.draftPrefix + (event?.id ?? "new") }
    /// Вихід з акаунта: чернетки належать людині, а не телефону — і нової події, і редагувань її подій.
    static func clearDrafts() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(draftPrefix) { defaults.removeObject(forKey: key) }
    }
    /// Один кодувальник на редактор: створення дорожче за кодування.
    private let encoder = JSONEncoder()
    private var pendingSave: Task<Void, Never>?
    /// Запит адреси для пересунутої крапки. Наступний рух скасовує попередній.
    private var pendingAddress: Task<Void, Never>?
    /// Те саме для цілі на екрані вибору. Окремо, бо там крапку ще приміряють.
    private var pendingAim: Task<Void, Never>?
    /// Останнє знайдене під ціллю, разом із координатами.
    private var aimed: (point: (latitude: Double, longitude: Double), place: PlaceResult)?
    /// Де ціль зараз: відповідь для попередньої точки не підписує нову.
    private var aimPoint: (latitude: Double, longitude: Double)?

    init(app: PoruchApp, event: Event?, home: AppState?) {
        self.app = app
        self.event = event
        self.home = home
        restore()
        issues = form.issues(imageUrl: event?.imageUrl)
        resumed = canStartOver
        track(.about)
    }

    /// Воронка створення (docs/analytics.md): лише нова подія, правка наявної — інша історія.
    private func track(_ reached: EditorStep) {
        if !editing { app.createStep(step: String(describing: reached), draft: resumed) }
    }
    private func blocked(by field: DraftField) {
        if !editing { app.createBlocked(step: String(describing: EditorStep.of(field)), field: field) }
    }

    var editing: Bool { event != nil }

    /// Хто збирає — ім'я на квитку, як його побачать на головній.
    var host: String? {
        let name = event?.gathering?.organizerName ?? home?.library.profile?.name ?? ""
        return name.isEmpty ? nil : name
    }
    /// Скільки вже йде: нова зустріч друкується «0/20».
    var taken: Int { Int(event?.gathering?.attendeeCount ?? 0) }

    /// Правки наявної події, яких сервер ще не бачив. Нова подія нічого не втрачає: вона в чернетці.
    var dirty: Bool { editing && form != original }

    /// Є що стерти: чернетка з текстом чи адресою.
    var canStartOver: Bool {
        !editing && !(form.title.isEmpty && form.description.isEmpty && form.address.isEmpty)
    }

    /// Стерти чернетку й почати з порожньої форми.
    func startOver() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        pendingSave?.cancel(); pendingSave = nil
        form = EditorForm()
        step = .about
        revealed = false
        pointChosen = false
        accepted = nil
        addressSuggestions = []
        restore()
        resumed = false
    }

    /// Правило, яке порушує поле, для тексту під ним. До спроби йти далі — лише для того, що
    /// людина вже набрала, щоб порожня форма не червоніла з першого кадру.
    func issue(_ field: DraftField) -> String? {
        guard issues.contains(field) else { return nil }
        let touched: Bool
        switch field.name {
        case "CONTACT_URL": touched = form.contactLink != nil
        // Назву й опис не червонимо посеред набору: межу вже каже лічильник під полем.
        case "TITLE", "DESCRIPTION", "ADDRESS", "LOCATION", "CATEGORY": touched = false
        // Дати, місткість, вік і пояс мають значення завжди: їхню помилку видно одразу.
        default: touched = true
        }
        guard revealed || touched else { return nil }
        switch field.name {
        case "TITLE": return field.text(length: form.title.trimmed.utf16.count)
        case "DESCRIPTION": return field.text(length: form.descriptionLength)
        default: return field.text
        }
    }

    /// Усі тексти під полями разом — значення для кроків, які SwiftUI вміє порівняти.
    var issueTexts: [DraftField: String] {
        Dictionary(uniqueKeysWithValues: issues.compactMap { field in issue(field).map { (field, $0) } })
    }

    /// Показати поле з порушенням: його крок, текст під ним і прокрутка до нього.
    /// `revealed` тут означає й «крок змінила помилка»: тоді вголос кажемо її, а не назву кроку.
    private func show(_ field: DraftField) {
        step = EditorStep.of(field)
        revealed = true
        focus = field
        jump += 1
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
            query: query, latitude: form.latitude, longitude: form.longitude, city: form.city
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
                // Колбек живе поза задачею, тож `Task.isCancelled` тут нічого не знає: застарілу
                // відповідь відсікає лише порівняння з крапкою, яка стоїть зараз.
                guard let self, let place, form.latitude == latitude, form.longitude == longitude else { return }
                // Старі підказки стосувались набору до крапки.
                accepted = place.label
                form.address = place.label
                if !place.city.isEmpty { form.city = place.city }
                addressSuggestions = []
            }
            resolveTimeZone(latitude: latitude, longitude: longitude)
        }
    }

    /// Анонс у зони шле лише нова подія, тож правці числа не кажемо. Відповідь для крапки, яку вже пересунули, — чужа.
    func countAudience() {
        guard !editing, let point = form.point else { audience = nil; return }
        app.zoneAudience(latitude: point.latitude, longitude: point.longitude) { [weak self] count in
            guard let self, form.point.map({ $0 == point }) == true else { return }
            audience = count.map { Int(truncating: $0) }
        }
    }

    /// Ціль зупинилась: питаємо, що під нею.
    func aim(at latitude: Double, longitude: Double) {
        pendingAim?.cancel()
        aimAddress = ""
        aimPoint = (latitude, longitude)
        pendingAim = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            app.resolveAddress(latitude: latitude, longitude: longitude) { [weak self] place in
                guard let self, let place, aimPoint.map({ $0 == (latitude, longitude) }) == true else { return }
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
            // Пояс для крапки, яку вже пересунули, — чужий.
            guard let self, let zone, zone != form.timeZone, form.latitude == latitude, form.longitude == longitude else { return }
            form.timeZone = zone
        }
    }

    /// Кожен крок перевіряє лише свої поля, тож «Далі» не блокується наступним.
    func advance() {
        if let field = issues.first(where: { EditorStep.of($0) == step }) { blocked(by: field); return show(field) }
        if let next = EditorStep(rawValue: step.rawValue + 1) { step = next; revealed = false; track(next) }
    }
    func retreat() { if let previous = EditorStep(rawValue: step.rawValue - 1) { step = previous; revealed = false } }

    func submit() {
        // Свіжа перевірка: поки людина дивилась на форму, початок міг стати минулим.
        issues = form.issues(imageUrl: event?.imageUrl)
        if let field = issues.first { blocked(by: field); return show(field) }
        guard let draft = form.draft(imageUrl: event?.imageUrl) else { return }
        persist()
        app.clearCompletedEvent()
        submitted = true
        if let event { app.updateEvent(id: event.id, draft: draft) } else { app.createEvent(draft: draft) }
    }

    /// Запис не пройшов: форма лишається людині, і подальші правки знову зберігаються в чернетку.
    /// Відмова з назвами полів (сервер теж так відповідає) веде до першого з них.
    func failed(fields: [DraftField]) {
        submitted = false
        if let field = fields.first { show(field) }
    }

    /// Стор підтвердив запис: чернетка більше не потрібна.
    func finish() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        // Після цього екран закривається, і `onDisappear` кличе `persist`: без прапорця він
        // записував щойно опубліковану форму назад, і наступне «+» відкривало ту саму подію.
        finished = true
        submitted = false
        app.clearCompletedEvent()
        // Нова подія — момент спитати про сповіщення: організатору теж нагадуємо за годину, а запити на участь дзвонять.
        if event == nil { ReminderPrompt.offer(app) }
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

    /// Чернетка лише для нової події: у наявної джерело правди — сервер, а стара локальна копія
    /// переважила б свіжіші зміни (іншого пристрою, скасування, нову місткість).
    func persist() {
        pendingSave?.cancel(); pendingSave = nil
        guard event == nil, !submitted, !finished, let data = try? encoder.encode(form) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func restore() {
        if event == nil, let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(EditorForm.self, from: data) {
            form = saved
            // Минулий початок у давній чернетці — не намір, а давність: ставимо типовий.
            if form.starts <= Date() {
                let fresh = EditorForm()
                form.starts = fresh.starts
                form.ends = fresh.ends
            }
            pointChosen = saved.placed ?? false
            accepted = saved.address.isEmpty ? nil : saved.address
            return
        }
        // Редагувати можна лише кімнату: сервер перевіряє те саме в `assert_event_editable`.
        if let event, let room = event.gathering {
            form = EditorForm(
                title: event.title, description: event.description_, categoryKey: event.category.key,
                city: event.city, address: event.address, latitude: event.latitude, longitude: event.longitude,
                starts: parseEventDate(event.startsAt) ?? Date(), ends: parseEventDate(event.endsAt) ?? Date(),
                timeZone: event.timeZone, capacity: Int(room.capacity),
                minAge: Int(room.minAge), maxAge: room.maxAge.map { Int(truncating: $0) },
                approvalRequired: room.approvalRequired, contactUrl: room.contactUrl
            )
            form.placed = true
            original = form
            pointChosen = true
            accepted = event.address
        } else if event == nil {
            form.city = home?.city.name ?? HomeLocation.companion.Kyiv.city
            form.latitude = home?.city.latitude ?? HomeLocation.companion.Kyiv.latitude
            form.longitude = home?.city.longitude ?? HomeLocation.companion.Kyiv.longitude
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Один форматер на редактор: правила перевіряються на кожну літеру, а створення форматера дороге.
private let iso = ISO8601DateFormatter()

/// Коротший запит нічого не звужує, а мережі коштує.
private let minAddressQuery = 3

private let defaultLead: TimeInterval = 3600

/// Типовий початок — повна година, не раніше ніж за годину: «21:00», а не «20:43».
private func defaultStart() -> Date {
    let soon = Date().addingTimeInterval(defaultLead)
    return Calendar.current.nextDate(after: soon, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? soon
}
private let defaultDuration: TimeInterval = 3600
private let defaultCategory = EventCategory.social
private let defaultCapacity = 20
