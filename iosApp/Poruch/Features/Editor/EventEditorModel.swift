import PhotosUI
import SwiftUI
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
    /// Фото й відео в порядку показу, перше — обкладинка. Optional, щоб старі чернетки читались далі.
    var media: [DraftItem]?
    /// Ціна входу, гривні (docs/organizers-1.5.md, 1.7). Nil — безкоштовно.
    var price: Int?

    private enum CodingKeys: String, CodingKey {
        case title, description, categoryKey = "category", city, address, latitude, longitude, placed
        case starts, ends, timeZone, capacity, minAge, maxAge, approvalRequired, contactUrl, media, price
    }

    /// Посилання, як його бачить чернетка: обрізане, порожнє стає nil.
    var contactLink: String? { ContactRules.shared.normalize(value: contactUrl) }

    /// Довжина опису так, як її рахує `EventDraft.validate`: без крайових пробілів, у UTF-16.
    var descriptionLength: Int { description.trimmed.utf16.count }

    /// Порушені правила. Та сама `EventDraft.validate`, що на Android і в спільному шарі, тож межі
    /// з `EventRules` не дублюються тут числами. Медіа не перевіряємо: вибір і так не дає більше пʼяти.
    func issues(imageUrl: String?) -> [DraftField] {
        build(imageUrl: imageUrl, media: nil, mediaBase: nil).validate(now: iso.string(from: Date()))
    }

    /// Nil, поки хоч одне поле порушує правило. Публікація дивиться сюди. [media] null — медіа події не чіпати;
    /// [mediaBase] — з `PoruchApp.editDraft`, з якими файлами правка відкрилась.
    func draft(imageUrl: String?, media: [DraftMedia]?, mediaBase: Set<String>?) -> EventDraft? {
        let draft = build(imageUrl: imageUrl, media: media, mediaBase: mediaBase)
        return draft.validate(now: iso.string(from: Date())).isEmpty ? draft : nil
    }

    private func build(imageUrl: String?, media: [DraftMedia]?, mediaBase: Set<String>?) -> EventDraft {
        EventDraft(
            title: title.trimmed, description: description.trimmed, category: category,
            // Без обраної крапки — NaN: правило LOCATION не пропустить центр міста як місце зустрічі.
            city: city.trimmed, address: address.trimmed,
            latitude: placed == true ? latitude : .nan, longitude: placed == true ? longitude : .nan,
            startsAt: iso.string(from: starts), endsAt: iso.string(from: ends),
            timeZone: timeZone, capacity: Int32(capacity), imageUrl: imageUrl,
            minAge: Int32(minAge), maxAge: maxAge.map { KotlinInt(int: Int32($0)) },
            approvalRequired: approvalRequired, contactUrl: contactLink, media: media, mediaBase: mediaBase,
            price: price.map { KotlinInt(int: Int32(clamping: $0)) }
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
    @Published var form = EditorForm() { didSet { issues = form.issues(imageUrl: event?.imageUrl); syncOrphans() } }
    @Published var step = EditorStep.about
    /// Порушені правила всієї форми. Рахуються раз на правку, а не на кожне поле в тілі.
    @Published private(set) var issues: [DraftField] = []
    /// Людина вже натиснула «Далі» чи «Опублікувати» на цьому кроці: тепер червоніють і порожні поля.
    @Published private(set) var revealed = false
    /// Поле, до якого прокрутити, і лічильник-сигнал: той самий збій двічі має прокрутити двічі.
    @Published private(set) var focus: DraftField?
    @Published private(set) var jump = 0
    @Published private(set) var submitted = false { didSet { syncOrphans() } }
    /// Подію збережено, чернетку стерто: більше нічого не пишемо.
    private var finished = false { didSet { syncOrphans() } }
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

    /// Скільки обраних файлів ще готуються (стискається відео): плитки-заглушки.
    @Published private(set) var preparing = 0
    /// Серед них відео: «Стискаємо відео…».
    @Published private(set) var compressing = false
    /// «Не вдалося додати цей файл» під плитками. Зникає з наступним вибором.
    @Published private(set) var mediaError: String?

    /// Картка «Є готовий анонс?»: текст і запит.
    @Published var announceText = ""
    @Published private(set) var announcing = false
    /// Що вийшло з анонсу: картка згортається в рядок. Nil — картка розгорнута.
    @Published var announced: AnnounceResult?

    private let app: PoruchApp
    private let event: Event?
    private let home: AppState?
    /// «Повторити»: нова подія з полями, фото й відео іншої. Чернетки не пише й не читає — її можна повторити знову.
    private let repeated: EventDraft?
    /// Правка: чернетка зі спільного шару (`PoruchApp.editDraft`) — поля, медіа й `mediaBase`, з якими редактор відкрився.
    private let edited: EventDraft?
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
        DraftFiles.deleteAll()
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

    init(app: PoruchApp, event: Event?, home: AppState?, repeated: EventDraft? = nil) {
        self.app = app
        self.event = event
        self.home = home
        self.repeated = repeated
        edited = event.flatMap { app.editDraft(event: $0) }
        restore()
        issues = form.issues(imageUrl: event?.imageUrl)
        resumed = canStartOver
        track(.about)
    }

    /// Воронка створення (docs/analytics.md): лише нова подія, правка наявної — інша історія.
    private func track(_ reached: EditorStep) {
        if !editing { app.createStep(step: String(describing: reached), draft: resumed, mediaCount: Int32(form.media?.count ?? 0)) }
    }
    private func blocked(by field: DraftField) {
        if !editing { app.createBlocked(step: String(describing: EditorStep.of(field)), field: field) }
    }

    var editing: Bool { event != nil }
    var repeating: Bool { repeated != nil }

    /// Хто збирає — ім'я на квитку, як його побачать на головній.
    var host: String? {
        let name = event?.gathering?.organizerName ?? home?.library.profile?.name ?? ""
        return name.isEmpty ? nil : name
    }
    /// Скільки вже йде: нова зустріч друкується «0/20».
    var taken: Int { Int(event?.gathering?.attendeeCount ?? 0) }

    /// Правки наявної події, яких сервер ще не бачив. Нова подія нічого не втрачає: вона в чернетці; повторена — ні.
    var dirty: Bool { (editing || repeated != nil) && form != original }

    /// Є що стерти: чернетка з текстом чи адресою.
    var canStartOver: Bool {
        !editing && repeated == nil && !(form.title.isEmpty && form.description.isEmpty && form.address.isEmpty)
    }

    /// Стерти чернетку й почати з порожньої форми.
    func startOver() {
        DraftFiles.delete(form.media ?? [])
        UserDefaults.standard.removeObject(forKey: storageKey)
        pendingSave?.cancel(); pendingSave = nil
        form = EditorForm()
        step = .about
        revealed = false
        pointChosen = false
        accepted = nil
        addressSuggestions = []
        announced = nil
        announceText = ""
        restore()
        resumed = false
    }

    // ---- Фото й відео

    /// Обране в пікері — по черзі, у порядку вибору: відео стискаються по одному, а не всі разом у памʼяті.
    func addMedia(_ items: [PhotosPickerItem]) {
        let room = Int(MediaRules.shared.MAX_ITEMS) - (form.media?.count ?? 0) - preparing
        let chosen = Array(items.prefix(max(room, 0)))
        guard !chosen.isEmpty else { return }
        mediaError = nil
        preparing += chosen.count
        Task { @MainActor in
            for item in chosen {
                compressing = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                let prepared = await DraftMediaPicker.prepare(item)
                preparing -= 1
                compressing = false
                guard let prepared else { mediaError = Copy.media_not_added; continue }
                // Редактор закрили, поки стискалось: файл нікому не належить.
                guard !finished else { DraftFiles.delete([prepared]); continue }
                form.media = (form.media ?? []) + [prepared]
                // Шторку могли закрити, поки стискалось: чернетка нової події має знати про файл і без `onChange` екрана.
                persist()
                app.mediaAdded(kind: prepared.kind)
            }
        }
    }

    func removeMedia(_ item: DraftItem) {
        form.media?.removeAll { $0 == item }
        // Нове з чернетки — з диска одразу; правка наявної події прибирає файл сервера сама, після збереження.
        DraftFiles.delete([item])
    }

    /// Плитку [id] перетягнули на місце [target].
    func moveMedia(_ id: String, to target: String) {
        guard var media = form.media, let from = media.firstIndex(where: { $0.id == id }),
              let to = media.firstIndex(where: { $0.id == target }), from != to else { return }
        media.insert(media.remove(at: from), at: to)
        form.media = media
    }

    // ---- «Є готовий анонс?»

    /// «Вставити» = «Заповнити»: поля з тексту (`parse-announcement`), і гостю. Не розібрали — назва й опис з самого тексту.
    func fillFromAnnouncement() {
        let text = announceText.trimmed
        guard !announcing else { return }
        // У буфері самі пробіли: «Вставити» спрацювала, а заповнювати нічим — кажемо, а не мовчимо.
        guard !text.isEmpty else { announced = AnnounceResult(text: Copy.announce_clipboard_empty, failed: true); return }
        announcing = true
        Task { @MainActor in
            var fill: AnnouncementFill
            do { fill = try await app.fillFromAnnouncement(text: text, city: form.city, timeZone: form.timeZone) }
            catch { fill = AnnouncementRules.shared.fallback(text: text, failure: .error) }
            // Нічого не знайшли — як збій: людина бачить, що текст уже в описі.
            if fill.failure == nil && fill.filled.isEmpty { fill = AnnouncementRules.shared.fallback(text: text, failure: .error) }
            announcing = false
            apply(fill)
        }
    }

    /// Чого в тексті нема, лишається як було. Адреса — у поле з підказками: крапку ставить людина.
    private func apply(_ fill: AnnouncementFill) {
        if let title = fill.title { form.title = title }
        if let description = fill.description_ { form.description = description }
        if let category = fill.category { form.category = category }
        if let starts = fill.startsAt.flatMap(parseEventDate) {
            let length = max(form.ends.timeIntervalSince(form.starts), defaultDuration)
            form.starts = starts
            form.ends = fill.endsAt.flatMap(parseEventDate) ?? starts.addingTimeInterval(length)
        }
        if let address = fill.address {
            form.address = address
            // Стара крапка — для іншої адреси: тепер її обирають з підказок.
            form.placed = false
            pointChosen = false
            accepted = nil
            suggestAddresses(address)
        }
        if let capacity = fill.capacity { form.capacity = Int(truncating: capacity) }
        if let minAge = fill.minAge {
            form.minAge = Int(truncating: minAge)
            if let maxAge = form.maxAge, maxAge < form.minAge { form.maxAge = nil }
        }
        if let contact = fill.contactUrl { form.contactUrl = contact }
        if let failure = fill.failure {
            announced = AnnounceResult(text: failure == .limit ? Copy.announce_limited : Copy.announce_failed, failed: true)
        } else {
            announced = AnnounceResult(text: Copy.announce_filled(fill.filled.map(\.part).joined(separator: ", ")), failed: false)
        }
    }

    /// «Інший текст»: картка знову розгорнута, з тим самим текстом.
    func reopenAnnouncement() { announced = nil }

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
        // Файл, що ще стискається, інакше мовчки випав би з публікації: кнопка й так неактивна, це запобіжник.
        guard preparing == 0 else { return }
        // Свіжа перевірка: поки людина дивилась на форму, початок міг стати минулим.
        issues = form.issues(imageUrl: event?.imageUrl)
        if let field = issues.first { blocked(by: field); return show(field) }
        // Медіа правки, яких не чіпали, — null: сервер лишає як є. Інакше обкладинку дає перше фото, а не стара адреса.
        let media = editing && form.media == original?.media ? nil : (form.media ?? []).map(\.draftMedia)
        guard let draft = form.draft(imageUrl: media == nil ? edited?.imageUrl : nil, media: media, mediaBase: edited?.mediaBase) else { return }
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
        // Збережено: втрачати нічого, тож і «Подію створено» після повтору зі зміненими полями закривається змахом.
        original = form
        // Нове вже в теці події: локальні копії більше не потрібні.
        DraftFiles.delete(form.media ?? [])
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
        guard event == nil, repeated == nil, !submitted, !finished, let data = try? encoder.encode(form) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Нове з правки чи повтору, якщо шторку закриють без збереження: стирається разом з моделлю (`OrphanFiles`).
    private let orphans = OrphanFiles()
    private func syncOrphans() {
        orphans.items = (event != nil || repeated != nil) && !submitted && !finished ? form.media ?? [] : []
    }

    private func restore() {
        // Повтор і правка — з чернеток спільного шару (`repeatDraft`, `editDraft`): медіа й обкладинку складає він.
        if let source = repeated ?? edited {
            form = EditorForm(draft: source)
            original = form
            pointChosen = true
            accepted = source.address
            return
        }
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
        if event == nil {
            form.city = home?.city.name ?? HomeLocation.companion.Kyiv.city
            form.latitude = home?.city.latitude ?? HomeLocation.companion.Kyiv.latitude
            form.longitude = home?.city.longitude ?? HomeLocation.companion.Kyiv.longitude
        }
    }
}

/// Файли нового з правки чи повтору: чернетки вони не пишуть, тож коли модель редактора зникає (шторку закрили), зникають
/// і файли. Не в `onDisappear`: той спрацьовує й під `fullScreenCover` вибору точки, коли редактор ще живий.
private final class OrphanFiles {
    var items: [DraftItem] = []
    deinit { DraftFiles.delete(items) }
}

extension EditorForm {
    /// Форма з чернетки спільного шару: правка (`editDraft`, медіа — уже в події) чи «Повторити» (`repeatDraft`, дата на
    /// тиждень пізніше, медіа — копії).
    init(draft: EventDraft) {
        self.init(
            title: draft.title, description: draft.description_, categoryKey: (draft.category ?? defaultCategory).key,
            city: draft.city, address: draft.address, latitude: draft.latitude, longitude: draft.longitude, placed: true,
            starts: parseEventDate(draft.startsAt) ?? defaultStart(), ends: parseEventDate(draft.endsAt) ?? defaultStart().addingTimeInterval(defaultDuration),
            timeZone: draft.timeZone, capacity: Int(draft.capacity), minAge: Int(draft.minAge), maxAge: draft.maxAge.map { Int(truncating: $0) },
            approvalRequired: draft.approvalRequired, contactUrl: draft.contactUrl,
            media: (draft.media ?? []).compactMap { item in
                (item as? DraftMediaCopied).map { DraftItem($0.media, origin: .copied) }
                    ?? (item as? DraftMediaRemote).map { DraftItem($0.media, origin: .remote) }
            },
            price: draft.price.map { Int(truncating: $0) }
        )
    }
}

/// Що «Вставити анонс» заповнило — рядок замість картки — чи чому не вийшло.
struct AnnounceResult: Equatable {
    let text: String
    let failed: Bool
}

private extension AnnounceField {
    /// «назву», «опис»…: частина речення «Заповнили з анонсу: …».
    var part: String {
        switch self {
        case .title: Copy.announce_part_title
        case .description_: Copy.announce_part_description
        case .category: Copy.announce_part_category
        case .date: Copy.announce_part_date
        case .place: Copy.announce_part_place
        case .capacity: Copy.announce_part_capacity
        case .age: Copy.announce_part_age
        default: Copy.announce_part_contact
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
