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
            DispatchQueue.main.async { self?.state = state; self?.reminders.reconcile(state) }
        }
    }
    func stop() { subscription?.close(); subscription = nil }
    deinit { subscription?.close(); graph.close() }
}
