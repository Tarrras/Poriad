import Foundation
import Shared

/// The one action the sticky bar offers. Deriving it in a single place means the label, the tap
/// and the enabled state can never disagree — and the organizer is never offered a guest seat the
/// server would refuse.
enum DetailAction {
    case join, leave, joinWaitlist, leaveWaitlist, organizer, cancelled, none

    var title: String {
        switch self {
        case .join: "Приєднатися"
        case .leave: "Ви йдете"
        case .joinWaitlist: "Стати в чергу"
        case .leaveWaitlist: "Ви в черзі"
        case .organizer: "Ви організатор"
        case .cancelled, .none: "Скасовано"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .join, .leave, .joinWaitlist, .leaveWaitlist: true
        default: false
        }
    }
}

/// A read-only projection of the shared state for one event: computed once per render instead of
/// six times inside the view body, and the only place that decides what the screen may offer.
struct EventDetailPresentation {
    let event: Event?
    let attendees: [Attendee]
    let mutating: Bool
    let signedIn: Bool
    let saved: Bool
    let waitlisted: Bool
    let organizer: Bool

    init(state: AppState?) {
        let event = state?.selectedEvent
        self.event = event
        attendees = state?.attendees ?? []
        mutating = state?.mutating == true
        signedIn = state?.signedIn == true
        saved = event.map { state?.isSaved(id: $0.id) == true } ?? false
        waitlisted = event.map { state?.isWaitlisted(id: $0.id) == true } ?? false
        organizer = event.flatMap { state?.organizes(event: $0) } ?? false
    }

    var cancelled: Bool { event?.isCancelled == true }
    var full: Bool { event?.isFull == true }

    var action: DetailAction {
        guard let event else { return .none }
        if cancelled { return .cancelled }
        if organizer { return .organizer }
        if event.joined { return .leave }
        if waitlisted { return .leaveWaitlist }
        return full ? .joinWaitlist : .join
    }

    var seatsSummary: String {
        guard let event else { return "" }
        if cancelled { return "Подію скасовано" }
        if full && !event.joined && !organizer { return "Місць немає. Додамо вас, щойно звільниться місце." }
        return "Вільних місць: \(event.seatsLeft)"
    }
}
