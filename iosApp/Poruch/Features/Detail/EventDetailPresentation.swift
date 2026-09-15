import Foundation
import Shared

/// Єдина дія нижньої панелі. Рахується в одному місці, щоб підпис, тап і доступність не розходились.
enum DetailAction {
    case join, request, requested, leave, joinWaitlist, leaveWaitlist, organizer, cancelled
    /// Афіша: сторінка джерела.
    case tickets
    /// Кнопки нема: афіша без посилання, знята подія або зіпсований рядок.
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

/// Проєкція спільного стану для однієї події: рахується раз на рендер і єдина вирішує, що екран пропонує.
struct EventDetailPresentation {
    let event: Event?
    let attendees: [Attendee]
    let mutating: Bool
    let signedIn: Bool
    let saved: Bool
    let waitlisted: Bool
    let organizer: Bool
    /// Хто проситься. Непорожньо лише для організатора.
    let requests: [Attendee]
    /// Сеанс прокату вже почався: показати можна, купити квиток — ні. Тижневої виставки не стосується.
    let sessionStarted: Bool

    /// `sessions` — карусель дат: від неї залежить лише, чи ховати кнопку квитка на сеансі, що почався.
    init(state: AppState?, eventID: String, sessions: [EventSession] = []) {
        // Лише відкрита подія або інша дата її прокату: знімок стану в першу мить ще тримає попередню.
        let event = state?.selectedEvent.flatMap { selected in
            selected.id == eventID || sessions.contains(where: { $0.id == selected.id }) ? selected : nil
        }
        self.event = event
        attendees = state?.attendees ?? []
        mutating = state?.mutating == true
        signedIn = state?.signedIn == true
        // Від обраної картки: після перемикання дати зберігається той вечір, що на екрані.
        saved = event.map { state?.isSaved(id: $0.id) == true } ?? false
        waitlisted = event.map { state?.isWaitlisted(id: $0.id) == true } ?? false
        organizer = event.flatMap { state?.organizes(event: $0) } ?? false
        requests = state?.joinRequests ?? []
        sessionStarted = event.map { sessions.count > 1 && !$0.isMultiDay && $0.hasStarted(now: nowInstant()) } ?? false
    }

    var cancelled: Bool { event?.isCancelled == true }

    /// Кімната, якщо це кімната. Місця й участь лише в неї.
    var room: Gathering? { event?.gathering }

    /// Оголошення, якщо це афіша. Тоді дія одна: вийти на джерело.
    var listing: Listing? { event?.listing }

    var full: Bool { room?.isFull == true }

    /// Афіша відгалужується першою: кнопка «приєднатися», яка гарантовано отримає відмову, гірша за відсутність кнопки.
    var action: DetailAction {
        guard event != nil else { return .none }
        if cancelled { return .cancelled }
        if let listing { return listing.isWithdrawn || !listing.hasSource || sessionStarted ? .none : .tickets }
        if organizer { return .organizer }
        // Ні кімнати, ні оголошення — зіпсований рядок: без дій.
        guard let room else { return .none }
        if room.awaitingApproval { return .requested }
        if room.joined { return .leave }
        if waitlisted { return .leaveWaitlist }
        if room.approvalRequired { return .request }
        return room.isFull ? .joinWaitlist : .join
    }

    /// Рядок під датою в нижній панелі: місця й черга для кімнати, ціна або причина відсутності кнопки для афіші.
    var seatsSummary: String {
        guard event != nil else { return "" }
        if cancelled { return "Подію скасовано" }
        if let listing {
            if listing.isWithdrawn { return "Джерело зняло цю подію. Запис лишається у вас як позначка." }
            if sessionStarted { return "Сеанс уже почався, квитки на нього не продають. Оберіть іншу дату." }
            return listing.hasSource ? listingPrice(listing) : "Подія з афіші. Ми лише показуємо її."
        }
        guard let room else { return "" }
        if room.awaitingApproval { return "Організатор ще не відповів" }
        if room.approvalRequired && !room.joined && !organizer { return "Ви вирішуєте, хто приєднається до події." }
        if room.isFull && !room.joined && !organizer { return "Місць немає. Додамо вас, щойно звільниться місце." }
        return "Вільних місць: \(room.seatsLeft)"
    }
}

/// Для кого подія, на картці, а не через відмову сервера.
func ageLimitLabel(_ room: Gathering) -> String? {
    guard room.hasAgeLimit else { return nil }
    if let maximum = room.maxAge { return "\(room.minAge)–\(maximum.intValue) років" }
    return "\(room.minAge)+"
}

/// Причини скарги в порядку шторки.
let reportReasons: [(value: String, title: String)] = [
    (ReportReason.shared.MINORS, "Небезпечно для неповнолітніх"),
    (ReportReason.shared.SAFETY, "Загроза безпеці"),
    (ReportReason.shared.HARASSMENT, "Домагання або образи"),
    (ReportReason.shared.SCAM, "Шахрайство"),
    (ReportReason.shared.SPAM, "Спам"),
    (ReportReason.shared.OTHER, "Інше")
]
