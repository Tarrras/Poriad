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
    let reminders = EventReminders()
    private var subscription: Subscription?
    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        graph = AppGraph(config: AppConfig(supabaseUrl: info["SUPABASE_URL"] as? String ?? "", publishableKey: info["SUPABASE_PUBLISHABLE_KEY"] as? String ?? ""), sessionStore: KeychainSessionStore())
        start()
    }
    func start() {
        guard subscription == nil else { return }
        subscription = app.observe { [weak self] state in
            DispatchQueue.main.async { self?.state = state; self?.reminders.reconcile(state) }
        }
    }
    func stop() { subscription?.close(); subscription = nil }
    deinit { subscription?.close(); graph.close() }
}

let categories: [(String, String, String)] = [("all", "Усі", "square.grid.2x2"), ("music", "Музика", "music.note"), ("sport", "Спорт", "figure.run"), ("art", "Мистецтво", "paintpalette"), ("food", "Їжа", "fork.knife"), ("games", "Ігри", "dice"), ("outdoors", "Природа", "leaf"), ("social", "Зустрічі", "person.2")]
func categoryName(_ key: String) -> String { categories.first { $0.0 == key }?.1 ?? key }
func parseEventDate(_ value: String) -> Date? {
    let parser = ISO8601DateFormatter()
    if let date = parser.date(from: value) { return date }
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser.date(from: value)
}
func eventDate(_ event: Event) -> String {
    guard let date = parseEventDate(event.startsAt) else { return event.startsAt }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "uk_UA"); formatter.timeZone = TimeZone(identifier: event.timeZone); formatter.dateFormat = "d MMMM · HH:mm z"
    return formatter.string(from: date)
}
