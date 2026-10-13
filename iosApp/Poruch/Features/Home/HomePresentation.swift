import Foundation
import Observation
import Shared

/// Стан головної складає спільний `HomePresenter` — та сама згортка, що й на Android, раз на зміну входів і
/// не на головному потоці. Тут лише спостережувана обгортка: `@Observable` стежить за `state` поштучно, тож
/// `HomeView` перемальовується зі своїм станом, а не з кожною емісією `AppModel`.
@MainActor @Observable final class HomeScreenModel {
    private(set) var state = HomeScreenState.companion.Empty
    private let presenter: HomePresenter
    private var subscription: Subscription?

    init(app: PoruchApp) {
        presenter = HomePresenter(app: app)
        subscription = presenter.observe { [weak self] state in self?.state = state }
    }

    /// Чип над сіткою: сітку збирає презентер, тож чип — його вхід.
    func selectFeedFilter(_ filter: FeedFilter) { presenter.selectFeedFilter(filter: filter) }

    // Без `deinit`: модель живе стільки, скільки `AppModel`, тобто весь процес, а підписку й презентер
    // із неізольованого `deinit` MainActor-класу закрити не можна.
}

extension HomeScreenState {
    /// Де шукає поле: без цього неочевидно, що пошук іде лише в обраному місті.
    var searchScope: String { searchEverywhere ? Copy.scope_everywhere : Copy.scope_in_city("\(cityName)") }
    /// Id усього знайденого, у порядку видачі: з нього довантажують картки наступного шматка.
    var resultIDs: [String] { resultIds }
    /// Перші `limit` знайдених, чиї картки вже приїхали, у порядку видачі.
    func results(limit: Int) -> [Event] { Array(results.prefix(limit)) }
    func isSaved(_ event: Event) -> Bool { isSaved(id: event.id) }
    func isWaitlisted(_ event: Event) -> Bool { isWaitlisted(id: event.id) }
}

extension PersonalRow: Identifiable {
    public var id: String { event.id }
}

/// Кількість великих карток над сіткою «У місті»: одне число з домену, бо стрічка кладе в них зустрічі від людей.
let homeHeroCount = Int(HomeRules.shared.HERO_COUNT)
/// Скільки результатів пошуку показує головна.
let homeResultsLimit = 12
