import Foundation
import Shared

/// Списки головної, зібрані раз зі спільного стану, а не в тілі view на кожне перемальовування.
struct HomePresentation {
    let signedIn: Bool
    let cityName: String
    /// Стрічка головної ще їде.
    let loading: Bool
    /// Пошук головної ще їде.
    let searchLoading: Bool
    /// Плани: організую або йду, найближчі першими.
    let plans: [Event]
    /// Мої події, де чекають запити на участь, зі скількома. Лише в організатора.
    let requests: [PendingRequests]
    /// Чати з непрочитаним, свіжіші першими, разом із карткою події для відкриття чату.
    let unread: [UnreadChat]
    /// Добірка за відповідями онбордингу. Порожня, якщо не відповідали.
    let suggested: [Event]
    let today: [Event]
    /// Решта поза дайджестом. Головна лише каже, скільки її.
    let rest: [Event]
    /// Скільки подій в області, без фільтрів мапи.
    let totalFound: Int
    /// Пошук головної, окремий від мапи: фільтр одного екрана не порожнить інший.
    let searchText: String
    /// Результати пошуку одним списком, без дайджесту. Лише ті, чиї картки вже приїхали.
    let results: [Event]
    /// Скільки знайдено насправді.
    let resultsTotal: Int

    var searching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Місто з подіями, назване в пошуку, крім поточного: текстовий пошук іде лише в межах міста.
    var cityMatch: HomeLocation? { searching ? HomeLocation.companion.mentioned(query: searchText, current: cityName) : nil }

    /// Що означає «поруч»: завжди ціле місто. «Шукати тут» на мапі головну не звужує.
    var areaLabel: String { "Плани на найближчі дні у місті \(cityName)" }

    private let savedIds: Set<String>
    private let waitlistedIds: Set<String>

    init(state: AppState?) {
        signedIn = state?.signedIn == true
        cityName = state?.cityName ?? HomeLocation.companion.Kyiv.city
        // Своя стрічка: та сама область, що на мапі, але без її фільтрів.
        let home = state?.home
        loading = home?.loading == true
        searchLoading = home?.searchLoading == true
        totalFound = Int(home?.totalFound ?? 0)
        resultsTotal = Int(home?.resultsTotal ?? 0)
        searchText = home?.searchText ?? ""
        savedIds = Set(state?.savedIds ?? [])
        waitlistedIds = Set(state?.waitlistedIds ?? [])
        // І свої, і ті, куди йду: `concerns` — те саме правило, що в нагадуваннях. Лише те, що ще не завершилось, як на Android.
        let mine = state?.myEvents ?? []
        let now = nowInstant()
        plans = mine.filter { state?.concerns(event: $0) == true && $0.isPublished && $0.isCurrent(now: now) }.sorted { $0.startsAt < $1.startsAt }
        requests = HomePresentation.pendingRequests(state?.pendingRequests ?? [], among: mine)
        let mineById = Dictionary(mine.map { ($0.id, $0) }) { first, _ in first }
        unread = (state?.chatUnread ?? []).compactMap { u in mineById[u.eventId].map { UnreadChat(summary: u, event: $0) } }

        // Увесь екран в одному порядку. Картки до індексу прив'язує спільний код: тут лише
        // завантажені, десятки, а не тисячі записів індексу через міст.
        let ranked = home?.events ?? []
        suggested = Array((home?.suggested ?? []).prefix(homeSuggestedLimit))
        // Те, що вже в «Для вас», нижче не повторюємо.
        let shown = Set(suggested.map(\.id))
        let remaining = ranked.filter { !shown.contains($0.id) }
        // «Сьогодні» — куди можна піти сьогодні, включно з прокатами. Але те, що сьогодні
        // починається, йде першим: прокат буде відкритий і завтра. `Calendar.current` — новий
        // об'єкт на кожне звертання, тому один на цикл.
        let calendar = Calendar.current
        var startingToday: [Event] = []
        var later: [Event] = []
        for event in remaining {
            if let date = parseEventDate(event.startsAt), calendar.isDateInToday(date) {
                startingToday.append(event)
            } else {
                later.append(event)
            }
        }
        let runningToday = later.filter { $0.isUnderway(now: now) }
        today = startingToday + runningToday
        let shownToday = Set(runningToday.map(\.id))
        rest = later.filter { !shownToday.contains($0.id) }
        results = home?.found ?? []
    }

    var isEmpty: Bool { suggested.isEmpty && today.isEmpty && rest.isEmpty }

    /// Запити за подіями, у порядку стрічки (свіжіші першими). Подія без картки в «моїх» пропускається.
    private static func pendingRequests(_ requests: [JoinRequest], among events: [Event]) -> [PendingRequests] {
        guard !requests.isEmpty else { return [] }
        let counts = RequestRules.shared.pendingByEvent(requests: requests)
        let cards = Dictionary(events.map { ($0.id, $0) }) { first, _ in first }
        var seen = Set<String>()
        return requests.compactMap { request in
            guard seen.insert(request.eventId).inserted, let event = cards[request.eventId] else { return nil }
            return PendingRequests(event: event, count: counts[request.eventId].map { Int(truncating: $0) } ?? 0)
        }
    }
    func isSaved(_ event: Event) -> Bool { savedIds.contains(event.id) }
    func isWaitlisted(_ event: Event) -> Bool { waitlistedIds.contains(event.id) }
}

/// Непрочитане в чаті з карткою події: чат відкривається з події, а не з id.
struct UnreadChat: Identifiable {
    let summary: ChatUnread
    let event: Event
    var id: String { event.id }
}

/// Подія й скільки людей просяться до неї.
struct PendingRequests: Identifiable {
    let event: Event
    let count: Int
    var id: String { event.id }
}

/// Головна — дайджест, а не каталог: далі краще на мапу.
let homeTodayLimit = 5
/// Більше за це «для вас» перестає бути добіркою.
let homeSuggestedLimit = 4
/// Скільки результатів пошуку показує головна.
let homeResultsLimit = 12
let homePlansLimit = 8
