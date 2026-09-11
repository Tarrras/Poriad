import Foundation
import Shared

/// The three lists home shows, derived once from the shared state rather than recomputed inside
/// the view body on every redraw.
struct HomePresentation {
    let signedIn: Bool
    let cityName: String
    let loading: Bool
    /// Plans this account joined, soonest first.
    let plans: [Event]
    /// What the opening answers picked out. Empty when nothing was answered — never a filler.
    let suggested: [Event]
    let today: [Event]
    let rest: [Event]
    /**
     Категорія, обрана **на цьому екрані**. Мапа має свою.

     Доки категорія була одна на застосунок, вибір на головній переставляв фільтр мапи й навпаки:
     два перемикачі, одне значення. Тепер кожен екран звужує те, що показує сам.
     */
    let category: String
    /**
     Пошук — той самий, що й на мапі.

     Другий пошук поруч із першим означав би два джерела правди: тут знайшлось, там ні. Тому
     головна не шукає сама, а відкриває двері до того ж запиту — і бачить ту саму видачу, з якої
     і так малює свої списки.
     */
    let searchText: String
    /// Уся видача одним списком: дайджест із результатів пошуку не складають.
    let results: [Event]

    var searching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private let savedIds: Set<String>
    private let waitlistedIds: Set<String>

    init(state: AppState?, category: String = AppStateKt.ALL_CATEGORIES) {
        signedIn = state?.signedIn == true
        cityName = state?.cityName ?? HomeLocation.companion.Kyiv.city
        loading = state?.loading == true
        self.category = category
        searchText = state?.searchText ?? ""
        savedIds = Set(state?.savedIds ?? [])
        waitlistedIds = Set(state?.waitlistedIds ?? [])
        plans = (state?.myEvents ?? []).filter { $0.gathering?.joined == true && $0.isPublished }.sorted { $0.startsAt < $1.startsAt }

        // Everything below reads the ranked list, so the whole screen is in one order.
        //
        // Кожне звертання до списку з Kotlin — це міст: сто сорок подій, зібраних заново. Тому
        // читаємо по одному разу в локальну змінну, а не двічі в одному виразі.
        // Звужується індекс, а не завантажені картки: під фільтром перші події категорії майже
        // завжди лежать далі за край вікна, і фільтрувати вікно означало б показати порожню
        // головну там, де подій насправді десятки.
        let all = category == AppStateKt.ALL_CATEGORIES
        let cards = state?.cards ?? [:]
        let ranked = (state?.index ?? [])
            .filter { all || $0.category == category }
            .compactMap { cards[$0.id] }
        suggested = Array((state?.suggestedIndex ?? [])
            .filter { all || $0.category == category }
            .compactMap { cards[$0.id] }
            .prefix(homeSuggestedLimit))
        // What is already under «Для вас» is not repeated further down the same screen.
        let shown = Set(suggested.map(\.id))
        let remaining = ranked.filter { !shown.contains($0.id) }
        // `Calendar.current` — не константа, а новий календар на кожне звертання. У циклі на сто
        // сорок подій це сто сорок календарів заради одного порівняння днів.
        let calendar = Calendar.current
        let startingToday = remaining.filter { event in
            guard let date = parseEventDate(event.startsAt) else { return false }
            return calendar.isDateInToday(date)
        }
        today = startingToday
        let todayIds = Set(startingToday.map(\.id))
        rest = remaining.filter { !todayIds.contains($0.id) }
        results = ranked
    }

    var isEmpty: Bool { searching ? results.isEmpty : suggested.isEmpty && today.isEmpty && rest.isEmpty }
    func isSaved(_ event: Event) -> Bool { savedIds.contains(event.id) }
    func isWaitlisted(_ event: Event) -> Bool { waitlistedIds.contains(event.id) }
}

/// Home is a digest, not a catalogue: past these counts the map is the better place to look.
let homeTodayLimit = 5
/// Home is a digest: past this many, «для вас» stops being a shortlist and becomes the list.
let homeSuggestedLimit = 4
let homeRestLimit = 8
/// Скільки результатів показує головна. Далі краще на мапу: там область і фільтри.
let homeResultsLimit = 12
let homePlansLimit = 8

/// Скільки карток головна просить під власний фільтр: більше за це вона не показує в жодному стані.
let homeCards = 24
