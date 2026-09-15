import Foundation
import Shared

/// Списки головної, зібрані раз зі спільного стану, а не в тілі view на кожне перемальовування.
struct HomePresentation {
    let signedIn: Bool
    let cityName: String
    let loading: Bool
    /// Плани, до яких приєднались, найближчі першими.
    let plans: [Event]
    /// Добірка за відповідями онбордингу. Порожня, якщо не відповідали.
    let suggested: [Event]
    let today: [Event]
    /// Решта поза дайджестом. Головна лише каже, скільки її.
    let rest: [Event]
    /// Скільки подій в області, те саме число, що на мапі.
    let totalFound: Int
    /// Область поставили рукою через «Шукати тут».
    let customArea: Bool
    /// Той самий пошук, що на мапі: другого джерела правди нема.
    let searchText: String
    /// Результати пошуку одним списком, без дайджесту.
    let results: [Event]

    var searching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Що означає «поруч»: місто зі списку чи область на мапі.
    var areaLabel: String {
        customArea
            ? "Плани в області, яку ви обрали на мапі"
            : "Плани на найближчі дні у місті \(cityName)"
    }

    private let savedIds: Set<String>
    private let waitlistedIds: Set<String>

    init(state: AppState?) {
        signedIn = state?.signedIn == true
        cityName = state?.cityName ?? HomeLocation.companion.Kyiv.city
        loading = state?.loading == true
        totalFound = Int(state?.totalFound ?? 0)
        customArea = state?.customArea == true
        searchText = state?.searchText ?? ""
        savedIds = Set(state?.savedIds ?? [])
        waitlistedIds = Set(state?.waitlistedIds ?? [])
        plans = (state?.myEvents ?? []).filter { $0.gathering?.joined == true && $0.isPublished }.sorted { $0.startsAt < $1.startsAt }

        // Увесь екран в одному порядку. Кожне звертання до Kotlin-списку — міст, тому читаємо раз у змінну.
        let cards = state?.cards ?? [:]
        let ranked = (state?.index ?? []).compactMap { cards[$0.id] }
        suggested = Array((state?.suggestedIndex ?? [])
            .compactMap { cards[$0.id] }
            .prefix(homeSuggestedLimit))
        // Те, що вже в «Для вас», нижче не повторюємо.
        let shown = Set(suggested.map(\.id))
        let remaining = ranked.filter { !shown.contains($0.id) }
        // «Сьогодні» — куди можна піти сьогодні, включно з прокатами. Але те, що сьогодні
        // починається, йде першим: прокат буде відкритий і завтра. `Calendar.current` — новий
        // об'єкт на кожне звертання, тому один на цикл.
        let calendar = Calendar.current
        let now = nowInstant()
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
        results = ranked
    }

    var isEmpty: Bool { searching ? results.isEmpty : suggested.isEmpty && today.isEmpty && rest.isEmpty }
    func isSaved(_ event: Event) -> Bool { savedIds.contains(event.id) }
    func isWaitlisted(_ event: Event) -> Bool { waitlistedIds.contains(event.id) }
}

/// Головна — дайджест, а не каталог: далі краще на мапу.
let homeTodayLimit = 5
/// Більше за це «для вас» перестає бути добіркою.
let homeSuggestedLimit = 4
/// Скільки результатів пошуку показує головна.
let homeResultsLimit = 12
let homePlansLimit = 8
