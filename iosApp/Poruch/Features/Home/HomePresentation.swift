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
    let today: [Event]
    let rest: [Event]
    let selectedCategory: String

    private let savedIds: Set<String>
    private let waitlistedIds: Set<String>

    init(state: AppState?) {
        signedIn = state?.signedIn == true
        cityName = state?.cityName ?? HomeLocation.companion.Kyiv.city
        loading = state?.loading == true
        selectedCategory = state?.category ?? AppStateKt.ALL_CATEGORIES
        savedIds = Set(state?.savedIds ?? [])
        waitlistedIds = Set(state?.waitlistedIds ?? [])
        plans = (state?.myEvents ?? []).filter { $0.joined && $0.isPublished }.sorted { $0.startsAt < $1.startsAt }

        let events = state?.events ?? []
        let startingToday = events.filter { event in
            guard let date = parseEventDate(event.startsAt) else { return false }
            return Calendar.current.isDateInToday(date)
        }
        today = startingToday
        let todayIds = Set(startingToday.map(\.id))
        rest = events.filter { !todayIds.contains($0.id) }
    }

    var isEmpty: Bool { today.isEmpty && rest.isEmpty }
    func isSaved(_ event: Event) -> Bool { savedIds.contains(event.id) }
    func isWaitlisted(_ event: Event) -> Bool { waitlistedIds.contains(event.id) }
}

/// Home is a digest, not a catalogue: past these counts the map is the better place to look.
let homeTodayLimit = 5
let homeRestLimit = 8
let homePlansLimit = 8
