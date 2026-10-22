import SwiftUI
import Shared
import Security
import AmplitudeSwift
import AmplitudeSwiftSessionReplayPlugin

final class KeychainSessionStore: SecureSessionStore {
    private let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.poruch.session", kSecAttrAccount as String: "session"]
    func read() -> String? {
        var query = base; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    /// `value_`: Kotlin/Native так експортує `write(value:)`, бо в `PendingUnregisterStore` метод з тією ж назвою.
    func write(value_ value: String) {
        let data = Data(value.utf8)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = base; query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        // Сесія не записалась — наступний запуск буде без входу. Лише код, без вмісту.
        if status != errSecSuccess { NSLog("Poruch/keychain: session write failed, status %d", status) }
    }
    func clear() {
        let status = SecItemDelete(base as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { NSLog("Poruch/keychain: session clear failed, status %d", status) }
    }
}

/// `AppModel` без підписки на `objectWillChange`: екран, що бере модель звідси, перемальовується лише
/// зі своїм станом (`@Observable` обгорткою презентера), а не на кожну емісію стору.
private struct AppModelKey: EnvironmentKey { static let defaultValue: AppModel? = nil }
extension EnvironmentValues {
    /// Неявно розгорнутий: ключ пишеться через get-set, і примусове розгортання в getter падало ще до запису.
    var appModel: AppModel! {
        get { self[AppModelKey.self] }
        set { self[AppModelKey.self] = newValue }
    }
}

/// Вісім полів, яких треба кореню (онбординг, таббар, листи, банер): `@Observable` поштучно, тож `RootView`
/// із таббаром і чотирма стеками перераховується лише коли змінилось одне з них, а не на кожну емісію стору.
@MainActor @Observable final class RootScreenModel {
    /// Стан уже є: до того невідомо, чи потрібен онбординг.
    private(set) var ready = false
    private(set) var needsOnboarding = false
    private(set) var digestEnabled = true
    private(set) var followsMade: Int32 = 0
    private(set) var savesMade: Int32 = 0
    private(set) var reviewMoment = false
    private(set) var waitingEvents = 0
    /// Нове в підписках: крапка на «Профілі».
    private(set) var newFollows = false
    private(set) var signedIn = false
    private(set) var passwordRecovery = false
    private(set) var notice: AppNotice?

    func apply(_ state: AppState) {
        if !ready { ready = true }
        if needsOnboarding != state.needsOnboarding { needsOnboarding = state.needsOnboarding }
        if digestEnabled != state.digestEnabled { digestEnabled = state.digestEnabled }
        if followsMade != state.library.followsMade { followsMade = state.library.followsMade }
        if savesMade != state.library.savesMade { savesMade = state.library.savesMade }
        if reviewMoment != state.reviewMoment { reviewMoment = state.reviewMoment }
        let waiting = Int(state.waitingEvents)
        if waitingEvents != waiting { waitingEvents = waiting }
        let follows = state.library.newFollowEvents > 0
        if newFollows != follows { newFollows = follows }
        if signedIn != state.signedIn { signedIn = state.signedIn }
        if passwordRecovery != state.session.passwordRecovery { passwordRecovery = state.session.passwordRecovery }
        // Kotlin-інтерфейс — протокол без `Equatable`: порівнюємо за посиланням, обʼєкт сповіщення один на емісію.
        if (notice as AnyObject?) !== (state.notice as AnyObject?) { notice = state.notice }
    }
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

    /// Головна: стан екрана зі спільного `HomePresenter`, той самий, що й на Android. Спостерігається
    /// окремо від `AppModel`, тож головна перемальовується лише зі своїм станом.
    let root = RootScreenModel()
    lazy var homeScreen = HomeScreenModel(app: app)
    lazy var exploreScreen = ExploreScreenModel(app: app)
    lazy var myEventsScreen = MyEventsScreenModel(app: app)

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
        // Адреса, ключ і схема — лише свого середовища, з Config.xcconfig через Info.plist: prod-бінарник
        // не несе dev. Без значень спільний шар каже «не налаштовано», а не йде кудись навмання.
        let config = AppConfig(
            supabaseUrl: info["SUPABASE_URL"] as? String ?? "",
            publishableKey: info["SUPABASE_KEY"] as? String ?? "",
            home: HomeLocation.companion.Kyiv,
            authScheme: info["APP_AUTH_SCHEME"] as? String ?? "poriad",
            appVersion: info["CFBundleShortVersionString"] as? String ?? "dev",
            geocoderUrl: "https://photon.komoot.io/api/"
        )
        // Один центр сповіщень для нагадувань і запитів: делегат у нього теж один.
        let notifications = LocalReminderScheduler.shared
        graph = AppGraph(config: config, sessionStore: KeychainSessionStore(), reminders: notifications, requestNotifier: notifications, chatNotifier: notifications)
        PoruchLog.shared.i(tag: "app") { "graph created" }
        // Amplitude — після графа: збережена відмова від аналітики вже в PoruchAnalytics і діє з першої
        // події. Мережевий автозбір не вмикаємо: URL запитів несуть id. Replay ховає весь текст — те саме
        // правило «жодних імен і текстів», що й для подій. Перемикач у профілі далі веде optOut разом із Firebase.
        if let key = info["AMPLITUDE_API_KEY"] as? String, !key.isEmpty {
            let amplitude = Amplitude(configuration: Configuration(
                apiKey: key, optOut: !PoruchAnalytics.shared.enabled,
                autocapture: AutocaptureOptions.all.subtracting(.networkTracking)
            ))
            amplitude.add(plugin: AmplitudeSwiftSessionReplayPlugin(sampleRate: 1, maskLevel: .conservative))
            let firebase = PoruchAnalytics.shared.collection
            PoruchAnalytics.shared.collection = { enabled in
                firebase?(enabled)
                amplitude.optOut = !enabled.boolValue
            }
        } else {
            PoruchLog.shared.w(tag: "analytics") { "Amplitude API key missing — analytics disabled" }
        }
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
        if self.state?.session.userId != nil && state.session.userId == nil { EventEditorModel.clearDrafts() }
        self.state = state
        root.apply(state)
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
