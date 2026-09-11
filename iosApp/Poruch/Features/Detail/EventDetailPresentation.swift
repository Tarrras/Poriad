import Foundation
import Shared

/// The one action the sticky bar offers. Deriving it in a single place means the label, the tap
/// and the enabled state can never disagree — and the organizer is never offered a guest seat the
/// server would refuse.
enum DetailAction {
    case join, request, requested, leave, joinWaitlist, leaveWaitlist, organizer, cancelled
    /// Афіша: єдина дія — сторінка джерела, де її продають і де лежить повний опис.
    case tickets
    /// Немає що запропонувати: афіша без посилання, знята подія або зіпсований рядок. Кнопки теж немає.
    case none

    var title: String {
        switch self {
        case .join: "Приєднатися"
        case .request: "Надіслати запит"
        case .requested: "Запит надіслано"
        case .leave: "Ви йдете"
        case .joinWaitlist: "Стати в чергу"
        case .leaveWaitlist: "Ви в черзі"
        case .organizer: "Ви організатор"
        case .tickets: "Купити квиток"
        case .cancelled, .none: "Скасовано"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .join, .request, .leave, .joinWaitlist, .leaveWaitlist, .tickets: true
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
    /// People asking to come. Only ever non-empty for the organizer of this event.
    let requests: [Attendee]

    init(state: AppState?) {
        let event = state?.selectedEvent
        self.event = event
        attendees = state?.attendees ?? []
        mutating = state?.mutating == true
        signedIn = state?.signedIn == true
        saved = event.map { state?.isSaved(id: $0.id) == true } ?? false
        waitlisted = event.map { state?.isWaitlisted(id: $0.id) == true } ?? false
        organizer = event.flatMap { state?.organizes(event: $0) } ?? false
        requests = state?.joinRequests ?? []
    }

    var cancelled: Bool { event?.isCancelled == true }

    /// Кімната цієї події, якщо вона взагалі кімната. Місця й участь питають тільки в неї.
    var room: Gathering? { event?.gathering }

    /// Оголошення, якщо це афіша. Тоді дій рівно одна — вийти на джерело.
    var listing: Listing? { event?.listing }

    var full: Bool { room?.isFull == true }

    /// Афіша відгалужується першою й ніколи не доходить до участі. Це не дублювання серверного
    /// `assert_can_join`, а його наслідок: кнопка «приєднатися», яка гарантовано отримає
    /// `IMPORTED_EVENT`, гірша за відсутність кнопки.
    var action: DetailAction {
        guard event != nil else { return .none }
        if cancelled { return .cancelled }
        if let listing { return listing.isWithdrawn || !listing.hasSource ? .none : .tickets }
        if organizer { return .organizer }
        // Ні кімнати, ні оголошення — зіпсований рядок. Показуємо подію, не пропонуємо дій.
        guard let room else { return .none }
        if room.awaitingApproval { return .requested }
        if room.joined { return .leave }
        if waitlisted { return .leaveWaitlist }
        if room.approvalRequired { return .request }
        return room.isFull ? .joinWaitlist : .join
    }

    /// Рядок під датою в нижній панелі: одна фраза про те, що зараз можливо. Для кімнати це місця
    /// й черга, для афіші — ціна або причина, чому кнопки немає.
    var seatsSummary: String {
        guard event != nil else { return "" }
        if cancelled { return "Подію скасовано" }
        if let listing {
            if listing.isWithdrawn { return "Джерело зняло цю подію. Запис лишається у вас як позначка." }
            return listing.hasSource ? listingPrice(listing) : "Подія з афіші. Ми лише показуємо її."
        }
        guard let room else { return "" }
        if room.awaitingApproval { return "Організатор ще не відповів" }
        if room.approvalRequired && !room.joined && !organizer { return "Ви вирішуєте, хто приєднається до події." }
        if room.isFull && !room.joined && !organizer { return "Місць немає. Додамо вас, щойно звільниться місце." }
        return "Вільних місць: \(room.seatsLeft)"
    }
}

/// Who the evening is for, said on the card rather than discovered when the server refuses.
/// Обмежень віку в афіші не буває: їх встановлює організатор, якого в неї немає.
func ageLimitLabel(_ room: Gathering) -> String? {
    guard room.hasAgeLimit else { return nil }
    if let maximum = room.maxAge { return "\(room.minAge)–\(maximum.intValue) років" }
    return "\(room.minAge)+"
}

/// Why somebody is reporting, in the order the sheet offers the reasons.
let reportReasons: [(value: String, title: String)] = [
    (ReportReason.shared.MINORS, "Небезпечно для неповнолітніх"),
    (ReportReason.shared.SAFETY, "Загроза безпеці"),
    (ReportReason.shared.HARASSMENT, "Домагання або образи"),
    (ReportReason.shared.SCAM, "Шахрайство"),
    (ReportReason.shared.SPAM, "Спам"),
    (ReportReason.shared.OTHER, "Інше")
]
