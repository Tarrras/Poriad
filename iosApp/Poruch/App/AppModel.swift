import SwiftUI
import Shared
import Security

final class KeychainSessionStore: SecureSessionStore {
    private let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.poruch.session", kSecAttrAccount as String: "session"]
    func read() -> String? {
        var query = base; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func write(value: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = base; query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }
    func clear() { SecItemDelete(base as CFDictionary) }
}

@MainActor final class AppModel: ObservableObject {
    let graph: AppGraph
    var app: PoruchApp { graph.app }
    @Published var state: AppState?

    /// Індекс для мапи, зібраний раз на емісію стану: кожен доступ до Kotlin-списку — міст.
    @Published private(set) var mapEntries: [EventIndexEntry] = []
    /// Завантажені картки в порядку показу. Може бути менше за `mapEntries`.
    @Published private(set) var cards: [Event] = []
    /// Усі завантажені картки за id. `cards` — лише суцільний початок стрічки, а стос майданчика розкиданий по індексу.
    @Published private(set) var cardsByID: [String: Event] = [:]

    /// Змінюється лише зі складом подій: дешевий ключ замість порівняння списків.
    @Published private(set) var eventsRevision = 0
    /// Змінюється з кожним новим `mapEntries` і `cardsByID`: ключ для похідних списків екранів.
    private(set) var entriesRevision = 0
    private(set) var cardsRevision = 0

    /// Набори, а не Kotlin-масиви: кожна картка питає «я збережена?», і масив був би лінійним пошуком через міст.
    @Published private(set) var savedIDs: Set<String> = []
    @Published private(set) var waitlistedIDs: Set<String> = []

    /// Списки головної, зібрані раз на емісію стану: в тілі view це коштувало більше за кадр.
    @Published private(set) var home = HomePresentation(state: nil)

    private var subscription: Subscription?
    /// Версії зі спільного стану: порівнюємо числа, а не обходимо тисячі записів через міст на кожну емісію.
    private var lastIndexVersion: Int32 = -1
    private var lastFeedVersion: Int32 = -1
    private var lastSelectedID: String?
    /// Id індексу набором: перевірка обраної події без лінійного пошуку.
    private var indexIDs: Set<String> = []
    init() {
        // Лог лише в debug-збірці.
        #if DEBUG
        PoruchLog.shared.enabled = true
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        // Невідоме чи відсутнє середовище — dev: помилка конфігурації не має тихо вести в prod.
        let env: AppEnvironment = info["APP_ENV"] as? String == "PROD" ? .prod : .dev
        let config = AppConfig(
            supabaseUrl: env.supabaseUrl,
            publishableKey: env.publishableKey,
            home: HomeLocation.companion.Kyiv,
            authScheme: env.authScheme
        )
        // Один центр сповіщень для нагадувань і запитів: делегат у нього теж один.
        let notifications = LocalReminderScheduler()
        graph = AppGraph(config: config, sessionStore: KeychainSessionStore(), reminders: notifications, requestNotifier: notifications, chatNotifier: notifications)
        PoruchLog.shared.i(tag: "app") { "graph created" }
        start()
    }
    func start() {
        guard subscription == nil else { return }
        subscription = app.observe { [weak self] state in
            DispatchQueue.main.async { self?.apply(state) }
        }
    }

    private func apply(_ state: AppState) {
        // Чернетка події належить людині, а не телефону: після виходу наступний акаунт її не бачить.
        if self.state?.session.userId != nil && state.session.userId == nil { UserDefaults.standard.removeObject(forKey: "poruch.draft.new") }
        self.state = state
        // Головна дешева: картки вже зібрані в спільному коді, тут лише десятки подій.
        home = HomePresentation(state: state)
        // Мапа малює індекс, картки приїжджають вікном; порядок один. Емісій багато (вибір у
        // каруселі, чат, прапорці завантаження), а індекс міняється рідко: перебудова лише за версією.
        let indexChanged = state.map.indexVersion != lastIndexVersion
        if indexChanged {
            lastIndexVersion = state.map.indexVersion
            indexIDs = Set(state.map.index.map(\.id))
            eventsRevision &+= 1
        }
        let selectedID = state.detail.event?.id
        if indexChanged || selectedID != lastSelectedID {
            lastSelectedID = selectedID
            let index = state.map.index
            // Подія, на яку навели з деталей, може не бути у видачі: додаємо, щоб був пін. Сеанс
            // прокату «вже там» через представника, інакше пін майданчика рахував би прокат двічі.
            if let selected = state.detail.event, !indexIDs.contains(selected.id),
               !index.contains(where: { run in run.sessions.contains { $0.id == selected.id } }) {
                mapEntries = index + [selected.asIndexEntry()]
            } else {
                mapEntries = index
            }
            entriesRevision &+= 1
        }
        if state.feedVersion != lastFeedVersion {
            lastFeedVersion = state.feedVersion
            cards = state.map.events
            cardsByID = Dictionary(uniqueKeysWithValues: state.map.events.map { ($0.id, $0) })
                .merging(state.cards.map { ($0.key as String, $0.value) }) { current, _ in current }
            cardsRevision &+= 1
        }
        // Присвоюємо лише зміну: кожне присвоєння @Published перемальовує всіх спостерігачів.
        let saved = Set(state.library.savedIds)
        if saved != savedIDs { savedIDs = saved }
        let waitlisted = Set(state.library.waitlistedIds)
        if waitlisted != waitlistedIDs { waitlistedIDs = waitlisted }
    }
    func stop() { subscription?.close(); subscription = nil }

    // ---- Потяг вниз. Kotlin-suspend кличемо з головного потоку, тож обгортки на `@MainActor`
    // моделі, а не в `.refreshable` напряму. Збій не кидає: він уже в `state.notice`.

    /// Головна: перечитати все, як при поверненні в застосунок, і дочекатись відповідей.
    func reloadAll() async { try? await app.reloadAll() }
    func reloadMyEvents() async { try? await app.reloadMyEvents() }
    func reloadEvent(id: String) async { try? await app.reloadEvent(id: id) }
    deinit { subscription?.close(); graph.close() }
}
