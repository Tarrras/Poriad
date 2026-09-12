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

    /**
     Події для мапи й каруселі, зібрані **один раз на емісію стану**.

     Кожен доступ до `state.recommended` — це перехід через міст у Kotlin, а `$0.id` усередині —
     ще один на кожен елемент. Поки це була обчислювана властивість екрана, вона рахувалася по
     кілька разів за кожне перемальовування, а перемальовування трапляється на кожен крок каруселі.
     */
    @Published private(set) var mapEntries: [EventIndexEntry] = []
    /// Картки в порядку показу: те, що вже завантажилось. Їх може бути менше за [mapEntries].
    @Published private(set) var cards: [Event] = []
    /**
     Усі завантажені картки за ідентифікатором.

     [cards] — це суцільний початок стрічки, який обривається на першій незавантаженій події. Стос
     майданчика лежить не на початку: його події розкидані по всьому індексу, тож зібрати їх можна
     лише звідси. Без цього пін казав «32», а карусель під ним — «Тут подій: 3».
     */
    @Published private(set) var cardsByID: [String: Event] = [:]

    /// Змінюється лише тоді, коли справді змінився склад подій, а не будь-який стан застосунку.
    /// Дешевий ключ замість порівняння списків там, де інакше довелося б їх щоразу обходити.
    @Published private(set) var eventsRevision = 0

    /// Набори, а не масиви з Kotlin: у списку кожна картка питає «а я збережена?», і з масивом це
    /// був би лінійний пошук через міст — на кожен рядок, на кожне перемальовування.
    @Published private(set) var savedIDs: Set<String> = []
    @Published private(set) var waitlistedIDs: Set<String> = []

    /**
     Три списки, які показує головна, зібрані **один раз на емісію стану**.

     Поки це рахувалося в тілі екрана, воно рахувалося на кожне його обчислення — а SwiftUI
     обчислює тіло по кілька разів на одну зміну. Виміряно: одна побудова коштувала ~12 мс, тобто
     більше за кадр, і повторювалась вона й тоді, коли головна лишалась за іншою вкладкою.
     */
    @Published private(set) var home = HomePresentation(state: nil)

    let reminders = EventReminders()
    private var subscription: Subscription?
    private var lastIndexIDs: [String] = []
    init() {
        // Tracing is a debug-build tool; release keeps the sinks silent.
        #if DEBUG
        PoruchLog.shared.enabled = true
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        let config = AppConfig(
            supabaseUrl: info["SUPABASE_URL"] as? String ?? "",
            publishableKey: info["SUPABASE_PUBLISHABLE_KEY"] as? String ?? "",
            home: HomeLocation.companion.Kyiv
        )
        graph = AppGraph(config: config, sessionStore: KeychainSessionStore())
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
        self.state = state
        home = HomePresentation(state: state)
        // Мапа малює **індекс** — усе, що є в області. Картки приїжджають вікном і їх менше;
        // порядок у обох один. Доти, доки мапа малювала картки, вона показувала стільки подій,
        // скільки встигло завантажитись, і стеля в 300 рядків була видна просто пінами.
        let index = state.index
        let ids = index.map(\.id)
        if ids != lastIndexIDs {
            lastIndexIDs = ids
            eventsRevision &+= 1
        }
        // Подія, заради якої мапу відкрили з деталей, могла не потрапити у поточну видачу (інший
        // фільтр, інша область) — тоді на мапі не було б ні піна, ні на що наводитись.
        if let selected = state.selectedEvent, !ids.contains(selected.id) {
            mapEntries = index + [selected.asIndexEntry()]
        } else {
            mapEntries = index
        }
        cards = state.events
        cardsByID = Dictionary(uniqueKeysWithValues: state.events.map { ($0.id, $0) })
            .merging(state.cards.map { ($0.key as String, $0.value) }) { current, _ in current }
        savedIDs = Set(state.savedIds)
        waitlistedIDs = Set(state.waitlistedIds)
        reminders.reconcile(state)
    }
    func stop() { subscription?.close(); subscription = nil }
    deinit { subscription?.close(); graph.close() }
}
